#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 📦 软件源速度测试与切换脚本 (高兼容 & 完美对齐版)
# 
# 版本：1.1.2 (彻底解决 grep 报错与对齐偏差)
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

# 核心对齐函数：手动计算空格补齐
# 原理：不再让 printf 猜宽度，而是算出中文字符导致的“视觉宽度差”，手动补空格
print_line() {
    local name="$1"
    local icon="$2"
    local time_str="$3"
    local level="$4"
    
    # 计算视觉宽度
    # 字节数(wc -c) 减去 字符数(wc -m) 等于多出的字节
    # 在 UTF-8 中，每个汉字多出 2 字节，显示占 2 列。
    local b_len=$(echo -n "$name" | wc -c)
    local c_len=$(echo -n "$name" | wc -m)
    local visible_width=$(( c_len + (b_len - c_len) / 2 ))
    
    # 目标宽度 25，计算需要补多少空格
    local spaces=$(( 25 - visible_width ))
    local padding=""
    if [ $spaces -gt 0 ]; then
        padding=$(printf '%*s' "$spaces" "")
    fi
    
    # 打印最终行
    echo -e "   ${name}${padding} ${icon}  ${time_str}  ${level}"
}

# ═══════════════════════════════════════════════════════════════
# 配置区
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

# 固定测试顺序，确保与下方菜单一致
MIRROR_ORDER=("腾讯云" "阿里云" "北京大学" "中国科学技术大学" "上海交通大学" "163 网易" "华为云" "清华大学" "官方源" "搜狐")

DEBIAN_VERSION=$(cat /etc/debian_version 2>/dev/null | cut -d'.' -f1 || echo "13")
CODENAME=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d'=' -f2 || echo "trixie")

# ═══════════════════════════════════════════════════════════════
# 主程序
# ═══════════════════════════════════════════════════════════════

print_header "📦 软件源速度测试与切换"
log_info "系统：Debian $DEBIAN_VERSION ($CODENAME)"

echo ""
# 表头采用固定间距，最稳妥
echo -e "   ${CYAN}镜像源名称                状态    响应延迟      评估${NC}"
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
        RESULTS["$name"]=99999
    fi
    
    # 调用手动对齐函数
    print_line "$name" "$icon" "$time_str" "$level"
done
set -e
echo -e "   ${CYAN}─────────────────────────────────────────────────────${NC}"

# ───────────────────────────────────────────────────────────────
# 切换与写入逻辑
# ───────────────────────────────────────────────────────────────

print_header "⚙️  软件源切换选项"

# 自动寻找最快源
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
    0) exit 0 ;;
    *) log_error "无效选项"; exit 1 ;;
esac

# 备份并写入
BACKUP_FILE="/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M)"
[[ -f /etc/apt/sources.list ]] && cp /etc/apt/sources.list "$BACKUP_FILE" && log_info "备份已存至: $BACKUP_FILE"

cat > /etc/apt/sources.list << EOF
# Debian $DEBIAN_VERSION ($CODENAME) 软件源 - $TARGET_NAME
deb $TARGET_URL $CODENAME main contrib non-free non-free-firmware
deb $TARGET_URL $CODENAME-updates main contrib non-free non-free-firmware
deb $TARGET_URL $CODENAME-security main contrib non-free non-free-firmware
EOF

log_success "🎉 已切换到 $TARGET_NAME！建议运行 apt update 更新。"
