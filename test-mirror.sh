#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 📦 软件源速度测试与切换脚本 (优化对齐版)
# 
# 用途：测试各软件源速度，一键切换最快源
# 作者：Tufu
# 版本：1.1.0 (2026-04-05 优化版)
#
# ═══════════════════════════════════════════════════════════════

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

# 定义显示顺序（确保测试顺序与菜单选项一致）
MIRROR_ORDER=("腾讯云" "阿里云" "北京大学" "中国科学技术大学" "上海交通大学" "163 网易" "华为云" "清华大学" "官方源" "搜狐")

# 当前系统版本检测
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

# ───────────────────────────────────────────────────────────────
# 步骤 1: 测试各软件源速度
# ───────────────────────────────────────────────────────────────

echo ""
echo -e "   ${CYAN}%-22s %-8s %-12s %-6s${NC}" "镜像源名称" "状态" "响应延迟" "评估"
echo -e "   ${CYAN}─────────────────────────────────────────────────────${NC}"

declare -A RESULTS
set +e
for name in "${MIRROR_ORDER[@]}"; do
    url="${MIRRORS[$name]}"
    test_url="${url}/dists/${CODENAME}/Release"
    
    # 测速
    start_time=$(date +%s%N)
    response=$(curl -s --connect-timeout 3 --max-time 5 -o /dev/null -w "%{http_code}" "$test_url" 2>&1)
    end_time=$(date +%s%N)
    
    elapsed=$(( (end_time - start_time) / 1000000 ))
    RESULTS["$name"]="$elapsed"

    # --- 核心对齐补丁 ---
    # 计算中文字符数：每个中文在终端占2宽，printf 却只计1位。
    # 我们需要通过减去中文字数来修正补全的空格数。
    cjk_count=$(echo -n "$name" | grep -o "[^\x00-\x7F]" | wc -l || echo 0)
    name_padding=$((25 - cjk_count))
    
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
    
    printf "   %-${name_padding}s %b  %b  %b\n" "$name" "$icon" "$time_str" "$level"
done
set -e
echo -e "   ${CYAN}─────────────────────────────────────────────────────${NC}"

# ───────────────────────────────────────────────────────────────
# 步骤 2: 提供切换选项
# ───────────────────────────────────────────────────────────────

print_header "⚙️  软件源切换选项"
echo ""

# 格式化显示最快源建议
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
echo "  1) 切换到腾讯云"
echo "  2) 切换到阿里云"
echo "  3) 切换到北京大学"
echo "  4) 切换到中国科学技术大学"
echo "  5) 切换到上海交通大学"
echo "  6) 切换到 163 网易"
echo "  7) 切换到华为云"
echo "  8) 切换到清华大学"
echo "  9) 切换到官方源"
echo " 10) 手动输入镜像源 URL"
echo "  0) 退出"
echo ""

read -p "请输入选项 [0-10]: " choice

case $choice in
    1) TARGET_URL="${MIRRORS[腾讯云]}"; TARGET_NAME="腾讯云" ;;
    2) TARGET_URL="${MIRRORS[阿里云]}"; TARGET_NAME="阿里云" ;;
    3) TARGET_URL="${MIRRORS[北京大学]}"; TARGET_NAME="北京大学" ;;
    4) TARGET_URL="${MIRRORS[中国科学技术大学]}"; TARGET_NAME="中国科学技术大学" ;;
    5) TARGET_URL="${MIRRORS[上海交通大学]}"; TARGET_NAME="上海交通大学" ;;
    6) TARGET_URL="${MIRRORS[163 网易]}"; TARGET_NAME="163 网易" ;;
    7) TARGET_URL="${MIRRORS[华为云]}"; TARGET_NAME="华为云" ;;
    8) TARGET_URL="${MIRRORS[清华大学]}"; TARGET_NAME="清华大学" ;;
    9) TARGET_URL="${MIRRORS[官方源]}"; TARGET_NAME="官方源" ;;
    10) read -p "请输入镜像源 URL: " TARGET_URL; TARGET_NAME="自定义" ;;
    0) log_info "已退出"; exit 0 ;;
    *) log_error "无效选项"; exit 1 ;;
esac

# ───────────────────────────────────────────────────────────────
# 步骤 3: 执行切换
# ───────────────────────────────────────────────────────────────

echo ""
log_info "正在切换到 $TARGET_NAME ..."

# 备份
BACKUP_FILE="/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)"
[[ -f /etc/apt/sources.list ]] && cp /etc/apt/sources.list "$BACKUP_FILE" && log_info "备份已存至: $BACKUP_FILE"

# 写入新配置 (支持 Debian 12/13 的 non-free-firmware)
cat > /etc/apt/sources.list << EOF
# Debian $DEBIAN_VERSION ($CODENAME) 软件源 - $TARGET_NAME
# 切换时间：$(date '+%Y-%m-%d %H:%M:%S')

deb $TARGET_URL $CODENAME main contrib non-free non-free-firmware
deb $TARGET_URL $CODENAME-updates main contrib non-free non-free-firmware
deb $TARGET_URL $CODENAME-security main contrib non-free non-free-firmware
EOF

log_success "软件源已切换为：$TARGET_NAME"

read -p "是否执行 apt update？(y/n): " update_choice
if [[ "$update_choice" =~ ^[Yy]$ ]]; then
    echo ""
    log_info "正在更新列表..."
    apt-get update || log_warn "更新过程中出现错误，请检查网络"
fi

log_success "🎉 操作完成！"
