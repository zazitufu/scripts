#!/usr/bin/env bash
# SSH failed-login report with GeoIP enrichment.
#
# Author: zazitufu
# Version: v1.8
# Updated: 2026-04-29 00:11:32 +08:00
# Changelog:
#   v1.8 2026-04-29 00:11 +08:00 zazitufu
#        Restore the original journalctl short timestamp format in the report table.
#   v1.7 2026-04-29 00:08 +08:00 zazitufu
#        Narrow the USER column to reduce spacing before the IP column.
#   v1.6 2026-04-29 00:06 +08:00 zazitufu
#        Restore IPv4-friendly IP column width to reduce extra spacing before PORT.
#   v1.5 2026-04-28 23:56 +08:00 zazitufu
#        Include the ip-api query field so batch GeoIP results map back to their source IPs.
#   v1.4 2026-04-28 23:54 +08:00 zazitufu
#        Restore standalone "Invalid user" login-attempt parsing and avoid double counting
#        when the same connection also has a failed-password line.
#   v1.3 2026-04-28 23:38 +08:00 zazitufu
#        Add day-range arguments: N, --days N, -d N.
#   v1.2 2026-04-28 zazitufu
#        Optimize parsing, cleanup, GeoIP lookup, summary performance, and output handling.
#   v1.1 2026-04-11 zazitufu
#        Initial SSH failed-login report with GeoIP enrichment.
#
# Usage:
#   ./ssh_failed_report_optimized.sh
#   ./ssh_failed_report_optimized.sh 3
#   ./ssh_failed_report_optimized.sh --days 3
#   ./ssh_failed_report_optimized.sh --since "2026-04-11 00:00:00"

set -Eeuo pipefail

usage() {
    printf 'Usage: %s [journalctl --since expression]\n' "${0##*/}"
    printf '       %s N\n' "${0##*/}"
    printf '       %s --days N\n' "${0##*/}"
    printf '       %s --since "2026-04-11 00:00:00"\n' "${0##*/}"
    printf '\n'
    printf 'Default: today\n'
    printf 'Examples:\n'
    printf '  %s\n' "${0##*/}"
    printf '  %s 3\n' "${0##*/}"
    printf '  %s --days 3\n' "${0##*/}"
    printf '  %s -d 7\n' "${0##*/}"
}

SINCE="today"
RANGE_LABEL="today"

set_days_since() {
    local days="$1"

    [[ "$days" =~ ^[1-9][0-9]*$ ]] || {
        printf 'Invalid --days value: %s\n' "$days" >&2
        exit 2
    }

    if [[ "$days" == "1" ]]; then
        SINCE="1 day ago"
        RANGE_LABEL="last 1 day"
    else
        SINCE="$days days ago"
        RANGE_LABEL="last $days days"
    fi
}

