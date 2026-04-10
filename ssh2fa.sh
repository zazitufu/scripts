#!/bin/bash

# =================================================================
# SSH 2FA 管理脚本 (增强时间同步版)
# 兼容: Debian 11, 12, 13, Ubuntu, Arch Linux
# =================================================================

set -e

# 配置路径
PAM_SSHD="/etc/pam.d/sshd"
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_SUFFIX=".2fa_orig_bak"

[[ "$EUID" -ne 0 ]] && echo "错误: 请使用 sudo 运行" && exit 1

. /etc/os-release
OS=$ID

# --- 1. 时间同步检查与安装模块 ---
ensure_time_sync() {
    echo "Step [1/4]: 正在保障时间同步状态..."

    # 安装同步服务
    case $OS in
        debian|ubuntu)
            apt-get update -qq
            # 安装 systemd-timesyncd (Debian 12+ 必备)
            apt-get install -y systemd-timesyncd -qq
            SSH_SVC="ssh"
            ;;
        arch)
            # Arch 通常自带 systemd-timesyncd，如果没有则安装
            pacman -Syu --noconfirm --needed systemd -q
            SSH_SVC="sshd"
            ;;
    esac

    # 启动并强制开启 NTP
    systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
    timedatectl set-ntp true || true

    # 循环检查同步状态 (最多等待 10 秒)
    echo -n "正在等待系统时间同步..."
    for i in {1..10}; do
        if timedatectl status | grep -q "System clock synchronized: yes"; then
            echo -e "\n✅ 时间已同步成功。"
            return 0
        fi
        echo -n "."
        sleep 1
    done

    echo -e "\n⚠️ 警告: 时间同步未在 10 秒内完成。如果后续 2FA 验证失败，请检查 UDP 123 端口。"
}

# --- 2. 依赖安装模块 ---
install_2fa_pkg() {
    echo "Step [2/4]: 正在安装 Google Authenticator 模块..."
    case $OS in
        debian|ubuntu)
            apt-get install -y libpam-google-authenticator -qq
            ;;
        arch)
            pacman -S --noconfirm --needed google-authenticator -q
            ;;
    esac
}

# --- 3. 配置模块 ---
apply_config() {
    echo "Step [3/4]: 正在配置 SSH 和 PAM..."
    
    # 备份
    [[ ! -f "${PAM_SSHD}${BACKUP_SUFFIX}" ]] && cp "$PAM_SSHD" "${PAM_SSHD}${BACKUP_SUFFIX}"
    [[ ! -f "${SSHD_CONFIG}${BACKUP_SUFFIX}" ]] && cp "$SSHD_CONFIG" "${SSHD_CONFIG}${BACKUP_SUFFIX}"

    # 修改 PAM
    if ! grep -q "pam_google_authenticator.so" "$PAM_SSHD"; then
        if [[ "$OS" == "arch" ]]; then
            sed -i '/auth.*include.*system-remote-login/a auth required pam_google_authenticator.so nullok' "$PAM_SSHD"
        else
            sed -i '/@include common-auth/a auth required pam_google_authenticator.so nullok' "$PAM_SSHD"
        fi
    fi

    # 修改 SSHD
    sed -i 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^#*UsePAM.*/UsePAM yes/' "$SSHD_CONFIG"
    
    # 核心：配置认证顺序 (公钥) 或 (密码+2FA)
    if ! grep -q "AuthenticationMethods" "$SSHD_CONFIG"; then
        echo "AuthenticationMethods publickey keyboard-interactive:pam" >> "$SSHD_CONFIG"
    else
        sed -i 's/^AuthenticationMethods.*/AuthenticationMethods publickey keyboard-interactive:pam/' "$SSHD_CONFIG"
    fi
}

# --- 4. 运行逻辑 ---
run_install() {
    ensure_time_sync
    install_2fa_pkg
    apply_config
    
    echo "Step [4/4]: 重启 SSH 服务..."
    systemctl restart "$SSH_SVC"
    
    echo "-------------------------------------------------------"
    echo "✅ 设置完成！"
    echo "配置文件路径: $SSHD_CONFIG"
    echo "PAM 路径: $PAM_SSHD"
    echo "请立即执行: google-authenticator"
    echo "-------------------------------------------------------"
}

run_uninstall() {
    echo "正在回滚配置..."
    [[ -f "${PAM_SSHD}${BACKUP_SUFFIX}" ]] && mv "${PAM_SSHD}${BACKUP_SUFFIX}" "$PAM_SSHD"
    [[ -f "${SSHD_CONFIG}${BACKUP_SUFFIX}" ]] && mv "${SSHD_CONFIG}${BACKUP_SUFFIX}" "$SSHD_CONFIG"
    
    case $OS in
        debian|ubuntu) systemctl restart ssh ;;
        arch) systemctl restart sshd ;;
    esac
    echo "✅ 已成功卸载。"
}

# 入口
case "$1" in
    install) run_install ;;
    uninstall) run_uninstall ;;
    *) echo "Usage: $0 {install|uninstall}"; exit 1 ;;
esac
