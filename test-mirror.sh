#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 📦 软件源速度测试与切换脚本
# 
# 版本：1.2.0 (新增当前源基准测试)
# ═══════════════════════════════════════════════════════════════

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 辅助函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# 核心对齐函数
print_line() {
    local name="$1"
    local icon="$2"
    local time_str="$3"
    local level="$4"
    local b_len=$(echo -n "$name" | wc -c)
    local c_len=$(echo -n "$name" | wc -m)
    local visible_width=$(( c_len + (b_len - c_len) / 2 ))
    local spaces=$(( 28 - visible_width )) # 稍微加宽一点适配 URL
    local padding=""
    [ $spaces -gt 0 ] && padding=$(printf '%*s' "$spaces" "")
    echo -e "   ${name}${padding} ${icon}  ${time_str}  ${level}"
}

# 单独的测速函数
get_speed() {
    local url="$1"
    local test_url="${url}/dists/${CODENAME}/Release"
    local start_time=$(date +%s%N)
    local response=$(curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w "%{http_code}" "$test_url" 2>&1 || echo "000")
    local end_time=$(date +%s%N)
    local elapsed=$(( (end_time - start_time) / 1000000 ))
    
    if [[ "$response" == "200" ]]; then
        if [[ $elapsed -lt 300 ]]; then
            echo -e "${GREEN}✅${NC}  ${GREEN}$(printf "%-5d ms" $elapsed)${NC}  ${GREEN}极速${NC}"
        elif [[ $elapsed -lt 1000 ]]; then
            echo -e "${GREEN}✅${NC}  ${CYAN}$(printf "%-5d ms" $elapsed)${NC}  ${CYAN}良好${NC}"
        else
            echo -e "${YELLOW}⚠️${NC}  ${RED}$(printf "%-5d ms" $elapsed)${NC}  ${RED}较慢${NC}"
        fi
    else
        echo -e "${RED}❌${NC}  ${RED}--      ${NC}  ${RED}无法连接${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 配置与系统检测
# ═══════════════════════════════════════════════════════════════

declare -A MIRRORS=(
    ["官方源"]="http://deb.debian.org/debian"
    ["阿里云"]="http://mirrors.aliyun.com/debian"
    ["腾讯云"]="http://mirrors.cloud.tencent.com/debian"
    ["华为云"]="http://mirrors.huaweicloud.com/debian"
    ["清华大学"]="http://mirrors.tuna.tsinghua.edu.cn/debian"
    ["北京大学"]="http://mirrors.pku.edu.cn/debian"
    ["上海交通大学"]="http://mirror.sjtu.edu.cn/debian"
    ["中国科学技术大学"]="http://mirrors.ustc.edu.cn/debian"
    ["163 网易"]="http://mirrors.163.com/debian"
    ["搜狐"]="http://mirrors.sohu.com/debian"
)

MIRROR_ORDER=("腾讯云" "阿里云" "北京大学" "中国科学技术大学" "上海交通大学" "163 网易" "华为云" "清华大学" "官方源" "搜狐")

DEBIAN_VERSION=$(cat /etc/debian_version 2>/dev/null | cut -d'.' -f1 || echo "13")
CODENAME=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d'=' -f2 || echo "trixie")

# ═══════════════════════════════════════════════════════════════
# 步骤 1: 系统信息与当前源基准测试
# ═══════════════════════════════════════════════════════════════

print_header "📦 系统环境与当前源基准"
log_info "系统：Debian $DEBIAN_VERSION ($CODENAME)"

# 提取当前源
CURRENT_URL="未知"
if [[ -f /etc/apt/sources.list ]]; then
    CURRENT_URL=$(grep -v "^#" /etc/apt/sources.list | grep "deb " | head -1 | awk '{print $2}' || echo "未知")
fi

echo -e "   ${CYAN}当前配置源:${NC} $CURRENT_URL"

if [[ "$CURRENT_URL" != "未知" ]]; then
    echo -ne "   ${CYAN}当前源测速:${NC} "
    get_speed "$CURRENT_URL"
fi
echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 2: 批量镜像站测速
# ───────────────────────────────────────────────────────────────

print_header "🚀 批量镜像站速度测试"
echo -e "   ${CYAN}镜像源名称                   状态    响应延迟      评估${NC}"
echo -e "   ${CYAN}─────────────────────────────────────────────────────${NC}"

declare -A RESULTS
set +e
for name in "${MIRROR_ORDER[@]}"; do
    url="${MIRRORS[$name]}"
    test_url="${url}/dists/${CODENAME}/Release"
    
    start_time=$(date +%s%N)
    response=$(curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w "%{http_code}" "$test_url" 2>&1)
    end_time=$(date +%s%N)
    
    elapsed=$(( (end_time - start_time) / 1000000 ))
    RESULTS["$name"]="$elapsed"

    if [[ "$response" == "200" ]]; then
        if [[ $elapsed -lt 300 ]]; then
            icon="${GREEN}✅${NC}"; level="${GREEN}极速${NC}"; time_str="${GREEN}$(printf "%-5d ms" $elapsed)${NC}"
        elif [[ $elapsed -lt 800 ]]; then
            icon="${GREEN}✅${NC}"; level="${CYAN}良好${NC}"; time_str="${CYAN}$(printf "%-5d ms" $elapsed)${NC}"
        elif [[ $elapsed -lt 1500 ]]; then
            icon="${YELLOW}⚠️${NC}"; level="${YELLOW}一般${NC}"; time_str="${YELLOW}$(printf "%-5d ms" $elapsed)${NC}"
        else
            icon="${YELLOW}⚠️${NC}"; level="${RED}较慢${NC}"; time_str="${RED}$(printf "%-5d ms" $elapsed)${NC}"
        fi
    else
        icon="${RED}❌${NC}"; level="${RED}失败${NC}"; time_str="${RED}--      ${NC}"; RESULTS["$name"]=99999
    fi
    
    print_line "$name" "$icon" "$time_str" "$level"
done
set -e
echo -e "   ${CYAN}─────────────────────────────────────────────────────${NC}"

# ───────────────────────────────────────────────────────────────
# 步骤 3: 切换选项 (保持之前的高兼容逻辑)
# ───────────────────────────────────────────────────────────────

print_header "⚙️  软件源切换选项"
FASTEST_VAL=99999
FASTEST_NAME="未知"
for n in "${!RESULTS[@]}"; do
    if [[ ${RESULTS[$n]} -lt $FASTEST_VAL ]]; then
        FASTEST_VAL=${RESULTS[$n]}
        FASTEST_NAME=$n
    fi
done

echo -e "  🚀 建议选择：${GREEN}$FASTEST_NAME${NC} (${FASTEST_VAL}ms)"
echo ""
echo "  1) 腾讯云    2) 阿里云    3) 北京大学    4) 中科大    5) 上交大"
echo "  6) 163网易   7) 华为云    8) 清华大学    9) 官方源    10) 自定义"
echo "  0) 退出"
echo ""

read -p "请输入选项 [0-10]: " choice

# ... (后续 case 逻辑与 sources.list 写入逻辑与 v1.1.2 完全一致)
# 此处为简洁省略重复的写入部分，请确保保留原有的 case 匹配与文件写入代码
