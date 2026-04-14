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

# -u: 使用未定义变量时报错
# -o pipefail: 管道中任意命令失败则整体失败
# 注意: 故意不加 -e（errexit）
# 原因: set -e 会将 [[ condition ]] && cmd 中 condition 为 false 时
#       整体 exit code=1 误判为脚本错误并无声退出
#       改为在关键位置使用 if/fi 或显式检查返回值
set -uo pipefail

# ─── 颜色输出工具函数 ─────────────────────────────────────────────────────────
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
F2B_INSTALLED=false
NETDATA_CONF_DIR=""
CADDY_CONF_DIR=""
CADDY_CONF_FILE=""
PARENT_DOMAIN=""
BA_USER=""
BA_PASS=""
BA_HASH=""
API_KEY=""
RECORD_FILE="/root/.netdata-parent.conf"


# =============================================================================
# STEP 0: 权限检查
# =============================================================================
check_root() {
    # 使用 if/fi 而非 [[ ]] && error
    # 原因: [[ $EUID -ne 0 ]] && error 在 EUID=0（是root）时
    #       [[ ]] 返回 exit code=1（false），整体表达式=1
    #       即使没有 set -e，某些 shell 配置也会触发非预期退出
    if [[ $EUID -ne 0 ]]; then
        error "请以 root 权限运行 (sudo bash $0)"
    fi
}


