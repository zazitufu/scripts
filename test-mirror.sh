#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 📦 软件源速度测试与切换脚本
# 
# 用途：测试各软件源速度，一键切换最快源
# 作者：Tufu
# 版本：1.0.0
# 创建：2026-04-05
#
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
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
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

# 当前系统版本
if [[ -f /etc/os-release ]]; then
    CODENAME=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d'=' -f2)
fi
if [[ -z "$CODENAME" ]]; then
    DEBIAN_VERSION=$(cat /etc/debian_version 2>/dev/null | cut -d'.' -f1)
    # 根据版本确定代号
    case "$DEBIAN_VERSION" in
        13) CODENAME="trixie" ;;
        12) CODENAME="bookworm" ;;
        11) CODENAME="bullseye" ;;
        10) CODENAME="buster" ;;
        *) CODENAME="trixie" ;;  # 默认
    esac
fi

# ═══════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════

print_header "📦 软件源速度测试与切换"

log_info "系统版本：Debian $DEBIAN ($CODENAME)"
echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 1: 显示当前软件源
# ───────────────────────────────────────────────────────────────

log_info "当前软件源配置："
echo ""

if [[ -f /etc/apt/sources.list ]]; then
    CURRENT_SOURCE=$(grep -v "^#" /etc/apt/sources.list | grep "deb " | head -1 | awk '{print $2}')
    echo -e "   ${CYAN}主源:${NC} $CURRENT_SOURCE"
else
    echo -e "   ${YELLOW}未找到 sources.list 文件${NC}"
    CURRENT_SOURCE="未知"
fi

