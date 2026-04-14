#!/bin/bash
# =============================================================================
# Netdata Child 节点一键部署脚本
# 支持系统: Debian 11/12/13, Ubuntu 20.04+, CentOS/Rocky/Alma 8+, Arch Linux
# 功能说明:
#   - 安装 Netdata（Child/推送模式）
#   - 向 Parent 节点推送监控数据（TLS 加密）
#   - 关闭本地 Web UI
#   - 提供完整卸载功能
# 用法:
#   bash setup-netdata-child.sh            # 安装
#   bash setup-netdata-child.sh uninstall  # 卸载
# =============================================================================

# 不加 -e（原因见 Parent 脚本注释）
set -uo pipefail

# ─── 颜色输出 ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}▶ $*${NC}"; echo -e "${CYAN}$(printf '─%.0s' {1..55})${NC}"; }

# ─── 全局变量 ─────────────────────────────────────────────────────────────────
OS_NAME=""
OS_VERSION=""
PKG_UPDATE=""
PKG_INSTALL=""
NETDATA_CONF_DIR=""
PARENT_HOST=""
PARENT_PORT="443"
API_KEY=""
NODE_NAME=""
RECORD_FILE="/root/.netdata-child.conf"


# =============================================================================
# STEP 0: 权限检查
# =============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请以 root 权限运行 (sudo bash $0)"
    fi
}


# =============================================================================
# STEP 1: 检测操作系统
# =============================================================================
detect_os() {
    step "检测操作系统"

    if [[ ! -f /etc/os-release ]]; then
        error "无法读取 /etc/os-release，不支持的系统"
    fi

    # shellcheck source=/dev/null
    source /etc/os-release
    OS_NAME="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    local OS_PRETTY="${PRETTY_NAME:-unknown}"

    case "${OS_NAME}" in
        debian)
            if [[ ! "${OS_VERSION}" =~ ^(11|12|13) ]]; then
                warn "Debian ${OS_VERSION} 未经充分测试，继续执行..."
            fi
            PKG_UPDATE="apt-get update -qq"
            PKG_INSTALL="apt-get install -y -qq"
            ;;
        ubuntu)
            PKG_UPDATE="apt-get update -qq"
            PKG_INSTALL="apt-get install -y -qq"
            ;;
        centos|rhel|rocky|almalinux)
            OS_NAME="centos"
            PKG_UPDATE="yum makecache -q"
            PKG_INSTALL="yum install -y -q"
            if command -v dnf &>/dev/null; then
                PKG_UPDATE="dnf makecache -q"
                PKG_INSTALL="dnf install -y -q"
            fi
            ;;
        arch|manjaro|endeavouros)
            OS_NAME="arch"
            PKG_UPDATE="pacman -Sy --noconfirm"
            PKG_INSTALL="pacman -S --noconfirm --needed"
            ;;
        *)
            error "不支持的系统: ${OS_NAME}。支持: Debian/Ubuntu/CentOS/Arch"
            ;;
    esac

    ok "系统识别: ${OS_PRETTY}"
    info "版本: ${OS_VERSION} | 内核: $(uname -r) | 主机名: $(hostname)"
}


