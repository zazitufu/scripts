#!/bin/bash
### 2026.4.11
### ssh check.检查当天尝试登录ssh的ip信息。
SINCE="${1:-today}"

echo "=== SSH Failed Login Report (v11) ==="
echo "Time range: $SINCE"
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
    echo "[INFO] No failed login attempts found for: $SINCE"
    rm -f "$TMPLOG" "$TMPGEO"; exit 0
fi

# ===============================
# 3. GeoIP 查询
# ===============================
mapfile -t UNIQ_IPS < <(awk -F'|' '{print $3}' "$TMPLOG" | sort -u)
echo "[INFO] Found ${#UNIQ_IPS[@]} unique IPs. Querying geo data..."

API_OK=0
total=${#UNIQ_IPS[@]}
processed=0

while [ $processed -lt $total ]; do
    batch=("${UNIQ_IPS[@]:$processed:100}")
    processed=$((processed + ${#batch[@]}))

    # 关键修复：fields 里加上 query，否则批量接口不返回 IP 字段
    json_body=$(printf '{"query":"%s","fields":"query,status,country,regionName,city,org"},' "${batch[@]}")
    json_body="[${json_body%,}]"

    resp=$(curl -s --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$json_body" \
        "http://ip-api.com/batch" 2>/dev/null)

    if [[ -z "$resp" ]]; then
        echo "[WARN] ip-api.com returned empty response."
        break
    fi

    # jq 输出 TSV: IP \t country \t regionName \t city \t org
    tsv=$(echo "$resp" | jq -r \
        '.[] | [(.query//""), (.country//""), (.regionName//""), (.city//""), (.org//"Unknown")] | @tsv')

    if [[ -z "$tsv" ]]; then
        echo "[WARN] jq parsing returned empty."
        break
    fi

    while IFS=$'\t' read -r qip country region city org; do
        [[ -z "$qip" ]] && continue
        if [[ -n "$city" ]]; then
            if [[ -n "$region" && "$region" != "$city" ]]; then
                geo="${country}/${region}/${city}"
            else
                geo="${country}/${city}"
            fi
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

# --- 回退：ipinfo.io 逐条查询 ---
if [ "$API_OK" -eq 0 ]; then
    echo "[INFO] Falling back to ipinfo.io..."
    for ip in "${UNIQ_IPS[@]}"; do
        resp=$(curl -s --max-time 8 "https://ipinfo.io/${ip}/json" 2>/dev/null)
        if [[ -n "$resp" ]]; then
            country=$(echo "$resp" | jq -r '.country // ""')
            region=$(echo  "$resp" | jq -r '.region  // ""')
            city=$(echo    "$resp" | jq -r '.city    // ""')
            org=$(echo     "$resp" | jq -r '.org     // "Unknown"')
            if [[ -n "$city" && "$city" != "null" ]]; then
                [[ -n "$region" && "$region" != "$city" ]] \
                    && geo="${country}/${region}/${city}" \
                    || geo="${country}/${city}"
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

# 补全没查到的 IP
for ip in "${UNIQ_IPS[@]}"; do
    grep -q "^${ip}|" "$TMPGEO" 2>/dev/null || echo "${ip}|Unknown|Unknown" >> "$TMPGEO"
done

echo "[INFO] Geo lookup done."
echo

# ===============================
# 4. 输出报告（awk join）
# ===============================
echo "-----------------------------------------------------------------------------------------------------------------------------------"
printf "%-18s %-20s %-16s %-6s %-35s %-30s\n" "TIME" "USER" "IP" "PORT" "LOCATION" "ASN/ORG"
echo "-----------------------------------------------------------------------------------------------------------------------------------"

awk -F'|' '
    NR==FNR { geo[$1]=$2; org[$1]=$3; next }
    {
        g = ($3 in geo) ? geo[$3] : "Unknown"
        o = ($3 in org) ? org[$3] : "Unknown"
        printf "%-18s %-20s %-16s %-6s %-35s %-30s\n", $1, $2, $3, $4, g, o
    }
' "$TMPGEO" "$TMPLOG"

echo "-----------------------------------------------------------------------------------------------------------------------------------"

# ===============================
# 5. 统计摘要
# ===============================
echo
echo "=== Summary ==="
echo "Total failed attempts : $(wc -l < "$TMPLOG")"
echo "Unique source IPs     : $(awk -F'|' '{print $3}' "$TMPLOG" | sort -u | wc -l)"
echo
echo "Top 5 attacking IPs:"
awk -F'|' '{print $3}' "$TMPLOG" | sort | uniq -c | sort -rn | head -5 \
    | awk '{printf "  %-6s %s\n", $1, $2}'
echo
echo "Top 5 attempted usernames:"
awk -F'|' '{print $2}' "$TMPLOG" | sort | uniq -c | sort -rn | head -5 \
    | awk '{printf "  %-6s %s\n", $1, $2}'

rm -f "$TMPLOG" "$TMPGEO"
