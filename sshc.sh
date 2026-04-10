#!/bin/bash
### 2026.4.11
### ssh check.检查当天尝试登录ssh的ip信息。
### v1.1
SINCE="${1:-today}"

# ===============================
# ANSI 颜色（终端输出时启用，重定向文件时自动关闭）
# ===============================
if [ -t 1 ]; then
    RED='\033[0;31m';    LRED='\033[1;31m'
    YELLOW='\033[0;33m'; CYAN='\033[0;36m'
    BLUE='\033[0;34m';   MAGENTA='\033[0;35m'
    GRAY='\033[0;90m';   BOLD='\033[1m'
    GREEN='\033[0;32m';  RESET='\033[0m'
else
    RED=''; LRED=''; YELLOW=''; CYAN=''
    BLUE=''; MAGENTA=''; GRAY=''; BOLD=''
    GREEN=''; RESET=''
fi

geo_color() {
    case "$1" in
        China*)           echo -n "$RED"     ;;
        Russia*)          echo -n "$LRED"    ;;
        "United States"*) echo -n "$BLUE"    ;;
        "United Kingdom"*)echo -n "$CYAN"    ;;
        Indonesia*)       echo -n "$YELLOW"  ;;
        "Hong Kong"*)     echo -n "$MAGENTA" ;;
        Unknown*)         echo -n "$GRAY"    ;;
        *)                echo -n "$GREEN"   ;;
    esac
}

echo -e "${BOLD}=== SSH Failed Login Report ===${RESET}"
echo -e "${GRAY}Time range: $SINCE${RESET}"
echo

# ===============================
# 1. 环境检查
# ===============================
if ! command -v journalctl >/dev/null 2>&1; then
    echo "[ERROR] journalctl not found. Abort."; exit 1
fi
for pkg in jq curl; do
    if ! command -v $pkg >/dev/null 2>&1; then
        echo "[INFO] $pkg not found. Installing..."
        sudo apt update && sudo apt install -y $pkg
    fi
done

# ===============================
# 2. 解析日志 → TMPLOG  (格式: TIME|USER|IP|PORT)
# ===============================
TMPLOG=$(mktemp /tmp/ssh_log_XXXXXX)
TMPGEO=$(mktemp /tmp/ssh_geo_XXXXXX)

journalctl -u ssh -u sshd --since "$SINCE" --no-pager 2>/dev/null \
    | grep -E "Failed password|Invalid user" \
    | while read -r line; do
        timestamp=$(echo "$line" | awk '{print $1" "$2" "$3}')
        ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        [[ -z "$ip" ]] && continue
        if echo "$line" | grep -iqE "invalid user"; then
            user=$(echo "$line" | grep -ioP '(?<=invalid user )\S+')
        else
            user=$(echo "$line" | grep -oP '(?<=for )\S+(?= from)')
        fi
        [[ -z "$user" ]] && user="unknown"
        port=$(echo "$line" | grep -oP '(?<=port )\d+' | head -1)
        [[ -z "$port" ]] && port="?"
        echo "${timestamp}|${user}|${ip}|${port}"
    done > "$TMPLOG"

if [ ! -s "$TMPLOG" ]; then
    echo -e "${YELLOW}[INFO] No failed login attempts found for: $SINCE${RESET}"
    rm -f "$TMPLOG" "$TMPGEO"; exit 0
fi

# ===============================
# 3. 统计每个 IP 攻击次数 → 关联数组
# ===============================
declare -A IP_COUNT
while IFS='|' read -r _ _ ip _; do
    IP_COUNT["$ip"]=$(( ${IP_COUNT["$ip"]:-0} + 1 ))
done < "$TMPLOG"

# ===============================
# 4. GeoIP 批量查询（ip-api.com，ipinfo.io 回退）
# ===============================
mapfile -t UNIQ_IPS < <(awk -F'|' '{print $3}' "$TMPLOG" | sort -u)
echo -e "${CYAN}[INFO]${RESET} Found ${BOLD}${#UNIQ_IPS[@]}${RESET} unique IPs. Querying geo data..."