# =============================================================================
# STEP 2: 检查并安装依赖
# =============================================================================
check_deps() {
    step "检查依赖"

    local DEPS=(curl wget)
    local MISSING=()

    for dep in "${DEPS[@]}"; do
        if command -v "${dep}" &>/dev/null; then
            ok "${dep} 已安装"
        else
            warn "${dep} 未安装，将自动安装"
            MISSING+=("${dep}")
        fi
    done

    if [[ ${#MISSING[@]} -gt 0 ]]; then
        info "安装缺失依赖: ${MISSING[*]}"
        ${PKG_UPDATE}
        ${PKG_INSTALL} "${MISSING[@]}"
        ok "依赖安装完成"
    fi
}


# =============================================================================
# STEP 3: 交互式收集配置
# =============================================================================
collect_config() {
    step "配置信息收集"
    echo ""

    # ── 3.1 Parent 地址 ──────────────────────────────────────────────────────
    while true; do
        read -rp "  请输入 Parent 域名或 IP (如 netdata.example.com): " PARENT_HOST
        if [[ -n "${PARENT_HOST}" && ! "${PARENT_HOST}" =~ [[:space:]] ]]; then
            break
        fi
        warn "不能为空或含空格，请重新输入"
    done
    ok "Parent 地址: ${PARENT_HOST}"

    # ── 3.2 Parent 端口 ──────────────────────────────────────────────────────
    read -rp "  请输入 Parent 端口 (默认 443): " INPUT_PORT
    PARENT_PORT="${INPUT_PORT:-443}"
    ok "Parent 端口: ${PARENT_PORT}"

    # ── 3.3 API Key（校验 UUID 格式） ────────────────────────────────────────
    while true; do
        read -rp "  请输入 API Key: " API_KEY
        if [[ "${API_KEY}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            break
        fi
        warn "格式不正确，应为 UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    done
    ok "API Key: ${API_KEY}"

    # ── 3.4 节点名称 ─────────────────────────────────────────────────────────
    local DEFAULT_NAME
    DEFAULT_NAME=$(hostname)
    read -rp "  请输入节点名称 (默认: ${DEFAULT_NAME}): " NODE_NAME
    NODE_NAME="${NODE_NAME:-${DEFAULT_NAME}}"
    ok "节点名称: ${NODE_NAME}"

    echo ""
}


# =============================================================================
# STEP 4: 安装 Netdata
# =============================================================================
install_netdata() {
    step "安装 Netdata"

    if command -v netdata &>/dev/null; then
        local ND_VER
        ND_VER=$(netdata -v 2>/dev/null | awk '{print $2}' || echo "已安装")
        warn "Netdata 已安装 (${ND_VER})，跳过安装，仅更新配置"
        return
    fi

    info "安装 Netdata (stable, 禁用遥测)..."

    case "${OS_NAME}" in
        arch)
            ${PKG_UPDATE}
            ${PKG_INSTALL} netdata
            ;;
        debian|ubuntu)
            wget -qO /tmp/nd-kickstart.sh https://get.netdata.cloud/kickstart.sh
            bash /tmp/nd-kickstart.sh \
                --stable-channel --disable-telemetry \
                --dont-start-it --no-updates \
                2>&1 | grep -E "(OK|ERROR|WARN|Installing)" || true
            rm -f /tmp/nd-kickstart.sh
            ;;
        centos)
            wget -qO /tmp/nd-kickstart.sh https://get.netdata.cloud/kickstart.sh
            bash /tmp/nd-kickstart.sh \
                --stable-channel --disable-telemetry \
                --dont-start-it --static-only \
                2>&1 | grep -E "(OK|ERROR|WARN|Installing)" || true
            rm -f /tmp/nd-kickstart.sh
            ;;
    esac

    if ! command -v netdata &>/dev/null; then
        error "Netdata 安装失败，请查看上方输出"
    fi
    ok "Netdata 安装完成"
}


# =============================================================================
# STEP 5: 配置 Netdata 为 Child（推送）模式
# =============================================================================
configure_netdata() {
    step "配置 Netdata Child 模式"

    if [[ -d /etc/netdata ]]; then
        NETDATA_CONF_DIR="/etc/netdata"
    elif [[ -d /opt/netdata/etc/netdata ]]; then
        NETDATA_CONF_DIR="/opt/netdata/etc/netdata"
    else
        error "找不到 Netdata 配置目录"
    fi
    info "配置目录: ${NETDATA_CONF_DIR}"

    # 主配置：关闭本地 Web UI
    cat > "${NETDATA_CONF_DIR}/netdata.conf" <<EOF
# Netdata 主配置 - Child 推送模式
# 节点: ${NODE_NAME}
# 由 setup-netdata-child.sh 自动生成

[global]
    hostname = ${NODE_NAME}
    # Child 本地只保留 1 小时历史，数据由 Parent 存储
    history  = 3600

[web]
    # 关闭本地 Web，不暴露任何端口
    mode = none

[plugins]
    proc      = yes
    cgroups   = yes
    diskspace = yes
    apps      = yes
    tc        = no
    nfacct    = no

[ml]
    # 关闭本地 ML，由 Parent 统一处理
    enabled = no
EOF
    ok "netdata.conf 已写入（Web UI 已关闭）"

    # Streaming 配置：推送到 Parent
    cat > "${NETDATA_CONF_DIR}/stream.conf" <<EOF
# Netdata Streaming - Child 推送模式
# 由 setup-netdata-child.sh 自动生成

[stream]
    enabled             = yes
    destination         = tls:${PARENT_HOST}:${PARENT_PORT}
    api key             = ${API_KEY}
    timeout seconds     = 60
    reconnect delay seconds = 5
    buffer size bytes   = 1048576
    initial clock resync iterations = 60
    enable compression  = yes
EOF
    ok "stream.conf 已写入（推送至 ${PARENT_HOST}:${PARENT_PORT}）"

    systemctl enable netdata &>/dev/null || true
    systemctl restart netdata

    local RETRY=0
    while [[ $RETRY -lt 15 ]]; do
        sleep 1
        if systemctl is-active --quiet netdata; then
            ok "Netdata 服务启动成功"
            return
        fi
        RETRY=$((RETRY + 1))
    done
    error "Netdata 启动超时: journalctl -u netdata -n 50"
}


# =============================================================================
# STEP 6: 验证连接状态
# =============================================================================
verify_connection() {
    step "验证 Streaming 连接"

    info "等待连接建立（最多 30 秒）..."

    local RETRY=0
    while [[ $RETRY -lt 30 ]]; do
        sleep 1
        if journalctl -u netdata -n 100 --no-pager 2>/dev/null | \
            grep -qi "connected\|streaming"; then
            echo ""
            ok "Streaming 连接已建立，数据正在推送至 Parent"
            return
        fi
        printf "."
        RETRY=$((RETRY + 1))
    done
    echo ""

    warn "30 秒内未检测到连接，可能原因:"
    warn "  1. DNS 解析未生效（新域名需等待）"
    warn "  2. Parent 443 端口未放行"
    warn "  3. API Key 与 Parent 不一致"
    warn "  4. Parent Caddy 配置未正确加载"
    info "排查命令: journalctl -u netdata -f"
    info "          curl -vk https://${PARENT_HOST}/api/v1/info"
}


# =============================================================================
# STEP 7: 保存配置记录
# =============================================================================
save_config_record() {
    step "保存配置记录"

    cat > "${RECORD_FILE}" <<EOF
# Netdata Child 配置记录
# 由 setup-netdata-child.sh 生成于 $(date '+%Y-%m-%d %H:%M:%S')

PARENT_HOST="${PARENT_HOST}"
PARENT_PORT="${PARENT_PORT}"
API_KEY="${API_KEY}"
NODE_NAME="${NODE_NAME}"
NETDATA_CONF_DIR="${NETDATA_CONF_DIR}"
OS_NAME="${OS_NAME}"
EOF
    chmod 600 "${RECORD_FILE}"
    ok "配置记录已保存: ${RECORD_FILE}"
}


# =============================================================================
# STEP 8: 卸载
# =============================================================================
do_uninstall() {
    step "卸载 Netdata Child 节点"

    if [[ -f "${RECORD_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${RECORD_FILE}"
        info "读取配置记录: ${RECORD_FILE}"
    else
        warn "未找到配置记录，使用默认路径"
        NETDATA_CONF_DIR="/etc/netdata"
    fi

    echo ""
    warn "即将执行以下卸载操作:"
    echo "  1. 停止并禁用 Netdata 服务"
    echo "  2. 卸载 Netdata 软件包及数据"
    echo "  3. 清理配置和日志"
    echo ""
    read -rp "  确认卸载？此操作不可撤销 [y/N]: " CONFIRM
    if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
        info "已取消卸载"
        exit 0
    fi
    echo ""

    info "停止 Netdata..."
    systemctl stop    netdata 2>/dev/null && ok "已停止" || warn "服务未运行"
    systemctl disable netdata 2>/dev/null || true

    info "卸载软件包..."
    case "${OS_NAME}" in
        arch)
            pacman -Rns --noconfirm netdata 2>/dev/null && ok "已卸载" || warn "卸载失败或已不存在"
            ;;
        debian|ubuntu)
            apt-get purge -y netdata 2>/dev/null && ok "已卸载" || warn "卸载失败或已不存在"
            apt-get autoremove -y 2>/dev/null || true
            ;;
        centos)
            yum remove -y netdata 2>/dev/null || warn "yum 卸载失败或已不存在"
            if [[ -d /opt/netdata ]]; then rm -rf /opt/netdata && ok "已删除 /opt/netdata"; fi
            ;;
    esac

    info "清理残留文件..."
    for dir in /etc/netdata /var/lib/netdata /var/cache/netdata \
                /var/log/netdata /opt/netdata/etc/netdata; do
        if [[ -d "${dir}" ]]; then rm -rf "${dir}" && info "  已删除: ${dir}"; fi
    done
    ok "清理完成"

    rm -f "${RECORD_FILE}" 2>/dev/null || true

    echo ""
    ok "卸载完成！"
}


# =============================================================================
# STEP 9: 显示摘要
# =============================================================================
show_summary() {
    local LINE="──────────────────────────────────────────────────────────"

    local PUBLIC_IP
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
                echo "获取失败")

    local MACHINE_GUID
    MACHINE_GUID=$(cat /var/lib/netdata/registry/netdata.public.unique.id 2>/dev/null || \
                   cat /opt/netdata/var/lib/netdata/registry/netdata.public.unique.id 2>/dev/null || \
                   echo "生成中...")

    echo ""
    echo -e "${GREEN}╔${LINE}╗${NC}"
    echo -e "${GREEN}║${NC}   ${BOLD}Netdata Child 节点部署完成！${NC}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    printf "${GREEN}║${NC}  %-16s : ${CYAN}%s${NC}\n" "节点名称"     "${NODE_NAME}"
    printf "${GREEN}║${NC}  %-16s : ${CYAN}%s${NC}\n" "本机公网 IP"  "${PUBLIC_IP}"
    printf "${GREEN}║${NC}  %-16s : ${CYAN}%s${NC}\n" "MACHINE_GUID" "${MACHINE_GUID}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    printf "${GREEN}║${NC}  %-16s : ${CYAN}%s${NC}\n" "推送至"       "${PARENT_HOST}:${PARENT_PORT}"
    printf "${GREEN}║${NC}  %-16s : ${CYAN}%s${NC}\n" "API Key"      "${API_KEY}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    printf "${GREEN}║${NC}  %-16s : %s\n" "配置记录" "${RECORD_FILE}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}[提示]${NC} Parent Web UI 约 10~30 秒后可见本节点"
    echo -e "${GREEN}║${NC}  ${YELLOW}[提示]${NC} 实时日志: journalctl -u netdata -f"
    echo -e "${GREEN}║${NC}  ${YELLOW}[提示]${NC} 卸载: bash $0 uninstall"
    echo -e "${GREEN}╚${LINE}╝${NC}"
    echo ""
}


# =============================================================================
# 主入口
# =============================================================================
main() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║     Netdata Child 节点一键部署脚本                   ║"
    echo "  ║     支持: Debian 11-13 / Ubuntu / CentOS / Arch      ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local ACTION="${1:-install}"

    case "${ACTION}" in
        install)
            check_root
            detect_os
            check_deps
            collect_config
            install_netdata
            configure_netdata
            verify_connection
            save_config_record
            show_summary
            ;;
        uninstall)
            check_root
            detect_os
            do_uninstall
            ;;
        *)
            echo "用法: bash $0 [install|uninstall]"
            echo ""
            echo "  install   - 部署 Netdata Child 节点（默认）"
            echo "  uninstall - 卸载所有已部署组件"
            exit 1
            ;;
    esac
}

main "$@"
