#!/bin/bash
#VPS 环境自动化配置工具
#v 0.1
#https://github.com/zazitufu/scripts/new/master
#2026年2月6日，00点26分
# 定义文件名
CONFIG_FILE="setvps.conf"

# 1. 检查并生成示例配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    echo "----------------------------------------------------"
    echo "错误: 未找到配置文件 $CONFIG_FILE"
    echo "正在为你生成示例配置文件..."
    
    # 生成 JSON 内容
    cat <<EOF > "$CONFIG_FILE"
{
  "menu_title": "VPS 环境自动化配置工具",
  "items": [
    {
      "name": "更新系统软件源",
      "command": "sudo apt update && sudo apt upgrade -y",
      "desc": "适用于 Debian/Ubuntu，更新基础包到最新版本"
    },
    {
      "name": "安装 Docker",
      "command": "curl -fsSL https://get.docker.com | sh",
      "desc": "安装 Docker Engine 官方最新版"
    },
    {
      "name": "Arch 系统清理",
      "command": "sudo pacman -Sc --noconfirm",
      "desc": "适用于 ArchLinux，清理包管理器缓存"
    },
    {
      "name": "自定义配置示例",
      "command": "echo 'Hello World'",
      "desc": "这是一个示例，你可以修改为任何 Shell 命令"
    }
  ]
}
EOF
    echo "----------------------------------------------------"
    echo "成功: 示例文件已创建在当前目录。"
    echo "提示: 请先使用 'nano $CONFIG_FILE' 或 'vi $CONFIG_FILE' 编辑配置。"
    echo "      根据你的 VPS 系统修改对应的安装命令。"
    echo "----------------------------------------------------"
    exit 1
fi

# 2. 检查并安装 jq (解析 JSON 必备)
if ! command -v jq &> /dev/null; then
    echo "正在检查系统并安装依赖 jq..."
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y jq
    elif command -v pacman &> /dev/null; then
        sudo pacman -Sy --noconfirm jq
    else
        echo "未能识别包管理器，请手动安装 jq 后再运行此脚本。"
        exit 1
    fi
fi

# 3. 读取配置
TITLE=$(jq -r '.menu_title' "$CONFIG_FILE")
ITEM_COUNT=$(jq '.items | length' "$CONFIG_FILE")

# 清屏增加美感
clear
echo "===================================================="
echo "    $TITLE"
echo "===================================================="

# 4. 构建菜单选项
# 第一项为全量安装
options=("【一键安装所有项目】")
for i in $(seq 0 $((ITEM_COUNT - 1))); do
    name=$(jq -r ".items[$i].name" "$CONFIG_FILE")
    desc=$(jq -r ".items[$i].desc" "$CONFIG_FILE")
    options+=("$name ($desc)")
done
options+=("退出脚本")

# 5. 执行函数
execute_task() {
    local idx=$1
    # 获取任务名称
    local name=$(jq -r ".items[$idx].name" "$CONFIG_FILE")
    
    echo -e "\n\033[32m[开始执行]\033[0m: $name"

    # 1. 关键点：获取 command 的类型 (string 或 array)
    local cmd_type=$(jq -r ".items[$idx].command | type" "$CONFIG_FILE")

    if [ "$cmd_type" == "array" ]; then
        # 2. 如果是数组，使用 jq 的 -c 参数逐行读取纯文本命令
        # 我们通过 mapfile 或 readarray 将其读入 Bash 数组
        readarray -t cmd_list < <(jq -r ".items[$idx].command[]" "$CONFIG_FILE")
        
        local total=${#cmd_list[@]}
        local count=1
        for cmd in "${cmd_list[@]}"; do
            echo -e "   \033[90m(步骤 $count/$total)\033[0m 执行: $cmd"
            eval "$cmd"
            
            # 检查每一步的执行结果
            if [ $? -ne 0 ]; then
                echo -e "\033[31m[错误]\033[0m 步骤 $count 执行失败。"
                return 1
            fi
            ((count++))
        done
    else
        # 3. 如果是普通字符串，直接执行
        local cmd=$(jq -r ".items[$idx].command" "$CONFIG_FILE")
        echo "执行命令: $cmd"
        eval "$cmd"
    fi

    if [ $? -eq 0 ]; then
        echo -e "\033[32m[成功]\033[0m: $name 处理完毕。"
    else
        echo -e "\033[31m[失败]\033[0m: $name 在执行过程中出错。"
    fi
}

# 6. 显示交互菜单
PS3="请输入选项数字 [1-$((${#options[@]}))]: "
select opt in "${options[@]}"; do
    case $REPLY in
        1)
            echo "开始执行全量安装任务..."
            for i in $(seq 0 $((ITEM_COUNT - 1))); do
                execute_task $i
            done
            echo "--- 所有任务已处理完毕 ---"
            ;;
        $((${#options[@]})))
            echo "已退出，再见！"
            break
            ;;
        *)
            choice_idx=$((REPLY - 2))
            if [ "$choice_idx" -ge 0 ] && [ "$choice_idx" -lt "$ITEM_COUNT" ]; then
                execute_task $choice_idx
            else
                echo "无效输入，请重新选择。"
            fi
            ;;
    esac
    echo -e "\n请继续选择或输入最后一位数字退出。"
done
