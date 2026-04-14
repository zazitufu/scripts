#!/bin/bash
# =============================================================================
# Netdata Parent 节点一键部署脚本
# 支持系统: Debian 11/12/13, Ubuntu 20.04+, CentOS/Rocky/Alma 8+, Arch Linux
# 功能说明:
#   - 安装并配置 Netdata (Parent/接收模式)
#   - 自动生成 Caddy2 反代配置 (含安全加固)
#   - 自动配置 Fail2ban jail (仅在已安装时)
#   - 提供完整卸载功能
# 用法:
#   bash setup-netdata-parent.sh            # 安装
#   bash setup-netdata-parent.sh uninstall  # 卸载
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

# ─── 全局变量（后续步骤填充） ──────────────────────────────────────────────────
OS_NAME=""          # 系统标识: debian / ubuntu / centos / arch
OS_VERSION=""       # 系统版本号
PKG_UPDATE=""       # 包管理器更新命令
PKG_INSTALL=""      # 包管理器安装命令
F2B_INSTALLED=false # Fail2ban 是否已安装
NETDATA_CONF_DIR="" # Netdata 配置目录
CADDY_CONF_DIR=""   # Caddy 配置片段目录
CADDY_CONF_FILE=""  # 最终生成的 Caddy 配置文件路径
PARENT_DOMAIN=""    # 用户输入的 Parent 域名
BA_USER=""          # Basic Auth 用户名
BA_PASS=""          # Basic Auth 明文密码（仅用于最终摘要显示）
BA_HASH=""          # Basic Auth bcrypt 哈希（写入 Caddy 配置）
API_KEY=""          # Netdata Streaming API Key (UUID)
RECORD_FILE="/root/.netdata-parent.conf"  # 配置记录，用于卸载


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

    # 所有主流 Linux 发行版均有此文件
    [[ -f /etc/os-release ]] || error "无法读取 /etc/os-release，不支持的系统"

    # shellcheck source=/dev/null
    source /etc/os-release
    OS_NAME="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    local OS_PRETTY="${PRETTY_NAME:-unknown}"

    case "${OS_NAME}" in
        debian)
            # 检查版本：支持 11 (Bullseye) / 12 (Bookworm) / 13 (Trixie)
            if [[ ! "${OS_VERSION}" =~ ^(11|12|13) ]]; then
                warn "Debian ${OS_VERSION} 未经充分测试，继续执行..."
            fi
            PKG_UPDATE="apt-get update -qq"
            PKG_INSTALL="apt-get install -y -qq"
            ;;
        ubuntu)
            # 支持 20.04 LTS 及以上
            PKG_UPDATE="apt-get update -qq"
            PKG_INSTALL="apt-get install -y -qq"
            ;;
        centos|rhel|rocky|almalinux)
            # 统一标识为 centos，兼容 CentOS 8 / Rocky / AlmaLinux
            OS_NAME="centos"
            PKG_UPDATE="yum makecache -q"
            PKG_INSTALL="yum install -y -q"
            # 优先使用 dnf（CentOS 8+ 默认）
            if command -v dnf &>/dev/null; then
                PKG_UPDATE="dnf makecache -q"
                PKG_INSTALL="dnf install -y -q"
            fi
            ;;
        arch|manjaro|endeavouros)
            # Arch 系列
            OS_NAME="arch"
            PKG_UPDATE="pacman -Sy --noconfirm"
            PKG_INSTALL="pacman -S --noconfirm --needed"
            ;;
        *)
            error "不支持的系统: ${OS_NAME}。支持范围: Debian/Ubuntu/CentOS/Arch"
            ;;
    esac

    ok "系统识别: ${OS_PRETTY}"
    info "版本号: ${OS_VERSION} | 内核: $(uname -r)"
}


