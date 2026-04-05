#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 📦 软件源速度测试与切换脚本 (高兼容修复版)
# 
# 版本：1.1.1 (修复了 grep 报错与表头对齐问题)
# ═══════════════════════════════════════════════════════════════

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# 计算中文字符对齐所需的 Padding
# 原理：UTF-8中汉字占3字节，wc -m计为1字符。显示占2位。
# 偏移量 = (字节数 - 字符数) / 2
get_padding() {
    local text="$1"
    local base_width="$2"
    local b_len=$(echo -n "$text" | wc -c)
    local c_len=$(echo -n "$text" | wc -m)
    local offset=$(( (b_len - c_len) / 2 ))
    echo $(( base_width - offset ))
}

# ═══════════════════════════════════════════════════════════════
# 软件源配置
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
if [[ -f /etc/os-release ]]; then
    CODENAME=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d'=' -f2 || echo "")
fi
[[ -z "$CODENAME" ]] && CODENAME="trixie"

# ═══════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════

print_header "📦 软件源速度测试与切换"
log_info "系统：Debian $DEBIAN_VERSION ($CODENAME)"

echo ""
# 修复 Header 打印逻辑
h_name="镜像源名称"
h_pad=$(get_padding "$h_name" 25)
printf "   ${CYAN}%-${h_pad}s %-8s %-12s %-6s${NC}\n" "$h_name" "状态" "响应延迟" "评估"
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

    # 使用健壮的 Padding 计算
    name_pad=$(get_padding "$name" 25)
    
    if [[ "$response" == "200" ]]; then
        if [[ $elapsed -lt 300 ]]; then
            icon="${GREEN}✅${NC}"
            level="${GREEN}极速${NC}"
            time_str="${GREEN}$(printf "%-5d ms" $elapsed)${NC}"
        elif [[ $elapsed -lt 800 ]]; then
            icon="${GREEN}✅${NC}"
            level="${CYAN}良好${NC}"
            time_str="${CYAN}$(printf "%-5d ms" $elapsed)${NC}"
        elif [[ $elapsed -lt 1500 ]]; then
            icon="${YELLOW}⚠️${NC}"
            level="${YELLOW}一般${NC}"
            time_str="${YELLOW}$(printf "%-5d ms" $elapsed)${NC}"
        else
            icon="${YELLOW}⚠️${NC}"
            level="${RED}较慢${NC}"
            time_str="${RED}$(printf "%-5d ms" $elapsed)${NC}"
        fi
    else
        icon="${RED}❌${NC}"
        level="${RED}失败${NC}"
        time_str="${RED}--      ${NC}"
    fi
    
    printf "   %-${name_pad}s %b  %b  %b\n" "$name" "$icon" "$time_str" "$level"
done
set -e
echo -e "   ${CYAN}─────────────────────────────────────────────────────${NC}"

# ───────────────────────────────────────────────────────────────
# 切换选项部分保持不变...
# ───────────────────────────────────────────────────────────────
print_header "⚙️  软件源切换选项"
echo ""
FASTEST_VAL=99999
FASTEST_NAME="未知"
for n in "${!RESULTS[@]}"; do
    if [[ ${RESULTS[$n]} -lt $FASTEST_VAL ]]; then
        FASTEST_VAL=${RESULTS[$n]}
        FASTEST_NAME=$n
    fi
done
echo -e "  建议选择：${GREEN}$FASTEST_NAME${NC} (${FASTEST_VAL}ms)"
echo ""
# ... (此处省略后续 case 逻辑，与之前一致)
# 请确保脚本结尾有正确的 case 选项处理