# =============================================================================
# STEP 1: 检测操作系统类型与版本
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

    local DEPS=(curl wget openssl)
    local MISSING=()

    for dep in "${DEPS[@]}"; do
        # 全部使用 if/fi，不用 [[ ]] && ok || warn 链式写法
        # 原因: 链式写法在中间某步非零退出时行为不可预测
        if command -v "${dep}" &>/dev/null; then
            ok "${dep} 已安装 ($(command -v "${dep}"))"
        else
            warn "${dep} 未安装，将自动安装"
            MISSING+=("${dep}")
        fi
    done

    if ! command -v caddy &>/dev/null; then
        error "未检测到 Caddy2。请先安装 Caddy2 再运行此脚本\n       参考: https://caddyserver.com/docs/install"
    fi
    local CADDY_VER
    CADDY_VER=$(caddy version 2>/dev/null | awk '{print $1}' || echo "unknown")
    ok "Caddy2 已就绪: ${CADDY_VER}"

    if command -v fail2ban-client &>/dev/null; then
        F2B_INSTALLED=true
        ok "Fail2ban 已安装，将自动添加 jail 配置"
    else
        F2B_INSTALLED=false
        warn "未检测到 Fail2ban，跳过 Fail2ban 配置"
    fi

    if [[ ${#MISSING[@]} -gt 0 ]]; then
        info "安装缺失依赖: ${MISSING[*]}"
        ${PKG_UPDATE}
        ${PKG_INSTALL} "${MISSING[@]}"
        ok "依赖安装完成"
    fi
}


# =============================================================================
# STEP 3: 检测 Caddy 配置片段目录
# =============================================================================
detect_caddy_dir() {
    step "检测 Caddy2 配置目录"

    if [[ -d "/etc/caddy/233boy" ]]; then
        CADDY_CONF_DIR="/etc/caddy/233boy"
        ok "检测到目录: /etc/caddy/233boy/"
    elif [[ -d "/etc/caddy/conf.d" ]]; then
        CADDY_CONF_DIR="/etc/caddy/conf.d"
        ok "检测到目录: /etc/caddy/conf.d/"
    else
        warn "未找到 /etc/caddy/233boy 或 /etc/caddy/conf.d"
        echo ""
        echo "  请选择要创建的配置目录:"
        echo "    1) /etc/caddy/233boy"
        echo "    2) /etc/caddy/conf.d"
        echo ""
        read -rp "  请输入选项 [1/2] (默认 2): " DIR_CHOICE
        case "${DIR_CHOICE:-2}" in
            1) CADDY_CONF_DIR="/etc/caddy/233boy" ;;
            *) CADDY_CONF_DIR="/etc/caddy/conf.d"  ;;
        esac
        mkdir -p "${CADDY_CONF_DIR}"
        ok "已创建目录: ${CADDY_CONF_DIR}"

        if [[ -f /etc/caddy/Caddyfile ]]; then
            if ! grep -q "import.*${CADDY_CONF_DIR}" /etc/caddy/Caddyfile 2>/dev/null; then
                warn "请确保 /etc/caddy/Caddyfile 中包含:"
                warn "  import ${CADDY_CONF_DIR}/*.conf"
            fi
        fi
    fi

    info "Caddy 配置目录: ${CADDY_CONF_DIR}"
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
        # 使用 if/fi 而非 [[ ]] && break
        # 原因: [[ condition ]] && break 在 condition 为 false 时
        #       整体 exit code=1，在严格模式下行为异常
        if [[ -n "${PARENT_DOMAIN}" && ! "${PARENT_DOMAIN}" =~ [[:space:]] ]]; then
            break
        fi
        warn "域名不能为空或含空格，请重新输入"
    done
    ok "域名: ${PARENT_DOMAIN}"

    # ── 4.2 Basic Auth 用户名 ──────────────────────────────────────────────
    read -rp "  请输入 Web UI 登录用户名 (默认: admin): " BA_USER
    BA_USER="${BA_USER:-admin}"
    ok "用户名: ${BA_USER}"

    # ── 4.3 Basic Auth 密码（最少 8 位，需二次确认） ─────────────────────────
    echo ""
    local BA_PASS2=""
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

    # ── 4.4 用 Caddy 内置命令生成 bcrypt 哈希 ────────────────────────────────
    info "生成 Basic Auth 密码哈希 (bcrypt)..."
    BA_HASH=$(caddy hash-password --plaintext "${BA_PASS}" 2>/dev/null)
    if [[ -z "${BA_HASH}" ]]; then
        error "caddy hash-password 执行失败，请确认 Caddy2 版本 >= 2.0"
    fi
    ok "密码哈希生成完成"

    # ── 4.5 自动生成 Streaming API Key (UUID) ────────────────────────────────
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
            # CentOS 8 已 EOL，static build 兼容性最佳
            wget -qO /tmp/nd-kickstart.sh https://get.netdata.cloud/kickstart.sh
            bash /tmp/nd-kickstart.sh \
                --stable-channel \
                --disable-telemetry \
                --dont-start-it \
                --static-only 2>&1 | grep -E "(OK|ERROR|WARN|Installing)" || true
            rm -f /tmp/nd-kickstart.sh
            ;;
    esac

    if ! command -v netdata &>/dev/null; then
        error "Netdata 安装失败，请查看上方输出"
    fi
    ok "Netdata 安装完成"
}


# =============================================================================
# STEP 6: 配置 Netdata 为 Parent（接收）模式
# =============================================================================
configure_netdata() {
    step "配置 Netdata Parent 模式"

    if [[ -d /etc/netdata ]]; then
        NETDATA_CONF_DIR="/etc/netdata"
    elif [[ -d /opt/netdata/etc/netdata ]]; then
        NETDATA_CONF_DIR="/opt/netdata/etc/netdata"
    else
        error "找不到 Netdata 配置目录"
    fi
    info "Netdata 配置目录: ${NETDATA_CONF_DIR}"

    cat > "${NETDATA_CONF_DIR}/netdata.conf" <<EOF
# Netdata 主配置 - Parent 接收模式
# 由 setup-netdata-parent.sh 自动生成

[global]
    history   = 604800
    cpu cores = 0

[web]
    # 只监听本地，Caddy 负责反代
    bind to = 127.0.0.1:19999
    allow connections from = 127.0.0.1
    enable gzip compression = yes

[ml]
    enabled = yes

[plugins]
    proc      = yes
    cgroups   = yes
    diskspace = yes
    apps      = yes
    tc        = no
    nfacct    = no
EOF
    ok "netdata.conf 已写入"

    cat > "${NETDATA_CONF_DIR}/stream.conf" <<EOF
# Netdata Streaming 配置 - Parent 接收模式
# 由 setup-netdata-parent.sh 自动生成

# 本节点不向上游推送
[stream]
    enabled = no

# 持有此 API Key 的所有 Child 均可推送，无需逐台配置
[${API_KEY}]
    enabled = yes
    default memory mode = dbengine
    default postpone alarms on connect seconds = 60
    health enabled by default = auto
    allow labels from = *
EOF
    ok "stream.conf 已写入"

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
    error "Netdata 启动超时，请检查: journalctl -u netdata -n 50"
}