# =============================================================================
# STEP 2: 检查并安装依赖
# =============================================================================
check_deps() {
    step "检查依赖"

    # 必需工具列表
    local DEPS=(curl wget openssl)
    local MISSING=()

    for dep in "${DEPS[@]}"; do
        if command -v "${dep}" &>/dev/null; then
            ok "${dep} 已安装 ($(command -v "${dep}"))"
        else
            warn "${dep} 未安装，将自动安装"
            MISSING+=("${dep}")
        fi
    done

    # 安装缺失的依赖
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        info "正在安装: ${MISSING[*]}"
        ${PKG_UPDATE}
        ${PKG_INSTALL} "${MISSING[@]}"
        ok "依赖安装完成"
    fi

    # ── Caddy2 检查（用户已自行安装，不代为安装，缺失则报错退出） ──────────────
    if ! command -v caddy &>/dev/null; then
        error "未检测到 Caddy2。请先安装 Caddy2 再运行此脚本\n       参考: https://caddyserver.com/docs/install"
    fi
    local CADDY_VER
    CADDY_VER=$(caddy version 2>/dev/null | awk '{print $1}' || echo "unknown")
    ok "Caddy2 已就绪: ${CADDY_VER}"

    # ── Fail2ban 检查（已安装则后续添加 jail，未安装则跳过） ──────────────────
    if command -v fail2ban-client &>/dev/null; then
        F2B_INSTALLED=true
        ok "Fail2ban 已安装，将自动添加 jail 配置"
    else
        F2B_INSTALLED=false
        warn "未检测到 Fail2ban，跳过 Fail2ban 配置（建议安装以提升安全性）"
    fi
}


# =============================================================================
# STEP 3: 检测 Caddy 配置片段目录
# =============================================================================
detect_caddy_dir() {
    step "检测 Caddy2 配置目录"

    if [[ -d "/etc/caddy/233boy" ]]; then
        # 233boy 脚本安装的 Caddy 通常使用此目录
        CADDY_CONF_DIR="/etc/caddy/233boy"
        ok "检测到目录: /etc/caddy/233boy/"

    elif [[ -d "/etc/caddy/conf.d" ]]; then
        # 标准自定义片段目录
        CADDY_CONF_DIR="/etc/caddy/conf.d"
        ok "检测到目录: /etc/caddy/conf.d/"

    else
        # 两个目录都不存在，让用户选择创建哪个
        warn "未找到 /etc/caddy/233boy 或 /etc/caddy/conf.d"
        echo ""
        echo "  请选择要创建的配置目录:"
        echo "    1) /etc/caddy/233boy  (233boy 风格)"
        echo "    2) /etc/caddy/conf.d  (标准风格)"
        echo ""
        read -rp "  请输入选项 [1/2] (默认 2): " DIR_CHOICE
        case "${DIR_CHOICE:-2}" in
            1) CADDY_CONF_DIR="/etc/caddy/233boy" ;;
            *) CADDY_CONF_DIR="/etc/caddy/conf.d" ;;
        esac
        mkdir -p "${CADDY_CONF_DIR}"
        ok "已创建目录: ${CADDY_CONF_DIR}"

        # 检查主 Caddyfile 是否已 import 此目录，否则提示用户手动处理
        if [[ -f /etc/caddy/Caddyfile ]]; then
            if ! grep -q "import.*${CADDY_CONF_DIR}" /etc/caddy/Caddyfile 2>/dev/null; then
                warn "请确保 /etc/caddy/Caddyfile 中包含以下 import 语句:"
                warn "  import ${CADDY_CONF_DIR}/*.conf"
            fi
        fi
    fi

    info "Caddy 配置片段目录: ${CADDY_CONF_DIR}"
}


