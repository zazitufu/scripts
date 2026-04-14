#!/bin/bash
# =============================================================================
# Netdata Child 节点一键部署脚本
# 支持系统: Debian 11/12/13, Ubuntu 20.04+, CentOS/Rocky/Alma 8+, Arch Linux
# 功能说明:
#   - 检测系统类型并安装依赖
#   - 安装 Netdata（Child/推送模式）
#   - 自动向 Parent 节点推送监控数据
#   - 关闭本地 Web UI（Child 不对外暴露）
#   - 提供完整卸载功能
# 用法:
#   bash setup-netdata-child.sh            # 安装
#   bash setup-netdata-child.sh uninstall  # 卸载
# =============================================================================

set -euo pipefail

# ─── 颜色输出工具函数 ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}▶ $*${NC}"; echo -e "${CYAN}$(printf '─%.0s' {1..55})${NC}"; }

# ─── 全局变量 ─────────────────────────────────────────────────────────────────
OS_NAME=""          # 系统标识
OS_VERSION=""       # 系统版本
PKG_UPDATE=""       # 包管理器更新命令
PKG_INSTALL=""      # 包管理器安装命令
NETDATA_CONF_DIR="" # Netdata 配置目录（安装后自动检测）
PARENT_HOST=""      # Parent 节点域名或 IP
PARENT_PORT="443"   # Parent 节点端口（默认 443，走 Caddy TLS）
API_KEY=""          # Streaming API Key（与 Parent 保持一致）
NODE_NAME=""        # 本节点自定义名称（默认 hostname）
RECORD_FILE="/root/.netdata-child.conf"  # 配置记录，供卸载使用


# =============================================================================
# STEP 0: 权限检查
# =============================================================================
check_root() {
    [[ $EUID -ne 0 ]] && error "请以 root 权限运行 (sudo bash $0)"
}


# =============================================================================
# STEP 1: 检测操作系统类型与版本
# =============================================================================
detect_os() {
    step "检测操作系统"

    [[ -f /etc/os-release ]] || error "无法读取 /etc/os-release，不支持的系统"

    # shellcheck source=/dev/null
    source /etc/os-release
    OS_NAME="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    local OS_PRETTY="${PRETTY_NAME:-unknown}"

    case "${OS_NAME}" in
        debian)
            [[ "${OS_VERSION}" =~ ^(11|12|13) ]] || \
                warn "Debian ${OS_VERSION} 未经充分测试，继续执行..."
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
            error "不支持的系统: ${OS_NAME}。支持范围: Debian/Ubuntu/CentOS/Arch"
            ;;
    esac

    ok "系统识别: ${OS_PRETTY}"
    info "版本号: ${OS_VERSION} | 内核: $(uname -r) | 主机名: $(hostname)"
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
# STEP 3: 交互式收集配置信息
# =============================================================================
collect_config() {
    step "配置信息收集"
    echo ""

    # ── 3.1 Parent 节点域名或 IP ──────────────────────────────────────────────
    while true; do
        read -rp "  请输入 Parent 节点域名或 IP (如 netdata.example.com): " PARENT_HOST
        [[ -n "${PARENT_HOST}" && ! "${PARENT_HOST}" =~ [[:space:]] ]] && break
        warn "输入不能为空且不能含空格，请重新输入"
    done
    ok "Parent 地址: ${PARENT_HOST}"

    # ── 3.2 Parent 端口（默认 443） ──────────────────────────────────────────
    read -rp "  请输入 Parent 端口 (默认 443): " INPUT_PORT
    PARENT_PORT="${INPUT_PORT:-443}"
    ok "Parent 端口: ${PARENT_PORT}"

    # ── 3.3 API Key ──────────────────────────────────────────────────────────
    while true; do
        read -rp "  请输入 API Key (从 Parent 部署摘要中复制): " API_KEY
        # 校验 UUID 格式: 8-4-4-4-12
        if [[ "${API_KEY}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
            break
        fi
        warn "API Key 格式不正确（应为 UUID 格式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx）"
    done
    ok "API Key: ${API_KEY}"

    # ── 3.4 节点名称（默认当前 hostname） ─────────────────────────────────────
    local DEFAULT_NAME
    DEFAULT_NAME=$(hostname)
    read -rp "  请输入本节点名称 (默认: ${DEFAULT_NAME}): " NODE_NAME
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

    info "开始安装 Netdata (stable channel, 禁用遥测)..."

    case "${OS_NAME}" in
        arch)
            ${PKG_UPDATE}
            ${PKG_INSTALL} netdata
            ;;
        debian|ubuntu)
            wget -qO /tmp/nd-kickstart.sh https://get.netdata.cloud/kickstart.sh
            bash /tmp/nd-kickstart.sh \
                --stable-channel \
                --disable-telemetry \
                --dont-start-it \
                --no-updates 2>&1 | grep -E "(OK|ERROR|WARN|Installing)" || true
            rm -f /tmp/nd-kickstart.sh
            ;;
        centos)
            # CentOS 8 官方已 EOL，static build 兼容性最佳
            wget -qO /tmp/nd-kickstart.sh https://get.netdata.cloud/kickstart.sh
            bash /tmp/nd-kickstart.sh \
                --stable-channel \
                --disable-telemetry \
                --dont-start-it \
                --static-only 2>&1 | grep -E "(OK|ERROR|WARN|Installing)" || true
            rm -f /tmp/nd-kickstart.sh
            ;;
    esac

    command -v netdata &>/dev/null || error "Netdata 安装失败，请查看上方输出"
    ok "Netdata 安装完成"
}