while (($#)); do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--days)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            set_days_since "$2"
            shift 2
            ;;
        --days=*)
            set_days_since "${1#*=}"
            shift
            ;;
        --since)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            SINCE="$2"
            RANGE_LABEL="$2"
            shift 2
            ;;
        --since=*)
            SINCE="${1#*=}"
            RANGE_LABEL="$SINCE"
            shift
            ;;
        --)
            shift
            [[ $# -le 1 ]] || { usage >&2; exit 2; }
            if [[ $# -eq 1 ]]; then
                SINCE="$1"
                RANGE_LABEL="$1"
            fi
            break
            ;;
        -*)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            [[ $# -eq 1 ]] || { usage >&2; exit 2; }
            if [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
                set_days_since "$1"
            else
                SINCE="$1"
                RANGE_LABEL="$1"
            fi
            shift
            ;;
    esac
done

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[0;31m';    LRED=$'\033[1;31m'
    YELLOW=$'\033[0;33m'; CYAN=$'\033[0;36m'
    BLUE=$'\033[0;34m';   MAGENTA=$'\033[0;35m'
    GRAY=$'\033[0;90m';   BOLD=$'\033[1m'
    GREEN=$'\033[0;32m';  RESET=$'\033[0m'
else
    RED=''; LRED=''; YELLOW=''; CYAN=''
    BLUE=''; MAGENTA=''; GRAY=''; BOLD=''
    GREEN=''; RESET=''
fi

info() { printf '%b[INFO]%b %s\n' "$CYAN" "$RESET" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%b[ERROR]%b %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$1 not found. Please install it first."
}

geo_color() {
    case "$1" in
        China*|CN|CN/*)            printf '%b' "$RED" ;;
        Russia*|RU|RU/*)           printf '%b' "$LRED" ;;
        "United States"*|US|US/*)  printf '%b' "$BLUE" ;;
        "United Kingdom"*|GB|GB/*) printf '%b' "$CYAN" ;;
        Indonesia*|ID|ID/*)        printf '%b' "$YELLOW" ;;
        "Hong Kong"*|HK|HK/*)      printf '%b' "$MAGENTA" ;;
        Unknown*)                  printf '%b' "$GRAY" ;;
        *)                         printf '%b' "$GREEN" ;;
    esac
}

make_geo() {
    local country="${1:-}" region="${2:-}" city="${3:-}"

    [[ "$country" == "null" ]] && country=''
    [[ "$region" == "null" ]] && region=''
    [[ "$city" == "null" ]] && city=''

    if [[ -n "$city" ]]; then
        if [[ -n "$region" && "$region" != "$city" ]]; then
            printf '%s/%s/%s' "${country:-Unknown}" "$region" "$city"
        else
            printf '%s/%s' "${country:-Unknown}" "$city"
        fi
    elif [[ -n "$country" ]]; then
        printf '%s' "$country"
    else
        printf 'Unknown'
    fi
}

store_geo() {
    local ip="$1" country="${2:-}" region="${3:-}" city="${4:-}" org="${5:-Unknown}"

    GEO["$ip"]="$(make_geo "$country" "$region" "$city")"
    [[ -z "$org" || "$org" == "null" ]] && org="Unknown"
    ORG["$ip"]="$org"
}

parse_auth_line() {
    local line="$1" type ts user ip port pid key

    if [[ "$line" =~ ^([^[:space:]]+[[:space:]]+[0-9]+[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2})[[:space:]] ]]; then
        ts="${BASH_REMATCH[1]}"
    else
        ts="${line%% *}"
    fi
    pid="?"
    if [[ "$line" =~ sshd\[([0-9]+)\] ]]; then
        pid="${BASH_REMATCH[1]}"
    fi

    if [[ "$line" =~ Failed[[:space:]]password[[:space:]]for[[:space:]]invalid[[:space:]]user[[:space:]]([^[:space:]]+)[[:space:]]from[[:space:]]([^[:space:]]+)[[:space:]]port[[:space:]]([0-9]+) ]]; then
        type="failed"
        user="${BASH_REMATCH[1]}"
        ip="${BASH_REMATCH[2]}"
        port="${BASH_REMATCH[3]}"
    elif [[ "$line" =~ Failed[[:space:]]password[[:space:]]for[[:space:]]([^[:space:]]+)[[:space:]]from[[:space:]]([^[:space:]]+)[[:space:]]port[[:space:]]([0-9]+) ]]; then
        type="failed"
        user="${BASH_REMATCH[1]}"
        ip="${BASH_REMATCH[2]}"
        port="${BASH_REMATCH[3]}"
    elif [[ "$line" =~ Invalid[[:space:]]user[[:space:]]([^[:space:]]+)[[:space:]]from[[:space:]]([^[:space:]]+)[[:space:]]port[[:space:]]([0-9]+) ]]; then
        type="invalid"
        user="${BASH_REMATCH[1]}"
        ip="${BASH_REMATCH[2]}"
        port="${BASH_REMATCH[3]}"
    else
        return 1
    fi

    key="${pid}/${user}/${ip}/${port}"
    printf '%s|%s|%s|%s|%s|%s\n' "$type" "$key" "$ts" "$user" "$ip" "$port"
}

lookup_ip_api_batch() {
    local batch=("$@") json_body resp tsv

    json_body="$(
        printf '%s\n' "${batch[@]}" |
            jq -R '{query: ., fields: "query,status,message,country,regionName,city,org"}' |
            jq -s '.'
    )"

    resp="$(
        curl -fsS --max-time 10 \
            -H "Content-Type: application/json" \
            -d "$json_body" \
            "http://ip-api.com/batch" 2>/dev/null
    )" || return 1

    jq -e 'type == "array"' >/dev/null <<<"$resp" || return 1

    tsv="$(
        jq -r '.[] | [
            (.query // ""),
            (.status // ""),
            (.country // ""),
            (.regionName // ""),
            (.city // ""),
            (.org // "Unknown")
        ] | @tsv' <<<"$resp"
    )" || return 1

    while IFS=$'\t' read -r qip status country region city org; do
        [[ -z "$qip" || "$status" != "success" ]] && continue
        store_geo "$qip" "$country" "$region" "$city" "$org"
    done <<<"$tsv"
}

lookup_ipinfo() {
    local ip="$1" resp tsv country region city org

    resp="$(curl -fsS --max-time 8 "https://ipinfo.io/${ip}/json" 2>/dev/null)" || {
        GEO["$ip"]="Unknown"
        ORG["$ip"]="Unknown"
        return 0
    }

    tsv="$(
        jq -r '[
            (.country // ""),
            (.region // ""),
            (.city // ""),
            (.org // "Unknown")
        ] | @tsv' <<<"$resp" 2>/dev/null
    )" || {
        GEO["$ip"]="Unknown"
        ORG["$ip"]="Unknown"
        return 0
    }

    IFS=$'\t' read -r country region city org <<<"$tsv"
    store_geo "$ip" "$country" "$region" "$city" "$org"
}

need_cmd journalctl
need_cmd jq
need_cmd curl

if (( BASH_VERSINFO[0] < 4 )); then
    die "bash 4+ is required because this script uses associative arrays."
fi

TMPRAW="$(mktemp "${TMPDIR:-/tmp}/ssh_journal_XXXXXX")"
TMPCAND="$(mktemp "${TMPDIR:-/tmp}/ssh_candidates_XXXXXX")"
TMPLOG="$(mktemp "${TMPDIR:-/tmp}/ssh_log_XXXXXX")"
cleanup() { rm -f "$TMPRAW" "$TMPCAND" "$TMPLOG"; }
trap cleanup EXIT

printf '%b=== SSH Failed Login Report ===%b\n' "$BOLD" "$RESET"
printf '%bTime range: %s%b\n' "$GRAY" "$RANGE_LABEL" "$RESET"
printf '%bjournalctl --since: %s%b\n\n' "$GRAY" "$SINCE" "$RESET"

if ! journalctl -u ssh -u sshd --since "$SINCE" -o short --no-pager >"$TMPRAW"; then
    die "journalctl query failed. Try sudo, check journal permissions, or verify the time range."
fi

while IFS= read -r line; do
    parse_auth_line "$line" || true
done <"$TMPRAW" >"$TMPCAND"

declare -A HAS_FAILED_KEY
while IFS='|' read -r type key _ _ _ _; do
    [[ "$type" == "failed" ]] && HAS_FAILED_KEY["$key"]=1
done <"$TMPCAND"

while IFS='|' read -r type key ts user ip port; do
    if [[ "$type" == "invalid" && -n "${HAS_FAILED_KEY[$key]+set}" ]]; then
        continue
    fi
    printf '%s|%s|%s|%s\n' "$ts" "$user" "$ip" "$port"
done <"$TMPCAND" >"$TMPLOG"

if [[ ! -s "$TMPLOG" ]]; then
    printf '%b[INFO] No failed login attempts found for: %s%b\n' "$YELLOW" "$SINCE" "$RESET"
    exit 0
fi

declare -A IP_COUNT GEO ORG COUNTRY_COUNT

while IFS='|' read -r _ _ ip _; do
    IP_COUNT["$ip"]=$(( ${IP_COUNT["$ip"]:-0} + 1 ))
done <"$TMPLOG"

mapfile -t UNIQ_IPS < <(printf '%s\n' "${!IP_COUNT[@]}" | sort)
total="${#UNIQ_IPS[@]}"

info "Found ${BOLD}${total}${RESET} unique IPs. Querying geo data..."

for ((i = 0; i < total; i += 100)); do
    batch=("${UNIQ_IPS[@]:i:100}")
    if ! lookup_ip_api_batch "${batch[@]}"; then
        warn "ip-api.com batch lookup failed for batch starting at index $i."
    fi
    if (( i + 100 < total )); then
        sleep 1
    fi
done

fallback_count=0
for ip in "${UNIQ_IPS[@]}"; do
    if [[ -z "${GEO[$ip]+set}" ]]; then
        fallback_count=$((fallback_count + 1))
    fi
done

if (( fallback_count > 0 )); then
    info "Falling back to ipinfo.io for ${fallback_count} IPs..."
    for ip in "${UNIQ_IPS[@]}"; do
        [[ -n "${GEO[$ip]+set}" ]] && continue
        lookup_ipinfo "$ip"
        sleep 0.3
    done
fi

for ip in "${UNIQ_IPS[@]}"; do
    [[ -n "${GEO[$ip]+set}" ]] || GEO["$ip"]="Unknown"
    [[ -n "${ORG[$ip]+set}" ]] || ORG["$ip"]="Unknown"
done

info "Geo lookup done."
printf '\n'

DIV="$(printf '%*s' 120 '' | tr ' ' '-')"
printf '%b%s%b\n' "$BOLD" "$DIV" "$RESET"
printf '%b%-16s %-12s %-16s %-5s %-5s %-38s %s%b\n' \
    "$BOLD" "TIME" "USER" "IP" "PORT" "CNT" "LOCATION" "ASN/ORG" "$RESET"
printf '%b%s%b\n' "$BOLD" "$DIV" "$RESET"

while IFS='|' read -r ts user ip port; do
    geo="${GEO[$ip]:-Unknown}"
    org="${ORG[$ip]:-Unknown}"
    cnt="${IP_COUNT[$ip]:-1}"

    if (( cnt >= 10 )); then
        ip_c="$LRED"
    elif (( cnt >= 5 )); then
        ip_c="$RED"
    elif (( cnt >= 3 )); then
        ip_c="$YELLOW"
    else
        ip_c="$RESET"
    fi

    gc="$(geo_color "$geo")"

    printf '%b%-16s%b %b%-12s%b %b%-16s%b %b%-5s%b %b%-5s%b %b%-38s%b %b%s%b\n' \
        "$GRAY" "$ts" "$RESET" \
        "$CYAN" "$user" "$RESET" \
        "$ip_c" "$ip" "$RESET" \
        "$GRAY" "$port" "$RESET" \
        "$BOLD" "$cnt" "$RESET" \
        "$gc" "$geo" "$RESET" \
        "$GRAY" "$org" "$RESET"
done <"$TMPLOG"

printf '%b%s%b\n' "$BOLD" "$DIV" "$RESET"

printf '\n%b=== Summary ===%b\n' "$BOLD" "$RESET"
total_attempts="$(wc -l <"$TMPLOG" | tr -d '[:space:]')"
printf 'Total failed attempts : %b%s%b\n' "$BOLD$RED" "$total_attempts" "$RESET"
printf 'Unique source IPs     : %b%s%b\n' "$BOLD" "$total" "$RESET"

printf '\n%bTop 5 attacking IPs:%b\n' "$BOLD" "$RESET"
awk -F'|' '{print $3}' "$TMPLOG" | sort | uniq -c | sort -rn | awk 'NR <= 5 {print}' |
while read -r count ip; do
    geo="${GEO[$ip]:-Unknown}"
    gc="$(geo_color "$geo")"
    printf '  %b%-6s%b %b%-16s%b  %b%s%b\n' \
        "$BOLD" "$count" "$RESET" "$LRED" "$ip" "$RESET" "$gc" "$geo" "$RESET"
done

printf '\n%bTop 5 attempted usernames:%b\n' "$BOLD" "$RESET"
awk -F'|' '{print $2}' "$TMPLOG" | sort | uniq -c | sort -rn | awk 'NR <= 5 {print}' |
while read -r count user; do
    printf '  %b%-6s%b %b%s%b\n' "$BOLD" "$count" "$RESET" "$CYAN" "$user" "$RESET"
done

while IFS='|' read -r _ _ ip _; do
    country="${GEO[$ip]:-Unknown}"
    country="${country%%/*}"
    [[ -n "$country" ]] || country="Unknown"
    COUNTRY_COUNT["$country"]=$(( ${COUNTRY_COUNT["$country"]:-0} + 1 ))
done <"$TMPLOG"

printf '\n%bAttacks by country:%b\n' "$BOLD" "$RESET"
for country in "${!COUNTRY_COUNT[@]}"; do
    printf '%s\t%s\n' "${COUNTRY_COUNT[$country]}" "$country"
done | sort -rn -k1,1 | awk 'NR <= 10 {print}' |
while IFS=$'\t' read -r count country; do
    gc="$(geo_color "$country")"
    printf '  %b%-6s%b %b%s%b\n' "$BOLD" "$count" "$RESET" "$gc" "$country" "$RESET"
done