# =============================================================================
# STEP 4: 交互式收集配置信息
# =============================================================================
collect_config() {
    step "配置信息收集"
    echo ""

    # ── 4.1 Parent 域名 ─────────────────────────────────────────────────────
    while true; do
        read -rp "  请输入 Parent 节点域名 (如 netdata.example.com): " PARENT_DOMAIN
        # 简单校验：非空且不含空格
        if [[ -n "${PARENT_DOMAIN}" && ! "${PARENT_DOMAIN}" =~ [[:space:]] ]]; then
            break
        fi
        warn "域名格式不正确，请重新输入"
    done
    ok "域名: ${PARENT_DOMAIN}"

    # ── 4.2 Basic Auth 用户名 ──────────────────────────────────────────────
    read -rp "  请输入 Web UI 登录用户名 (默认: admin): " BA_USER
    BA_USER="${BA_USER:-admin}"
    ok "用户名: ${BA_USER}"

    # ── 4.3 Basic Auth 密码（最少 8 位，需二次确认） ─────────────────────────
    echo ""
    while true; do
        read -rsp "  请输入 Web UI 登录密码 (最少 8 位): " BA_PASS
        echo
        if [[ ${#BA_PASS} -lt 8 ]]; then
            warn "密码至少 8 位，请重新输入"
            continue
        fi
        read -rsp "  请再次确认密码: " BA_PASS2
        echo
        if [[ "${BA_PASS}" == "${BA_PASS2}" ]]; then
            break
        fi
        warn "两次输入不一致，请重新输入"
    done
    ok "密码设置完成"

    # ── 4.4 用 Caddy 内置命令生成 bcrypt 哈希（避免依赖 htpasswd 等外部工具） ──
    info "生成 Basic Auth 密码哈希 (bcrypt)..."
    BA_HASH=$(caddy hash-password --plaintext "${BA_PASS}" 2>/dev/null) || \
        error "caddy hash-password 执行失败，请确认 Caddy2 版本 >= 2.0"
    [[ -z "${BA_HASH}" ]] && error "密码哈希为空，请检查 Caddy2 是否正常"
    ok "密码哈希生成完成"

    # ── 4.5 自动生成 Streaming API Key (UUID 格式) ────────────────────────────
    # 优先读内核 uuid 接口，其次 uuidgen，最后 openssl 拼接
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        API_KEY=$(cat /proc/sys/kernel/random/uuid)
    elif command -v uuidgen &>/dev/null; then
        API_KEY=$(uuidgen | tr '[:upper:]' '[:lower:]')
    else
        local R
        R=$(openssl rand -hex 16)
        API_KEY="${R:0:8}-${R:8:4}-${R:12:4}-${R:16:4}-${R:20:12}"
    fi
    ok "API Key 已生成: ${API_KEY}"

    # 最终配置文件路径
    CADDY_CONF_FILE="${CADDY_CONF_DIR}/${PARENT_DOMAIN}.conf"
    info "Caddy 配置将写入: ${CADDY_CONF_FILE}"
    echo ""
}


# =============================================================================
# STEP 5: 安装 Netdata
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
            # Arch 直接用官方仓库
            ${PKG_UPDATE}
            ${PKG_INSTALL} netdata
            ;;
        debian|ubuntu)
            # 使用官方 kickstart 脚本
            wget -qO /tmp/nd-kickstart.sh https://get.netdata.cloud/kickstart.sh
            bash /tmp/nd-kickstart.sh \
                --stable-channel \
                --disable-telemetry \
                --dont-start-it \
                --no-updates 2>&1 | grep -E "(OK|ERROR|WARN|Installing)" || true
            rm -f /tmp/nd-kickstart.sh
            ;;
        centos)
            # CentOS 8 官方已 EOL，用 static build 兼容性最好
            wget -qO /tmp/nd-kickstart.sh https://get.netdata.cloud/kickstart.sh
            bash /tmp/nd-kickstart.sh \
                --stable-channel \
                --disable-telemetry \
                --dont-start-it \
                --static-only 2>&1 | grep -E "(OK|ERROR|WARN|Installing)" || true
            rm -f /tmp/nd-kickstart.sh
            ;;
    esac

    # 验证安装结果
    command -v netdata &>/dev/null || error "Netdata 安装失败，请查看上方输出排查原因"
    ok "Netdata 安装完成"
}