# =============================================================================
# STEP 5: 配置 Netdata 为 Child（推送）模式
# =============================================================================
configure_netdata() {
    step "配置 Netdata Child 模式"

    # ── 5.1 自动检测 Netdata 配置目录 ────────────────────────────────────────
    if [[ -d /etc/netdata ]]; then
        NETDATA_CONF_DIR="/etc/netdata"
    elif [[ -d /opt/netdata/etc/netdata ]]; then
        NETDATA_CONF_DIR="/opt/netdata/etc/netdata"
    else
        error "找不到 Netdata 配置目录，请确认安装是否成功"
    fi
    info "Netdata 配置目录: ${NETDATA_CONF_DIR}"

    # ── 5.2 主配置：关闭本地 Web UI，Child 不对外暴露 ─────────────────────────
    cat > "${NETDATA_CONF_DIR}/netdata.conf" <<EOF
# =============================================================================
# Netdata 主配置 - Child 推送模式
# 节点名称: ${NODE_NAME}
# 由 setup-netdata-child.sh 自动生成
# =============================================================================

[global]
    # 节点在 Parent Web UI 中显示的名称
    hostname = ${NODE_NAME}

    # Child 本地只保留极短历史（数据推送给 Parent 存储）
    # 减少本地磁盘和内存占用
    history = 3600

[web]
    # 关闭本地 Web 访问，所有数据由 Parent 统一展示
    # Child 节点不需要对外暴露任何端口
    mode = none

[plugins]
    # 开启核心采集插件
    proc      = yes     # CPU、内存、网络、磁盘 I/O
    cgroups   = yes     # 容器/虚拟机资源统计
    diskspace = yes     # 磁盘用量
    apps      = yes     # 进程级资源统计
    # 关闭非必要插件，降低资源占用和噪音
    tc        = no
    nfacct    = no

[ml]
    # Child 关闭 ML（由 Parent 统一做异常检测，节省资源）
    enabled = no
EOF
    ok "netdata.conf 已写入（Web UI 已关闭）"

    # ── 5.3 Streaming 配置：向 Parent 推送数据 ────────────────────────────────
    cat > "${NETDATA_CONF_DIR}/stream.conf" <<EOF
# =============================================================================
# Netdata Streaming 配置 - Child 推送模式
# 由 setup-netdata-child.sh 自动生成
# =============================================================================

[stream]
    # 开启推送模式
    enabled = yes

    # Parent 地址（走 TLS，经 Caddy 反代）
    # 格式: tls:域名:端口
    destination = tls:${PARENT_HOST}:${PARENT_PORT}

    # 与 Parent stream.conf 中配置的 API Key 保持一致
    api key = ${API_KEY}

    # 连接超时（秒）: 超时后自动重试
    timeout seconds = 60

    # 断线重连间隔（秒）: 网络抖动时自动重连
    reconnect delay seconds = 5

    # 推送缓冲区大小（字节）: 1MB，短暂断线时缓存数据
    buffer size bytes = 1048576

    # 连接建立后时钟同步迭代次数
    initial clock resync iterations = 60

    # 压缩传输（减少带宽占用）
    enable compression = yes
EOF
    ok "stream.conf 已写入（推送至 ${PARENT_HOST}:${PARENT_PORT}）"

    # ── 5.4 启动/重启 Netdata ─────────────────────────────────────────────────
    systemctl enable netdata &>/dev/null || true
    systemctl restart netdata

    # 等待服务就绪（最多 15 秒）
    local RETRY=0
    while [[ $RETRY -lt 15 ]]; do
        sleep 1
        if systemctl is-active --quiet netdata; then
            ok "Netdata 服务启动成功"
            return
        fi
        RETRY=$((RETRY + 1))
    done
    error "Netdata 启动超时，请检查: journalctl -u netdata -n 50"
}


