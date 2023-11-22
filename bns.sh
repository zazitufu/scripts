#!/bin/bash
# 2023年11月23日，v 0.0.2
# Backup and restore 此脚本用来快速打包备份准备重装系统后需要复用的文件。
# 不展开到绝对路径，而是当前路径下： tar -xzvf filename --strip-components=1

# 需要备份的文件列表（绝对路径或通配符）
files_to_backup=(
    "/etc/resolv.conf"
    "/etc/network/interfaces"
    "/etc/v2ray/config.json"
    "/etc/v2ray/conf/*"
    "/etc/caddy/Caddyfile"
    "/etc/caddy/233boy/*"
    "/etc/ssh/sshd_config"
    "/etc/hostname"
    "/root/.ssh/*"
)

# 函数：备份文件
backup_files() {
    echo "输入要创建的备份文件的名称（默认在当前路径）:"
    read backup_filename

    # 动态展开通配符并创建文件列表
    expanded_files=()
    for file in "${files_to_backup[@]}"; do
        for expanded in $file; do
            if [ -e "$expanded" ]; then
                expanded_files+=("$expanded")
            fi
        done
    done

    # 创建备份
    if [ ${#expanded_files[@]} -eq 0 ]; then
        echo "没有找到要备份的文件。"
    else
        tar -czvf "$backup_filename" "${expanded_files[@]}"
        echo "备份完成，文件名: $backup_filename"
    fi
}

# 函数：恢复文件
restore_files() {
    echo "输入要恢复的备份文件的名称（默认在当前路径）:"
    read backup_filename

    # 检查文件是否存在
    if [ ! -f "$backup_filename" ]; then
        echo "备份文件不存在: $backup_filename"
        return
    fi

    echo "选择恢复方式:"
    echo "1) 按原路径恢复"
    echo "2) 恢复到当前路径下"
    read -p "输入选择 (1或2): " restore_choice

    case $restore_choice in
        1)
            # 按原路径恢复
            tar -xzvf "$backup_filename" -C /
            ;;
        2)
            # 恢复到当前路径下
            tar -xzvf "$backup_filename" --strip-components=1
            ;;
        *)
            echo "无效的选择。"
            return
            ;;
    esac

    echo "恢复完成。已恢复的文件:"
    tar -tf "$backup_filename"
}

# 主菜单
echo "选择一个操作:"
echo "1) 备份文件"
echo "2) 恢复文件"
read -p "输入选择 (1或2): " choice

case $choice in
    1)
        backup_files
        ;;
    2)
        restore_files
        ;;
    *)
        echo "无效的选择。"
        ;;
esac