# =============================================================================
# STEP 6: 配置 Netdata 为 Parent（接收）模式
# =============================================================================
configure_netdata() {
    step "配置 Netdata Parent 模式"

    # ── 6.1 自动检测 Netdata 配置目录（兼容包安装和 static 安装） ──────────────
    if [[ -d /etc/netdata ]]; then
        NETDATA_CONF_DIR="/etc/netdata"
    elif [[ -d /opt/netdata/etc/netdata ]]; then
        NETDATA_CONF_DIR="/opt/netdata/etc/netdata"
    else
        error "找不到 Netdata 配置目录，请确认 Netdata 安装是否成功"
    fi
    info "Netdata 配置目录: ${NETDATA_CONF_DIR}"

    # ── 6.2 主配置文件：限制监听本地，性能与功能配置 ────────────────────────────
    cat > "${NETDATA_CONF_DIR}/netdata.conf" <<EOF
# =============================================================================
# Netdata 主配置 - Parent 接收模式
# 由 setup-netdata-parent.sh 自动生成
# =============================================================================

[global]
    # 历史数据保留（秒）: 604800 = 7天
    # 配合 dbengine 可突破此限制，取决于磁盘空间
    history = 604800

    # 多线程: 0 = 自动检测 CPU 核心数
    cpu cores = 0

[web]
    # 只监听本地回环，Caddy 负责对外反代
    # 不对任何外部 IP 暴露，即使防火墙有问题也安全
    bind to = 127.0.0.1:19999

    # 允许来自本地的连接（Caddy 反代）
    allow connections from = 127.0.0.1

    # 启用 gzip 压缩，减少 Caddy 到 Netdata 的带宽
    enable gzip compression = yes

[ml]
    # 机器学习异常检测（消耗少量 CPU，建议开启）
    enabled = yes

[plugins]
    # 开启核心插件
    proc    = yes
    cgroups = yes
    diskspace = yes
    apps    = yes
    # 关闭非必要插件，降低噪音和资源占用
    tc      = no
    nfacct  = no
EOF
    ok "netdata.conf 已写入"

    # ── 6.3 Streaming 配置：开启 Parent 模式，接受 Child 推送 ──────────────────
    cat > "${NETDATA_CONF_DIR}/stream.conf" <<EOF
# =============================================================================
# Netdata Streaming 配置 - Parent 接收模式
# 由 setup-netdata-parent.sh 自动生成
# =============================================================================

# ── 本节点自身不向上游推送数据（纯 Parent 角色） ─────────────────────────────
[stream]
    enabled = no

# ── Child 节点认证配置 ────────────────────────────────────────────────────────
# 所有持有此 API Key 的 Child 均可推送数据
# 无需为每台 Child 单独配置，新增 Child 部署后自动识别
[${API_KEY}]
    # 开启此 Key 的接收
    enabled = yes

    # 数据存储模式: dbengine 支持长期磁盘存储（推荐）
    default memory mode = dbengine

    # Child 连接后延迟触发告警（秒）: 避免启动时误报
    default postpone alarms on connect seconds = 60

    # 继承 Child 的健康告警配置
    health enabled by default = auto

    # 允许 Child 发送自定义标签
    allow labels from = *
EOF
    ok "stream.conf 已写入"

    # ── 6.4 启动/重启 Netdata ──────────────────────────────────────────────────
    systemctl enable netdata &>/dev/null || true
    systemctl restart netdata

    # 等待服务就绪
    local RETRY=0
    while [[ $RETRY -lt 10 ]]; do
        sleep 1
        if systemctl is-active --quiet netdata; then
            ok "Netdata 服务启动成功 (PID: $(systemctl show netdata --property MainPID --value))"
            return
        fi
        RETRY=$((RETRY + 1))
    done
    error "Netdata 启动超时，请检查日志: journalctl -u netdata -n 50"
}