API_OK=0; total=${#UNIQ_IPS[@]}; processed=0

while [ $processed -lt $total ]; do
    batch=("${UNIQ_IPS[@]:$processed:100}")
    processed=$((processed + ${#batch[@]}))

    json_body=$(printf '{"query":"%s","fields":"query,status,country,regionName,city,org"},' "${batch[@]}")
    json_body="[${json_body%,}]"

    resp=$(curl -s --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$json_body" "http://ip-api.com/batch" 2>/dev/null)

    [[ -z "$resp" ]] && { echo -e "${YELLOW}[WARN]${RESET} ip-api.com empty response."; break; }

    tsv=$(echo "$resp" | jq -r \
        '.[] | [(.query//""),(.country//""),(.regionName//""),(.city//""),(.org//"Unknown")] | @tsv')
    [[ -z "$tsv" ]] && { echo -e "${YELLOW}[WARN]${RESET} jq parsing failed."; break; }

    while IFS=$'\t' read -r qip country region city org; do
        [[ -z "$qip" ]] && continue
        if [[ -n "$city" ]]; then
            [[ -n "$region" && "$region" != "$city" ]] \
                && geo="${country}/${region}/${city}" || geo="${country}/${city}"
        elif [[ -n "$country" ]]; then
            geo="$country"
        else
            geo="Unknown"
        fi
        [[ -z "$org" ]] && org="Unknown"
        echo "${qip}|${geo}|${org}" >> "$TMPGEO"
    done <<< "$tsv"

    API_OK=1
    [[ $processed -lt $total ]] && sleep 1
done

if [ "$API_OK" -eq 0 ]; then
    echo -e "${CYAN}[INFO]${RESET} Falling back to ipinfo.io..."
    for ip in "${UNIQ_IPS[@]}"; do
        resp=$(curl -s --max-time 8 "https://ipinfo.io/${ip}/json" 2>/dev/null)
        if [[ -n "$resp" ]]; then
            country=$(echo "$resp" | jq -r '.country // ""')
            region=$(echo  "$resp" | jq -r '.region  // ""')
            city=$(echo    "$resp" | jq -r '.city    // ""')
            org=$(echo     "$resp" | jq -r '.org     // "Unknown"')
            if [[ -n "$city" && "$city" != "null" ]]; then
                [[ -n "$region" && "$region" != "$city" ]] \
                    && geo="${country}/${region}/${city}" || geo="${country}/${city}"
            elif [[ -n "$country" && "$country" != "null" ]]; then
                geo="$country"
            else
                geo="Unknown"
            fi
            echo "${ip}|${geo}|${org}" >> "$TMPGEO"
        else
            echo "${ip}|Unknown|Unknown" >> "$TMPGEO"
        fi
        sleep 0.3
    done
fi

for ip in "${UNIQ_IPS[@]}"; do
    grep -q "^${ip}|" "$TMPGEO" 2>/dev/null || echo "${ip}|Unknown|Unknown" >> "$TMPGEO"
done

echo -e "${CYAN}[INFO]${RESET} Geo lookup done."
echo

# ===============================
# 5. 输出报告（纯 bash while 循环，只读 TMPLOG）
# ===============================
DIV="${BOLD}$(printf '─%.0s' {1..120})${RESET}"
echo -e "$DIV"
printf "${BOLD}%-16s %-18s %-16s %-5s %-4s  %-36s %s${RESET}\n" \
    "TIME" "USER" "IP" "PORT" "CNT" "LOCATION" "ASN/ORG"
echo -e "$DIV"

while IFS='|' read -r ts user ip port; do
    # 查 geo/org
    geo_line=$(grep "^${ip}|" "$TMPGEO" | head -1)
    geo="${geo_line#*|}"
    org="${geo##*|}"
    geo="${geo%|*}"
    [[ -z "$geo" ]] && geo="Unknown"
    [[ -z "$org" ]] && org="Unknown"

    # 查攻击次数
    cnt="${IP_COUNT[$ip]:-1}"

    # IP 颜色按攻击次数分级
    if   [ "$cnt" -ge 10 ]; then ip_c=$LRED
    elif [ "$cnt" -ge 5  ]; then ip_c=$RED
    elif [ "$cnt" -ge 3  ]; then ip_c=$YELLOW
    else                          ip_c=$RESET
    fi

    gc=$(geo_color "$geo")

    printf "${GRAY}%-16s${RESET} ${CYAN}%-18s${RESET} ${ip_c}%-16s${RESET} ${GRAY}%-5s${RESET} ${BOLD}%-4s${RESET}  ${gc}%-36s${RESET} ${GRAY}%s${RESET}\n" \
        "$ts" "$user" "$ip" "$port" "$cnt" "$geo" "$org"
done < "$TMPLOG"

echo -e "$DIV"

# ===============================
# 6. 统计摘要
# ===============================
echo
echo -e "${BOLD}=== Summary ===${RESET}"
echo -e "Total failed attempts : ${BOLD}${RED}$(wc -l < "$TMPLOG")${RESET}"
echo -e "Unique source IPs     : ${BOLD}$(awk -F'|' '{print $3}' "$TMPLOG" | sort -u | wc -l)${RESET}"

echo
echo -e "${BOLD}Top 5 attacking IPs:${RESET}"
awk -F'|' '{print $3}' "$TMPLOG" | sort | uniq -c | sort -rn | head -5 | \
while read -r count ip; do
    geo_line=$(grep "^${ip}|" "$TMPGEO" | head -1)
    geo="${geo_line#*|}"; geo="${geo%|*}"
    [[ -z "$geo" ]] && geo="Unknown"
    gc=$(geo_color "$geo")
    printf "  ${BOLD}%-6s${RESET} ${LRED}%-16s${RESET}  ${gc}%s${RESET}\n" "$count" "$ip" "$geo"
done

echo
echo -e "${BOLD}Top 5 attempted usernames:${RESET}"
awk -F'|' '{print $2}' "$TMPLOG" | sort | uniq -c | sort -rn | head -5 | \
    awk '{printf "  \033[1m%-6s\033[0m \033[0;36m%s\033[0m\n", $1, $2}'

echo
echo -e "${BOLD}Attacks by country:${RESET}"
while IFS='|' read -r _ _ ip _; do
    geo_line=$(grep "^${ip}|" "$TMPGEO" | head -1)
    geo="${geo_line#*|}"; geo="${geo%|*}"
    country="${geo%%/*}"
    echo "${country:-Unknown}"
done < "$TMPLOG" | sort | uniq -c | sort -rn | head -10 | \
while read -r count country; do
    gc=$(geo_color "$country")
    printf "  ${BOLD}%-6s${RESET} ${gc}%s${RESET}\n" "$count" "$country"
done

rm -f "$TMPLOG" "$TMPGEO"