# =============================================================================
# STEP 6: 验证与 Parent 的连接
# =============================================================================
verify_connection() {
    step "验证连接状态"

    info "等待 Streaming 连接建立（最多 30 秒）..."

    # 检查 netdata 日志中是否出现连接成功的标志
    local RETRY=0
    local LOG_FILE="/var/log/netdata/error.log"

    # static 安装日志路径不同
    [[ -f /opt/netdata/var/log/netdata/error.log ]] && \
        LOG_FILE="/opt/netdata/var/log/netdata/error.log"

    while [[ $RETRY -lt 30 ]]; do
        sleep 1
        # 检查 systemd journal 中的连接信息
        if journalctl -u netdata -n 50 --no-pager 2>/dev/null | \
            grep -qi "connected to\|streaming\|accepted connection"; then
            ok "Streaming 连接已建立！数据正在推送至 Parent"
            return
        fi
        # 检查日志文件
        if [[ -f "${LOG_FILE}" ]] && \
            grep -qi "connected\|streaming" "${LOG_FILE}" 2>/dev/null; then
            ok "Streaming 连接已建立！"
            return
        fi
        RETRY=$((RETRY + 1))
        printf "."
    done
    echo ""

    # 连接超时，给出排查建议而不是直接报错退出
    warn "30 秒内未检测到连接成功日志，可能原因："
    warn "  1. Parent 域名 DNS 解析未生效（新域名需等待传播）"
    warn "  2. Parent 防火墙未放行 443 端口"
    warn "  3. API Key 与 Parent 配置不一致"
    warn "  4. Caddy 配置未正确加载（检查 Parent 端 Caddy 状态）"
    info "手动排查命令（在本机执行）:"
    info "  journalctl -u netdata -f"
    info "  curl -vk https://${PARENT_HOST}/api/v1/info"
}


# =============================================================================
# STEP 7: 保存配置记录（供卸载使用）
# =============================================================================
save_config_record() {
    step "保存配置记录"

    cat > "${RECORD_FILE}" <<EOF
# Netdata Child 配置记录
# 由 setup-netdata-child.sh 生成于 $(date '+%Y-%m-%d %H:%M:%S')
# 此文件用于卸载脚本读取，请勿随意修改

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
# STEP 8: 卸载功能
# =============================================================================
do_uninstall() {
    step "卸载 Netdata Child 节点"

    # ── 读取安装记录 ────────────────────────────────────────────────────────────
    if [[ -f "${RECORD_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${RECORD_FILE}"
        info "读取配置记录: ${RECORD_FILE}"
    else
        warn "未找到配置记录 (${RECORD_FILE})，进入手动模式"
        NETDATA_CONF_DIR="/etc/netdata"
    fi

    # ── 确认卸载 ────────────────────────────────────────────────────────────────
    echo ""
    warn "即将执行以下卸载操作:"
    echo "  1. 停止并禁用 Netdata 服务"
    echo "  2. 卸载 Netdata 软件包及数据"
    echo "  3. 清理配置文件和日志"
    echo "  4. 删除配置记录文件"
    echo ""
    read -rp "  确认卸载？此操作不可撤销 [y/N]: " CONFIRM
    [[ "${CONFIRM}" =~ ^[Yy]$ ]] || { info "已取消卸载"; exit 0; }
    echo ""

    # ── 停止服务 ─────────────────────────────────────────────────────────────────
    info "停止 Netdata 服务..."
    systemctl stop    netdata 2>/dev/null && ok "Netdata 已停止" || warn "服务未运行"
    systemctl disable netdata 2>/dev/null || true

    # ── 卸载软件包 ───────────────────────────────────────────────────────────────
    info "卸载 Netdata 软件包..."
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
            [[ -d /opt/netdata ]] && rm -rf /opt/netdata && ok "已删除 /opt/netdata"
            ;;
    esac

    # ── 清理残留文件 ─────────────────────────────────────────────────────────────
    info "清理 Netdata 残留文件..."
    local NETDATA_DIRS=(
        /etc/netdata
        /var/lib/netdata
        /var/cache/netdata
        /var/log/netdata
        /opt/netdata/etc/netdata
    )
    for dir in "${NETDATA_DIRS[@]}"; do
        [[ -d "${dir}" ]] && rm -rf "${dir}" && info "  已删除: ${dir}"
    done
    ok "残留文件清理完成"

    # ── 删除配置记录 ─────────────────────────────────────────────────────────────
    rm -f "${RECORD_FILE}" 2>/dev/null || true

    echo ""
    ok "卸载完成！"
}


# =============================================================================
# STEP 9: 显示部署摘要
# =============================================================================
show_summary() {
    local LINE="──────────────────────────────────────────────────────────"

    # 获取本机公网 IP（用于参考，非必须）
    local PUBLIC_IP
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
                echo "获取失败")

    # 获取 MACHINE_GUID（Netdata 节点唯一标识）
    local MACHINE_GUID
    MACHINE_GUID=$(cat /var/lib/netdata/registry/netdata.public.unique.id 2>/dev/null || \
                   cat /opt/netdata/var/lib/netdata/registry/netdata.public.unique.id 2>/dev/null || \
                   echo "生成中，稍后可查")

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
    printf "${GREEN}║${NC}  %-16s : %s\n"              "配置记录"     "${RECORD_FILE}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}[提示]${NC} 在 Parent Web UI 中等待约 10~30 秒即可看到本节点"
    echo -e "${GREEN}║${NC}  ${YELLOW}[提示]${NC} 实时日志: journalctl -u netdata -f"
    echo -e "${GREEN}║${NC}  ${YELLOW}[提示]${NC} 卸载命令: bash $0 uninstall"
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