# =============================================================================
# STEP 7: 生成 Caddy2 配置文件
# =============================================================================
configure_caddy() {
    step "生成 Caddy2 配置"

    # ── 备份已有同名配置 ────────────────────────────────────────────────────────
    if [[ -f "${CADDY_CONF_FILE}" ]]; then
        local BACKUP="${CADDY_CONF_FILE}.bak.$(date +%Y%m%d%H%M%S)"
        cp "${CADDY_CONF_FILE}" "${BACKUP}"
        warn "已备份旧配置: ${BACKUP}"
    fi

    # ── 确保日志目录存在 ────────────────────────────────────────────────────────
    mkdir -p /var/log/caddy
    # 尝试设置 caddy 用户权限（不同系统 caddy 用户名可能不同，失败不中断）
    chown caddy:caddy /var/log/caddy 2>/dev/null || \
        chown www-data:www-data /var/log/caddy 2>/dev/null || true

    # ── 写入 Caddy 配置 ─────────────────────────────────────────────────────────
    cat > "${CADDY_CONF_FILE}" <<EOF
# =============================================================================
# Netdata Parent - Caddy2 反代配置
# 域名: ${PARENT_DOMAIN}
# 由 setup-netdata-parent.sh 自动生成于 $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

${PARENT_DOMAIN} {

    # ── 访问日志（JSON 格式，供 Fail2ban 解析） ─────────────────────────────────
    log {
        output file /var/log/caddy/${PARENT_DOMAIN}_access.log {
            roll_size    50mb   # 单个日志文件最大 50MB
            roll_keep    7      # 保留最近 7 个轮转文件
            roll_keep_for 720h  # 最多保留 30 天
        }
        format json
        level  INFO
    }

    # ── 隐藏服务器指纹，添加安全响应头 ──────────────────────────────────────────
    header {
        # 删除暴露服务器类型的响应头
        -Server
        -X-Powered-By
        -Via
        # 告知浏览器禁止 MIME 嗅探
        X-Content-Type-Options    "nosniff"
        # 禁止本站被嵌入 iframe（防点击劫持）
        X-Frame-Options           "DENY"
        # 旧版浏览器 XSS 过滤
        X-XSS-Protection          "1; mode=block"
        # 不发送 Referer 头
        Referrer-Policy           "no-referrer"
        # 禁用不必要的浏览器功能
        Permissions-Policy        "geolocation=(), microphone=(), camera=()"
        # 强制 HTTPS（1年，含子域）
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    # ── 只允许 GET / POST / HEAD 方法，拒绝其他（如 TRACE/PUT/DELETE） ───────────
    @bad_method not method GET POST HEAD
    respond @bad_method "Method Not Allowed" 405

    # ── 封锁已知恶意扫描器 User-Agent ────────────────────────────────────────────
    # 444 表示直接断开 TCP 连接，不返回任何内容，令扫描器无法判断服务状态
    @bad_ua {
        header User-Agent ""           # 空 UA，通常为自动化脚本
        header User-Agent "*masscan*"
        header User-Agent "*zgrab*"
        header User-Agent "*nikto*"
        header User-Agent "*sqlmap*"
        header User-Agent "*nmap*"
        header User-Agent "*dirbuster*"
        header User-Agent "*hydra*"
        header User-Agent "*medusa*"
        header User-Agent "*w3af*"
        header User-Agent "*acunetix*"
        header User-Agent "*burpsuite*"
        header User-Agent "*nuclei*"
        header User-Agent "*gobuster*"
        header User-Agent "*wfuzz*"
    }
    respond @bad_ua 444

    # ── 封锁常见漏洞探测路径 ─────────────────────────────────────────────────────
    # 这些路径与 Netdata 无关，出现则为扫描行为，直接断连
    @attack_path {
        path /.env
        path /.env.*
        path /.git*
        path /.svn*
        path /.htaccess
        path /.htpasswd
        path /.DS_Store
        path /wp-login.php
        path /wp-admin*
        path /wp-content*
        path /xmlrpc.php
        path /phpmyadmin*
        path /pma*
        path /adminer*
        path /shell*
        path /webshell*
        path /cmd*
        path /backup*
        path /database*
        path /config*
        path *.php
        path *.asp
        path *.aspx
        path *.jsp
        path *.cgi
        path *.sh
    }
    respond @attack_path 444

    # ── Netdata Streaming 数据接收路径 ───────────────────────────────────────────
    # Child 节点通过 WebSocket 推送数据到此路径
    # 此路径不需要 Basic Auth（Child 通过 API Key 鉴权）
    handle /api/v1/stream* {
        reverse_proxy 127.0.0.1:19999 {
            transport http {
                dial_timeout            10s
                response_header_timeout 30s
                # 保持长连接（Streaming 需要持续连接）
                keepalive               1m
            }
            # 透传真实 IP 给 Netdata（用于日志记录）
            header_up X-Forwarded-For {remote_host}
            header_up X-Real-IP {remote_host}
        }
    }

    # ── Web UI 访问（浏览器查看监控面板，需要 Basic Auth 认证） ─────────────────
    handle /* {
        # Basic Auth 保护：防止未授权访问监控数据
        basicauth {
            # 用户名: ${BA_USER}
            # 密码已加密存储（bcrypt），明文密码请妥善保管
            ${BA_USER} ${BA_HASH}
        }
        reverse_proxy 127.0.0.1:19999 {
            transport http {
                dial_timeout 10s
            }
            header_up X-Forwarded-For {remote_host}
            header_up X-Real-IP {remote_host}
        }
    }
}
EOF
    ok "Caddy 配置文件已写入: ${CADDY_CONF_FILE}"

    # ── 验证 Caddy 配置语法 ─────────────────────────────────────────────────────
    info "验证 Caddy 配置语法..."
    # caddy validate 需要完整的 Caddyfile 入口，只能验证格式
    if caddy fmt --overwrite "${CADDY_CONF_FILE}" 2>/dev/null; then
        ok "Caddy 配置格式校验通过"
    else
        warn "caddy fmt 返回异常，配置可能有问题，请手动确认"
    fi

    # ── 重载 Caddy（不中断已有连接） ───────────────────────────────────────────
    info "重载 Caddy 配置..."
    if systemctl reload caddy 2>/dev/null; then
        ok "Caddy 已热重载"
    elif systemctl restart caddy 2>/dev/null; then
        ok "Caddy 已重启"
    else
        error "Caddy 重载失败，请手动检查: journalctl -u caddy -n 30\n       并验证配置: caddy validate --config /etc/caddy/Caddyfile"
    fi
}


# =============================================================================
# STEP 8: 配置 Fail2ban（仅添加 jail，不安装）
# =============================================================================
configure_fail2ban() {
    step "配置 Fail2ban"

    if [[ "${F2B_INSTALLED}" != "true" ]]; then
        warn "Fail2ban 未安装，跳过此步骤"
        info "建议安装: ${PKG_INSTALL} fail2ban，并重新运行脚本"
        return
    fi

    # ── 8.1 创建针对 Caddy JSON 日志的 filter ───────────────────────────────────
    cat > /etc/fail2ban/filter.d/caddy-netdata.conf <<EOF
# Fail2ban Filter: caddy-netdata
# 解析 Caddy JSON 格式访问日志，匹配产生 4xx/5xx 响应的客户端 IP
# 由 setup-netdata-parent.sh 自动生成

[Definition]
# 匹配 JSON 日志中 remote_ip 字段 + 4xx/5xx 状态码
failregex = ^.*"remote_ip":"<HOST>".*"status":4[0-9]{2}.*$
            ^.*"remote_ip":"<HOST>".*"status":5[0-9]{2}.*$

# 忽略规则（可按需添加）
ignoreregex =

# 日志格式说明: Caddy 使用 JSON 格式，每行一条请求记录
# 示例:
#   {"level":"info","ts":...,"remote_ip":"1.2.3.4",...,"status":403,...}
datepattern = {ts}
EOF
    ok "Fail2ban filter 已创建: /etc/fail2ban/filter.d/caddy-netdata.conf"

    # ── 8.2 创建 jail 配置 ────────────────────────────────────────────────────────
    cat > /etc/fail2ban/jail.d/caddy-netdata.conf <<EOF
# Fail2ban Jail: caddy-netdata
# 基于 Caddy 访问日志，自动封锁持续攻击的 IP
# 由 setup-netdata-parent.sh 自动生成

[caddy-netdata]
enabled  = true

# 监听的端口（http=80, https=443）
port     = http,https

# 使用上方定义的 filter
filter   = caddy-netdata

# Caddy 访问日志路径（与 Caddyfile 中 log output file 一致）
logpath  = /var/log/caddy/${PARENT_DOMAIN}_access.log

# 触发条件: findtime 秒内出现 maxretry 次失败 → 封禁
maxretry = 20        # 允许失败次数
findtime = 60        # 统计时间窗口（秒）

# 封禁时长: 86400 秒 = 24 小时
# 改为 -1 则永久封禁（需手动解封: fail2ban-client unban <IP>）
bantime  = 86400

# 永远不封禁本机
ignoreip = 127.0.0.1/8 ::1
EOF
    ok "Fail2ban jail 已创建: /etc/fail2ban/jail.d/caddy-netdata.conf"

    # ── 8.3 重载 Fail2ban ────────────────────────────────────────────────────────
    info "重载 Fail2ban..."
    if fail2ban-client reload 2>/dev/null; then
        ok "Fail2ban 重载成功"
        # 等待 jail 启动并验证
        sleep 2
        if fail2ban-client status caddy-netdata &>/dev/null; then
            ok "Jail 'caddy-netdata' 已激活"
            fail2ban-client status caddy-netdata | grep -E "Status|Filter|Actions" || true
        else
            warn "Jail 状态异常，请检查: fail2ban-client status caddy-netdata"
        fi
    else
        warn "Fail2ban 重载失败，请手动执行: fail2ban-client reload"
    fi
}


# =============================================================================
# STEP 9: 保存配置记录（供卸载使用）
# =============================================================================
save_config_record() {
    step "保存配置记录"

    cat > "${RECORD_FILE}" <<EOF
# Netdata Parent 配置记录
# 由 setup-netdata-parent.sh 生成于 $(date '+%Y-%m-%d %H:%M:%S')
# 此文件用于卸载脚本读取，请勿随意修改

PARENT_DOMAIN="${PARENT_DOMAIN}"
API_KEY="${API_KEY}"
BA_USER="${BA_USER}"
BA_HASH="${BA_HASH}"
CADDY_CONF_FILE="${CADDY_CONF_FILE}"
CADDY_CONF_DIR="${CADDY_CONF_DIR}"
NETDATA_CONF_DIR="${NETDATA_CONF_DIR}"
OS_NAME="${OS_NAME}"
EOF
    # 限制只有 root 可读，因为包含密码哈希
    chmod 600 "${RECORD_FILE}"
    ok "配置记录已保存: ${RECORD_FILE}"
}


# =============================================================================
# STEP 10: 卸载功能
# =============================================================================
do_uninstall() {
    step "卸载 Netdata Parent 节点"

    # ── 读取安装记录 ────────────────────────────────────────────────────────────
    if [[ -f "${RECORD_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${RECORD_FILE}"
        info "读取配置记录: ${RECORD_FILE}"
    else
        warn "未找到配置记录 (${RECORD_FILE})"
        warn "将尝试手动模式定位文件"
        read -rp "  请输入当时配置的 Parent 域名: " PARENT_DOMAIN
        [[ -d "/etc/caddy/233boy" ]] && CADDY_CONF_DIR="/etc/caddy/233boy" || CADDY_CONF_DIR="/etc/caddy/conf.d"
        CADDY_CONF_FILE="${CADDY_CONF_DIR}/${PARENT_DOMAIN}.conf"
        NETDATA_CONF_DIR="/etc/netdata"
    fi

    # ── 确认卸载 ────────────────────────────────────────────────────────────────
    echo ""
    warn "即将执行以下卸载操作:"
    echo "  1. 停止并禁用 Netdata 服务"
    echo "  2. 卸载 Netdata 软件包及数据"
    echo "  3. 删除 Caddy 配置: ${CADDY_CONF_FILE}"
    echo "  4. 删除 Fail2ban jail 配置"
    echo "  5. 删除访问日志文件"
    echo "  6. 删除配置记录文件"
    echo ""
    read -rp "  确认卸载？此操作不可撤销 [y/N]: " CONFIRM
    [[ "${CONFIRM}" =~ ^[Yy]$ ]] || { info "已取消卸载"; exit 0; }
    echo ""

    # ── 停止 Netdata ─────────────────────────────────────────────────────────────
    info "停止 Netdata 服务..."
    systemctl stop    netdata 2>/dev/null && ok "Netdata 已停止" || warn "Netdata 服务未运行"
    systemctl disable netdata 2>/dev/null || true

    # ── 卸载 Netdata 软件包 ──────────────────────────────────────────────────────
    info "卸载 Netdata 软件包..."
    case "${OS_NAME}" in
        arch)
            pacman -Rns --noconfirm netdata 2>/dev/null && ok "Netdata 已卸载" || warn "卸载失败或已不存在"
            ;;
        debian|ubuntu)
            apt-get purge -y netdata 2>/dev/null && ok "Netdata 已卸载" || warn "卸载失败或已不存在"
            apt-get autoremove -y 2>/dev/null || true
            ;;
        centos)
            yum remove -y netdata 2>/dev/null || warn "yum 卸载失败或已不存在"
            # 清理 static 安装残留
            [[ -d /opt/netdata ]] && rm -rf /opt/netdata && ok "已删除 /opt/netdata"
            ;;
    esac

    # ── 清理 Netdata 配置、数据、日志 ───────────────────────────────────────────
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
    ok "Netdata 残留文件清理完成"

    # ── 删除 Caddy 配置 ──────────────────────────────────────────────────────────
    info "删除 Caddy 配置..."
    if [[ -f "${CADDY_CONF_FILE}" ]]; then
        rm -f "${CADDY_CONF_FILE}"
        ok "已删除: ${CADDY_CONF_FILE}"
        systemctl reload caddy 2>/dev/null && ok "Caddy 已重载" || warn "Caddy 重载失败，请手动执行"
    else
        warn "Caddy 配置不存在: ${CADDY_CONF_FILE}"
    fi

    # ── 删除 Fail2ban 配置 ───────────────────────────────────────────────────────
    info "清理 Fail2ban 配置..."
    rm -f /etc/fail2ban/filter.d/caddy-netdata.conf 2>/dev/null || true
    rm -f /etc/fail2ban/jail.d/caddy-netdata.conf   2>/dev/null || true
    if command -v fail2ban-client &>/dev/null; then
        fail2ban-client reload 2>/dev/null && ok "Fail2ban 已重载" || warn "Fail2ban 重载失败"
    fi

    # ── 删除日志文件 ─────────────────────────────────────────────────────────────
    info "清理日志文件..."
    rm -f "/var/log/caddy/${PARENT_DOMAIN}_access.log"* 2>/dev/null || true
    ok "日志已清理"

    # ── 删除配置记录 ─────────────────────────────────────────────────────────────
    rm -f "${RECORD_FILE}" 2>/dev/null || true

    echo ""
    ok "卸载完成！Caddy2 本身未被卸载（按您要求保留）"
}


# =============================================================================
# STEP 11: 显示部署摘要
# =============================================================================
show_summary() {
    # 计算字段对齐
    local LINE="──────────────────────────────────────────────────────────"
    echo ""
    echo -e "${GREEN}╔${LINE}╗${NC}"
    echo -e "${GREEN}║${NC}   ${BOLD}Netdata Parent 节点部署完成！${NC}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    printf "${GREEN}║${NC}  %-14s : ${CYAN}%s${NC}\n" "访问地址" "https://${PARENT_DOMAIN}"
    printf "${GREEN}║${NC}  %-14s : ${CYAN}%s${NC}\n" "Web UI 用户名" "${BA_USER}"
    printf "${GREEN}║${NC}  %-14s : ${CYAN}%s${NC}\n" "Web UI 密码" "${BA_PASS}"
    printf "${GREEN}║${NC}  %-14s : ${CYAN}%s${NC}\n" "API Key" "${API_KEY}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    printf "${GREEN}║${NC}  %-14s : %s\n" "Caddy 配置" "${CADDY_CONF_FILE}"
    printf "${GREEN}║${NC}  %-14s : %s\n" "配置记录" "${RECORD_FILE}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}部署 Child 节点时，使用以下参数:${NC}"
    printf "${GREEN}║${NC}    PARENT_HOST = ${CYAN}%s${NC}\n" "${PARENT_DOMAIN}"
    printf "${GREEN}║${NC}    API_KEY     = ${CYAN}%s${NC}\n" "${API_KEY}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}[提示]${NC} 卸载命令: bash $0 uninstall"
    echo -e "${GREEN}║${NC}  ${YELLOW}[提示]${NC} 请妥善保存 API Key 和密码！"
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
    echo "  ║     Netdata Parent 节点一键部署脚本                  ║"
    echo "  ║     支持: Debian 11-13 / Ubuntu / CentOS / Arch      ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    local ACTION="${1:-install}"

    case "${ACTION}" in
        install)
            check_root
            detect_os
            check_deps
            detect_caddy_dir
            collect_config
            install_netdata
            configure_netdata
            configure_caddy
            configure_fail2ban
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
            echo "  install   - 部署 Netdata Parent 节点（默认）"
            echo "  uninstall - 卸载所有已部署组件"
            exit 1
            ;;
    esac
}

main "$@"