# =============================================================================
# STEP 7: 生成 Caddy2 配置文件
# =============================================================================
configure_caddy() {
    step "生成 Caddy2 配置"

    if [[ -f "${CADDY_CONF_FILE}" ]]; then
        local BACKUP="${CADDY_CONF_FILE}.bak.$(date +%Y%m%d%H%M%S)"
        cp "${CADDY_CONF_FILE}" "${BACKUP}"
        warn "已备份旧配置: ${BACKUP}"
    fi

    mkdir -p /var/log/caddy
    chown caddy:caddy /var/log/caddy 2>/dev/null || \
        chown www-data:www-data /var/log/caddy 2>/dev/null || true

    cat > "${CADDY_CONF_FILE}" <<EOF
# Netdata Parent - Caddy2 反代配置
# 域名: ${PARENT_DOMAIN}
# 由 setup-netdata-parent.sh 自动生成于 $(date '+%Y-%m-%d %H:%M:%S')

${PARENT_DOMAIN} {

    # ── 访问日志（JSON，供 Fail2ban 解析） ──────────────────────────────────
    log {
        output file /var/log/caddy/${PARENT_DOMAIN}_access.log {
            roll_size    50mb
            roll_keep    7
            roll_keep_for 720h
        }
        format json
        level  INFO
    }

    # ── 隐藏指纹，添加安全响应头 ────────────────────────────────────────────
    header {
        -Server
        -X-Powered-By
        -Via
        X-Content-Type-Options    "nosniff"
        X-Frame-Options           "DENY"
        X-XSS-Protection          "1; mode=block"
        Referrer-Policy           "no-referrer"
        Permissions-Policy        "geolocation=(), microphone=(), camera=()"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    # ── 只允许 GET / POST / HEAD ─────────────────────────────────────────────
    @bad_method not method GET POST HEAD
    respond @bad_method "Method Not Allowed" 405

    # ── 封锁恶意扫描器 UA ────────────────────────────────────────────────────
    @bad_ua {
        header User-Agent ""
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
        header User-Agent "*nuclei*"
        header User-Agent "*gobuster*"
        header User-Agent "*wfuzz*"
    }
    respond @bad_ua 444

    # ── 封锁漏洞探测路径（直接断连） ────────────────────────────────────────
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
        path /config*
        path *.php
        path *.asp
        path *.aspx
        path *.jsp
        path *.cgi
        path *.sh
    }
    respond @attack_path 444

    # ── Streaming 数据接收（Child 推送，无需 Basic Auth） ────────────────────
    handle /api/v1/stream* {
        reverse_proxy 127.0.0.1:19999 {
            transport http {
                dial_timeout            10s
                response_header_timeout 30s
                keepalive               1m
            }
            header_up X-Forwarded-For {remote_host}
            header_up X-Real-IP {remote_host}
        }
    }

    # ── Web UI（Basic Auth 保护） ────────────────────────────────────────────
    handle /* {
        basicauth {
            # 用户名: ${BA_USER}
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
    ok "Caddy 配置已写入: ${CADDY_CONF_FILE}"

    caddy fmt --overwrite "${CADDY_CONF_FILE}" 2>/dev/null && \
        ok "Caddy 配置格式校验通过" || \
        warn "caddy fmt 返回异常，请手动确认"

    info "重载 Caddy..."
    if systemctl reload caddy 2>/dev/null; then
        ok "Caddy 已热重载"
    elif systemctl restart caddy 2>/dev/null; then
        ok "Caddy 已重启"
    else
        error "Caddy 重载失败: journalctl -u caddy -n 30"
    fi
}


# =============================================================================
# STEP 8: 配置 Fail2ban（仅添加 jail）
# =============================================================================
configure_fail2ban() {
    step "配置 Fail2ban"

    if [[ "${F2B_INSTALLED}" != "true" ]]; then
        warn "Fail2ban 未安装，跳过"
        return
    fi

    cat > /etc/fail2ban/filter.d/caddy-netdata.conf <<EOF
# Fail2ban Filter: caddy-netdata
# 解析 Caddy JSON 日志，匹配 4xx/5xx 来源 IP
# 由 setup-netdata-parent.sh 自动生成

[Definition]
failregex = ^.*"remote_ip":"<HOST>".*"status":4[0-9]{2}.*$
            ^.*"remote_ip":"<HOST>".*"status":5[0-9]{2}.*$
ignoreregex =
datepattern = {ts}
EOF
    ok "filter 已创建"

    cat > /etc/fail2ban/jail.d/caddy-netdata.conf <<EOF
# Fail2ban Jail: caddy-netdata
# 由 setup-netdata-parent.sh 自动生成

[caddy-netdata]
enabled  = true
port     = http,https
filter   = caddy-netdata
logpath  = /var/log/caddy/${PARENT_DOMAIN}_access.log
# 60 秒内 20 次失败 → 封禁 24 小时（-1 为永久）
maxretry = 20
findtime = 60
bantime  = 86400
ignoreip = 127.0.0.1/8 ::1
EOF
    ok "jail 已创建"

    if fail2ban-client reload 2>/dev/null; then
        ok "Fail2ban 重载成功"
        sleep 2
        if fail2ban-client status caddy-netdata &>/dev/null; then
            ok "Jail 'caddy-netdata' 已激活"
        else
            warn "请手动检查: fail2ban-client status caddy-netdata"
        fi
    else
        warn "Fail2ban 重载失败: fail2ban-client reload"
    fi
}


# =============================================================================
# STEP 9: 保存配置记录
# =============================================================================
save_config_record() {
    step "保存配置记录"

    cat > "${RECORD_FILE}" <<EOF
# Netdata Parent 配置记录
# 由 setup-netdata-parent.sh 生成于 $(date '+%Y-%m-%d %H:%M:%S')

PARENT_DOMAIN="${PARENT_DOMAIN}"
API_KEY="${API_KEY}"
BA_USER="${BA_USER}"
BA_HASH="${BA_HASH}"
CADDY_CONF_FILE="${CADDY_CONF_FILE}"
CADDY_CONF_DIR="${CADDY_CONF_DIR}"
NETDATA_CONF_DIR="${NETDATA_CONF_DIR}"
OS_NAME="${OS_NAME}"
EOF
    chmod 600 "${RECORD_FILE}"
    ok "配置记录已保存: ${RECORD_FILE}"
}


# =============================================================================
# STEP 10: 卸载
# =============================================================================
do_uninstall() {
    step "卸载 Netdata Parent 节点"

    if [[ -f "${RECORD_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${RECORD_FILE}"
        info "读取配置记录: ${RECORD_FILE}"
    else
        warn "未找到配置记录，进入手动模式"
        read -rp "  请输入当时配置的 Parent 域名: " PARENT_DOMAIN
        if [[ -d "/etc/caddy/233boy" ]]; then
            CADDY_CONF_DIR="/etc/caddy/233boy"
        else
            CADDY_CONF_DIR="/etc/caddy/conf.d"
        fi
        CADDY_CONF_FILE="${CADDY_CONF_DIR}/${PARENT_DOMAIN}.conf"
        NETDATA_CONF_DIR="/etc/netdata"
    fi

    echo ""
    warn "即将执行以下卸载操作:"
    echo "  1. 停止并禁用 Netdata 服务"
    echo "  2. 卸载 Netdata 软件包及数据"
    echo "  3. 删除 Caddy 配置: ${CADDY_CONF_FILE}"
    echo "  4. 删除 Fail2ban jail 配置"
    echo "  5. 删除日志及配置记录"
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
            if [[ -d /opt/netdata ]]; then rm -rf /opt/netdata && ok "已删除 /opt/netdata"; fi
            ;;
    esac

    info "清理残留文件..."
    for dir in /etc/netdata /var/lib/netdata /var/cache/netdata \
                /var/log/netdata /opt/netdata/etc/netdata; do
        if [[ -d "${dir}" ]]; then rm -rf "${dir}" && info "  已删除: ${dir}"; fi
    done
    ok "残留文件清理完成"

    info "删除 Caddy 配置..."
    if [[ -f "${CADDY_CONF_FILE}" ]]; then
        rm -f "${CADDY_CONF_FILE}"
        ok "已删除: ${CADDY_CONF_FILE}"
        systemctl reload caddy 2>/dev/null && ok "Caddy 已重载" || warn "Caddy 重载失败"
    else
        warn "配置不存在: ${CADDY_CONF_FILE}"
    fi

    info "清理 Fail2ban 配置..."
    rm -f /etc/fail2ban/filter.d/caddy-netdata.conf 2>/dev/null || true
    rm -f /etc/fail2ban/jail.d/caddy-netdata.conf   2>/dev/null || true
    if command -v fail2ban-client &>/dev/null; then
        fail2ban-client reload 2>/dev/null && ok "Fail2ban 已重载" || warn "Fail2ban 重载失败"
    fi

    rm -f "/var/log/caddy/${PARENT_DOMAIN}_access.log"* 2>/dev/null || true
    rm -f "${RECORD_FILE}" 2>/dev/null || true

    echo ""
    ok "卸载完成！Caddy2 已保留。"
}


# =============================================================================
# STEP 11: 显示部署摘要
# =============================================================================
show_summary() {
    local LINE="──────────────────────────────────────────────────────────"
    echo ""
    echo -e "${GREEN}╔${LINE}╗${NC}"
    echo -e "${GREEN}║${NC}   ${BOLD}Netdata Parent 节点部署完成！${NC}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    printf "${GREEN}║${NC}  %-16s : ${CYAN}%s${NC}\n" "访问地址"      "https://${PARENT_DOMAIN}"
    printf "${GREEN}║${NC}  %-16s : ${CYAN}%s${NC}\n" "Web UI 用户名" "${BA_USER}"
    printf "${GREEN}║${NC}  %-16s : ${CYAN}%s${NC}\n" "Web UI 密码"   "${BA_PASS}"
    printf "${GREEN}║${NC}  %-16s : ${CYAN}%s${NC}\n" "API Key"       "${API_KEY}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    printf "${GREEN}║${NC}  %-16s : %s\n" "Caddy 配置" "${CADDY_CONF_FILE}"
    printf "${GREEN}║${NC}  %-16s : %s\n" "配置记录"   "${RECORD_FILE}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}部署 Child 节点时所需参数:${NC}"
    printf "${GREEN}║${NC}    PARENT_HOST = ${CYAN}%s${NC}\n" "${PARENT_DOMAIN}"
    printf "${GREEN}║${NC}    API_KEY     = ${CYAN}%s${NC}\n" "${API_KEY}"
    echo -e "${GREEN}╠${LINE}╣${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}[提示]${NC} 请妥善保存 API Key 和密码"
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
