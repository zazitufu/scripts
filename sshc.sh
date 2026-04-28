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
