#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 🌐 IPv4/IPv6 连通性检测与优化脚本
# 
# 用途：检测 VPS 的 IPv4/IPv6 连通性，优化 gai.conf 配置
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
# 主流程
# ═══════════════════════════════════════════════════════════════

print_header "🌐 IPv4/IPv6 连通性检测与优化"

log_info "开始检测网络连通性..."
echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 1: 检测 IPv4 连通性
# ───────────────────────────────────────────────────────────────

log_info "测试 IPv4 连通性..."

IPV4_TEST=$(curl -4 -s --connect-timeout 10 https://www.cloudflare.com 2>&1 | head -1)
IPV4_STATUS=$?

if [[ $IPV4_STATUS -eq 0 && -n "$IPV4_TEST" ]]; then
    IPV4_OK=true
    log_success "IPv4 连通性：正常 ✅"
    
    # 获取 IPv4 地址
    IPV4_ADDR=$(curl -4 -s --connect-timeout 5 https://api.ipify.org 2>/dev/null || echo "未知")
    echo -e "   ${CYAN}IPv4 地址:${NC} $IPV4_ADDR"
else
    IPV4_OK=false
    log_error "IPv4 连通性：失败 ❌"
fi

echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 2: 检测 IPv6 连通性
# ───────────────────────────────────────────────────────────────

log_info "测试 IPv6 连通性..."

IPV6_TEST=$(curl -6 -s --connect-timeout 10 https://www.cloudflare.com 2>&1 | head -1)
IPV6_STATUS=$?

if [[ $IPV6_STATUS -eq 0 && -n "$IPV6_TEST" ]]; then
    IPV6_OK=true
    log_success "IPv6 连通性：正常 ✅"
    
    # 获取 IPv6 地址
    IPV6_ADDR=$(curl -6 -s --connect-timeout 5 https://api6.ipify.org 2>/dev/null || echo "未知")
    echo -e "   ${CYAN}IPv6 地址:${NC} $IPV6_ADDR"
else
    IPV6_OK=false
    log_error "IPv6 连通性：失败 ❌"
fi

echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 3: 显示当前 gai.conf 配置
# ───────────────────────────────────────────────────────────────

log_info "检查当前 gai.conf 配置..."

if [[ -f /etc/gai.conf ]]; then
    echo ""
    echo "当前 IPv4 优先级设置："
    
    if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
        echo -e "   ${GREEN}IPv4 优先已启用 ✅${NC}"
        CURRENT_PRIORITY="ipv4"
    elif grep -q "^#precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
        echo -e "   ${YELLOW}IPv4 优先已禁用 (注释状态)${NC}"
        CURRENT_PRIORITY="default"
    else
        echo -e "   ${YELLOW}使用系统默认配置${NC}"
        CURRENT_PRIORITY="default"
    fi
else
    log_warn "/etc/gai.conf 文件不存在"
    CURRENT_PRIORITY="default"
fi

echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 4: 显示网络状态总结
# ───────────────────────────────────────────────────────────────

print_header "📊 网络状态总结"

echo ""
printf "%-20s | %-10s | %-10s\n" "网络类型" "连通性" "状态"
echo "---------------------|------------|------------"
printf "%-20s | %-10s | %-10s\n" "IPv4" "$([[ $IPV4_OK == true ]] && echo '正常' || echo '失败')" "$([[ $IPV4_OK == true ]] && echo '✅' || echo '❌')"
printf "%-20s | %-10s | %-10s\n" "IPv6" "$([[ $IPV6_OK == true ]] && echo '正常' || echo '失败')" "$([[ $IPV6_OK == true ]] && echo '✅' || echo '❌')"
echo ""

# 判断网络类型
if [[ "$IPV4_OK" == "true" && "$IPV6_OK" == "true" ]]; then
    NETWORK_TYPE="双栈 (IPv4 + IPv6)"
    log_success "网络类型：$NETWORK_TYPE"
elif [[ "$IPV4_OK" == "true" ]]; then
    NETWORK_TYPE="仅 IPv4"
    log_info "网络类型：$NETWORK_TYPE"
elif [[ "$IPV6_OK" == "true" ]]; then
    NETWORK_TYPE="仅 IPv6"
    log_warn "网络类型：$NETWORK_TYPE (可能需要 CFwarp)"
else
    NETWORK_TYPE="无网络连接"
    log_error "网络类型：$NETWORK_TYPE"
    exit 1
fi

echo ""

# ───────────────────────────────────────────────────────────────
# 步骤 5: 提供优化选项
# ───────────────────────────────────────────────────────────────

print_header "⚙️  网络优化选项"

echo ""
echo "请选择操作："
echo ""
echo "  1) 设置 IPv4 优先 (适合 IPv6 不稳定的机器)"
echo "  2) 设置 IPv6 优先 (适合 IPv6 更快的机器)"
echo "  3) 恢复系统默认配置"
echo "  4) 查看当前 gai.conf 完整内容"
echo "  0) 退出"
echo ""

read -p "请输入选项 [0-4]: " choice

case $choice in
    1)
        echo ""
        log_info "正在设置 IPv4 优先..."
        
        # 备份当前配置
        if [[ -f /etc/gai.conf ]]; then
            BACKUP_FILE="/etc/gai.conf.bak.$(date +%Y%m%d%H%M%S)"
            cp /etc/gai.conf "$BACKUP_FILE"
            log_info "已备份到：$BACKUP_FILE"
        fi
        
        # 修改配置
        if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
            log_info "IPv4 优先已启用，无需修改"
        elif grep -q "^#precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
            sed -i 's/^#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf
            log_success "已启用 IPv4 优先"
        else
            echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
            log_success "已添加 IPv4 优先配置"
        fi
        
        echo ""
        log_success "✅ IPv4 优先设置完成！"
        echo ""
        echo "验证方法：curl https://www.cloudflare.com (应该使用 IPv4)"
        ;;
        
    2)
        echo ""
        log_info "正在设置 IPv6 优先..."
        
        # 备份当前配置
        if [[ -f /etc/gai.conf ]]; then
            BACKUP_FILE="/etc/gai.conf.bak.$(date +%Y%m%d%H%M%S)"
            cp /etc/gai.conf "$BACKUP_FILE"
            log_info "已备份到：$BACKUP_FILE"
        fi
        
        # 修改配置
        if grep -q "^#precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
            log_info "IPv6 优先已启用 (IPv4 优先已禁用)"
        elif grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
            sed -i 's/^precedence ::ffff:0:0\/96  100/#precedence ::ffff:0:0\/96  100/' /etc/gai.conf
            log_success "已禁用 IPv4 优先 (IPv6 优先)"
        else
            log_info "系统默认配置 (通常 IPv6 优先)"
        fi
        
        echo ""
        log_success "✅ IPv6 优先设置完成！"
        echo ""
        echo "验证方法：curl https://www.cloudflare.com (应该使用 IPv6)"
        ;;
        
    3)
        echo ""
        log_info "正在恢复系统默认配置..."
        
        if [[ -f /etc/gai.conf ]]; then
            # 备份当前配置
            BACKUP_FILE="/etc/gai.conf.bak.$(date +%Y%m%d%H%M%S)"
            cp /etc/gai.conf "$BACKUP_FILE"
            log_info "已备份当前配置到：$BACKUP_FILE"
            
            # 恢复默认 (注释掉 IPv4 优先行)
            if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
                sed -i 's/^precedence ::ffff:0:0\/96  100/#precedence ::ffff:0:0\/96  100/' /etc/gai.conf
                log_success "已恢复系统默认配置"
            else
                log_info "已经是默认配置"
            fi
        else
            log_warn "/etc/gai.conf 文件不存在"
        fi
        
        echo ""
        log_success "✅ 已恢复系统默认配置！"
        ;;
        
    4)
        echo ""
        if [[ -f /etc/gai.conf ]]; then
            echo "─────────────────────────────────────────────────"
            grep -E "^precedence|^#" /etc/gai.conf | head -20
            echo "─────────────────────────────────────────────────"
        else
            log_warn "/etc/gai.conf 文件不存在"
        fi
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

echo ""
log_success "🎉 操作完成！"
echo ""