# 检查 sources.list.d 目录
if [[ -d /etc/apt/sources.list.d ]]; then
    EXTRA_SOURCES=$(ls /etc/apt/sources.list.d/*.list 2>/dev/null | wc -l)
    if [[ $EXTRA_SOURCES -gt 0 ]]; then
        echo -e "   ${CYAN}额外源:${NC} $EXTRA_SOURCES 个配置文件"
    fi
fi

echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 2: 测试各软件源速度
# ───────────────────────────────────────────────────────────────

print_header "🚀 测试软件源速度"

log_info "正在测试各软件源响应速度..."
echo ""

# 存储结果
declare -A RESULTS
declare -a SORTED_MIRRORS

# 测试每个源
for name in "${!MIRRORS[@]}"; do
    url="${MIRRORS[$name]}"
    test_url="${url}/dists/${CODENAME}/Release"
    
    # 测试连接时间 (毫秒)
    start_time=$(date +%s%N)
    response=$(curl -s --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" "$test_url" 2>/dev/null)
    end_time=$(date +%s%N)
    
    # 计算耗时
    elapsed=$(( (end_time - start_time) / 1000000 ))
    
    # 保存结果
    RESULTS["$name"]="$elapsed:$response"
    
    # 判断状态
    if [[ "$response" == "200" ]]; then
        if [[ $elapsed -lt 500 ]]; then
            status="${GREEN}✅ ${elapsed}ms${NC}"
        elif [[ $elapsed -lt 1000 ]]; then
            status="${GREEN}✅ ${elapsed}ms${NC}"
        elif [[ $elapsed -lt 2000 ]]; then
            status="${YELLOW}⚠️  ${elapsed}ms${NC}"
        else
            status="${RED}❌ ${elapsed}ms${NC}"
        fi
    else
        status="${RED}❌ 失败 (${response})${NC}"
    fi
    
    printf "   %-30s %b\n" "$name" "$status"
done

echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 3: 排序并显示最佳源
# ───────────────────────────────────────────────────────────────

log_info "速度排名："
echo ""

# 创建排序列表
SORTED_LIST=""
for name in "${!RESULTS[@]}"; do
    IFS=':' read -r time code <<< "${RESULTS[$name]}"
    if [[ "$code" == "200" ]]; then
        SORTED_LIST+="$time $name\n"
    fi
done

# 排序
SORTED_LIST=$(echo -e "$SORTED_LIST" | sort -n)

# 显示前 5 名
count=0
echo "   排名  耗时     镜像源"
echo "   ─────────────────────────────────"
while IFS=' ' read -r time name; do
    if [[ -n "$name" ]]; then
        ((count++))
        if [[ $count -le 5 ]]; then
            if [[ $time -lt 500 ]]; then
                echo -e "   ${GREEN}$count     ${time}ms    ${name}${NC}"
            elif [[ $time -lt 1000 ]]; then
                echo -e "   ${GREEN}$count     ${time}ms    ${name}${NC}"
            else
                echo -e "   ${YELLOW}$count     ${time}ms    ${name}${NC}"
            fi
        fi
    fi
done <<< "$SORTED_LIST"

# 获取最快的源
FASTEST=$(echo -e "$SORTED_LIST" | head -1 | awk '{print $2}')
FASTEST_TIME=$(echo -e "$SORTED_LIST" | head -1 | awk '{print $1}')

echo ""
if [[ -n "$FASTEST" ]]; then
    log_success "最快镜像源：${FASTEST} (${FASTEST_TIME}ms)"
else
    log_warn "所有镜像源测试失败"
fi

echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 4: 提供切换选项
# ───────────────────────────────────────────────────────────────

print_header "⚙️  软件源切换选项"

echo ""
echo "请选择操作："
echo ""
echo "  1) 切换到最快源 ($FASTEST)"
echo "  2) 切换到阿里云"
echo "  3) 切换到腾讯云"
echo "  4) 切换到清华大学"
echo "  5) 切换到官方源"
echo "  6) 手动输入镜像源 URL"
echo "  0) 退出"
echo ""

read -p "请输入选项 [0-6]: " choice

case $choice in
    1)
        if [[ -n "$FASTEST" ]]; then
            TARGET_URL="${MIRRORS[$FASTEST]}"
            TARGET_NAME="$FASTEST"
        else
            log_error "无可用镜像源"
            exit 1
        fi
        ;;
    2)
        TARGET_URL="${MIRRORS[阿里云]}"
        TARGET_NAME="阿里云"
        ;;
    3)
        TARGET_URL="${MIRRORS[腾讯云]}"
        TARGET_NAME="腾讯云"
        ;;
    4)
        TARGET_URL="${MIRRORS[清华大学]}"
        TARGET_NAME="清华大学"
        ;;
    5)
        TARGET_URL="${MIRRORS[官方源]}"
        TARGET_NAME="官方源"
        ;;
    6)
        read -p "请输入镜像源 URL (如：http://mirrors.aliyun.com/debian): " TARGET_URL
        TARGET_NAME="自定义"
        ;;
    0)
        log_info "已退出"
        exit 0
        ;;
    *)
        log_error "无效的选项！"
        exit 1
        ;;
esac

# ───────────────────────────────────────────────────────────────
# 步骤 5: 执行切换
# ───────────────────────────────────────────────────────────────

echo ""
log_info "正在切换到 $TARGET_NAME ..."
echo ""

# 备份当前配置
BACKUP_FILE="/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)"
cp /etc/apt/sources.list "$BACKUP_FILE"
log_info "已备份当前配置到：$BACKUP_FILE"

# 创建新的 sources.list
cat > /etc/apt/sources.list << EOF
# Debian $DEBIAN ($CODENAME) 软件源
# 镜像：$TARGET_NAME
# 切换时间：$(date '+%Y-%m-%d %H:%M:%S')

deb $TARGET_URL $CODENAME main contrib non-free non-free-firmware
deb $TARGET_URL $CODENAME-updates main contrib non-free non-free-firmware
deb $TARGET_URL $CODENAME-security main contrib non-free non-free-firmware
EOF

log_success "✅ 软件源已切换到：$TARGET_NAME"
echo ""
echo "   镜像 URL: $TARGET_URL"
echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 6: 测试新配置
# ───────────────────────────────────────────────────────────────

read -p "是否现在更新软件源列表？(y/n): " update_choice

if [[ "$update_choice" == "y" || "$update_choice" == "Y" ]]; then
    echo ""
    log_info "正在更新软件源列表..."
    echo ""
    
    if apt-get update 2>&1 | tail -5; then
        echo ""
        log_success "✅ 软件源更新成功！"
    else
        echo ""
        log_warn "⚠️  软件源更新失败，请检查配置"
    fi
fi

echo ""
log_success "🎉 操作完成！"
echo ""
echo "提示：如需恢复原配置，运行："
echo "      cp $BACKUP_FILE /etc/apt/sources.list"
echo ""
