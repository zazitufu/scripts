#!/bin/bash
# VPS 环境自动化配置工具
# v 0.3 - 增加本机信息显示
# https://github.com/zazitufu/scripts/new/master
# 2026 年 3 月 22 日 - 增加系统信息检测功能

# 定义文件名
CONFIG_FILE="setvps.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 1. 检查并生成示例配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    echo "----------------------------------------------------"
    echo -e "${RED}错误：${NC}未找到配置文件 $CONFIG_FILE"
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
    echo -e "${GREEN}成功：${NC}示例文件已创建在当前目录。"
    echo -e "${YELLOW}提示：${NC}请先使用 'nano $CONFIG_FILE' 或 'vi $CONFIG_FILE' 编辑配置。"
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

# 4. 执行函数
execute_task() {
    local idx=$1
    # 获取任务名称
    local name=$(jq -r ".items[$idx].name" "$CONFIG_FILE")
    
    echo -e "\n${GREEN}[开始执行]${NC}: $name"

    # 1. 关键点：获取 command 的类型 (string 或 array)
    local cmd_type=$(jq -r ".items[$idx].command | type" "$CONFIG_FILE")

    if [ "$cmd_type" == "array" ]; then
        # 2. 如果是数组，使用 jq 的 -c 参数逐行读取纯文本命令
        readarray -t cmd_list < <(jq -r ".items[$idx].command[]" "$CONFIG_FILE")
        
        local total=${#cmd_list[@]}
        local count=1
        for cmd in "${cmd_list[@]}"; do
            echo -e "   ${BLUE}(步骤 $count/$total)${NC} 执行：$cmd"
            eval "$cmd"
            
            # 检查每一步的执行结果
            if [ $? -ne 0 ]; then
                echo -e "${RED}[错误]${NC} 步骤 $count 执行失败。"
                return 1
            fi
            ((count++))
        done
    else
        # 3. 如果是普通字符串，直接执行
        local cmd=$(jq -r ".items[$idx].command" "$CONFIG_FILE")
        echo "执行命令：$cmd"
        eval "$cmd"
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[成功]${NC}: $name 处理完毕。"
    else
        echo -e "${RED}[失败]${NC}: $name 在执行过程中出错。"
    fi
}

# 5. 更换系统软件源子菜单函数
change_repo_source() {
    while true; do
        clear
        echo "===================================================="
        echo "        更换系统软件源"
        echo "===================================================="
        echo ""
        echo "  1) 更换为 Debian 官方源"
        echo "  2) 更换为阿里云源"
        echo "  3) 返回主菜单"
        echo ""
        echo "===================================================="
        
        read -p "请输入选项数字 [1-3]: " source_choice
        
        case $source_choice in
            1)
                echo -e "${YELLOW}正在更换为 Debian 官方源...${NC}"
                
                # 检测系统版本
                if [ -f /etc/debian_version ]; then
                    DEBIAN_VERSION=$(cat /etc/debian_version)
                    CODENAME=""
                    
                    # 根据版本确定代号
                    if echo "$DEBIAN_VERSION" | grep -q "12"; then
                        CODENAME="bookworm"
                    elif echo "$DEBIAN_VERSION" | grep -q "11"; then
                        CODENAME="bullseye"
                    elif echo "$DEBIAN_VERSION" | grep -q "10"; then
                        CODENAME="buster"
                    else
                        CODENAME="stable"
                    fi
                    
                    # 备份原有源
                    cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)
                    
                    # 写入官方源
                    cat > /etc/apt/sources.list <<EOFSRC
deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-backports main contrib non-free non-free-firmware
EOFSRC
                    
                    echo -e "${GREEN}✓ Debian 官方源已配置${NC}"
                    echo "  已备份原配置文件"
                    echo "  正在更新软件包列表..."
                    apt update
                    
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ 软件源更新成功！${NC}"
                    else
                        echo -e "${RED}✗ 更新失败，请检查网络连接${NC}"
                    fi
                else
                    echo -e "${RED}✗ 非 Debian 系统，无法配置 Debian 源${NC}"
                fi
                
                read -p "按回车键继续..."
                ;;
                
            2)
                echo -e "${YELLOW}正在更换为阿里云源...${NC}"
                
                # 检测系统类型
                if [ -f /etc/debian_version ]; then
                    # Debian/Ubuntu 系统
                    DEBIAN_VERSION=$(cat /etc/debian_version)
                    CODENAME=""
                    
                    # 根据版本确定代号
                    if echo "$DEBIAN_VERSION" | grep -q "12"; then
                        CODENAME="bookworm"
                    elif echo "$DEBIAN_VERSION" | grep -q "11"; then
                        CODENAME="bullseye"
                    elif echo "$DEBIAN_VERSION" | grep -q "10"; then
                        CODENAME="buster"
                    else
                        CODENAME="stable"
                    fi
                    
                    # 备份原有源
                    cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)
                    
                    # 写入阿里云源
                    cat > /etc/apt/sources.list <<EOFSRC
deb http://mirrors.aliyun.com/debian $CODENAME main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian $CODENAME-updates main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian $CODENAME-backports main contrib non-free non-free-firmware
EOFSRC
                    
                    echo -e "${GREEN}✓ 阿里云源已配置${NC}"
                    echo "  已备份原配置文件"
                    echo "  正在更新软件包列表..."
                    apt update
                    
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ 软件源更新成功！${NC}"
                    else
                        echo -e "${RED}✗ 更新失败，请检查网络连接${NC}"
                    fi
                    
                elif [ -f /etc/redhat-release ]; then
                    # CentOS/RHEL 系统
                    echo "  检测到 CentOS/RHEL 系统..."
                    
                    # 备份原有配置
                    cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null
                    
                    # 下载阿里云镜像配置
                    if command -v curl &> /dev/null; then
                        curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
                        echo -e "${GREEN}✓ 阿里云 YUM 源已配置${NC}"
                        yum makecache
                    else
                        echo -e "${RED}✗ 未找到 curl 命令，无法下载配置文件${NC}"
                    fi
                else
                    echo -e "${RED}✗ 未识别的系统类型${NC}"
                fi
                
                read -p "按回车键继续..."
                ;;
                
            3)
                echo "返回主菜单..."
                return 0
                ;;
                
            *)
                echo -e "${RED}无效输入，请重新选择${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 6. 显示本机信息函数
show_system_info() {
    clear
    echo "===================================================="
    echo -e "        ${BOLD}本机系统信息${NC}"
    echo "===================================================="
    echo ""
    
    # 1. 系统版本
    echo -e "${CYAN}【系统版本】${NC}"
    if [ -f /etc/os-release ]; then
        PRETTY_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
        echo "  系统名称：$PRETTY_NAME"
    fi
    
    if [ -f /etc/debian_version ]; then
        DEBIAN_VER=$(cat /etc/debian_version)
        echo "  Debian 版本：$DEBIAN_VER"
    fi
    
    KERNEL_VER=$(uname -r)
    echo "  内核版本：$KERNEL_VER"
    echo ""
    
    # 2. IP 地址
    echo -e "${CYAN}【IP 地址】${NC}"
    
    # IPv4
    IPV4=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 icanhazip.com 2>/dev/null || echo "获取失败")
    echo "  IPv4 地址：$IPV4"
    
    # IPv6
    IPV6=$(curl -s6 ifconfig.me 2>/dev/null || curl -s6 icanhazip.com 2>/dev/null || echo "无 IPv6")
    echo "  IPv6 地址：$IPV6"
    echo ""
    
    # 3. 时区
    echo -e "${CYAN}【时区信息】${NC}"
    TIMEZONE=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}')
    if [ -z "$TIMEZONE" ]; then
        TIMEZONE=$(cat /etc/timezone 2>/dev/null || echo "未知")
    fi
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')
    echo "  时区：$TIMEZONE"
    echo "  当前时间：$CURRENT_TIME"
    echo ""
    
    # 4. CPU 信息
    echo -e "${CYAN}【CPU 信息】${NC}"
    CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d':' -f2 | xargs)
    if [ -z "$CPU_MODEL" ]; then
        CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)
    fi
    CPU_CORES=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo)
    CPU_PHYSICAL=$(lscpu 2>/dev/null | grep "Socket(s)" | awk '{print $2}' || echo "1")
    
    if [ -n "$CPU_MODEL" ]; then
        echo "  CPU 型号：$CPU_MODEL"
    else
        echo "  CPU 型号：未知"
    fi
    echo "  CPU 核心数：$CPU_CORES 核"
    echo "  CPU 物理插槽：$CPU_PHYSICAL 个"
    echo ""
    
    # 5. 内存信息
    echo -e "${CYAN}【内存信息】${NC}"
    MEM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
    MEM_USED=$(free -h | grep Mem | awk '{print $3}')
    MEM_FREE=$(free -h | grep Mem | awk '{print $4}')
    MEM_AVAILABLE=$(free -h | grep Mem | awk '{print $7}')
    
    echo "  物理内存总量：$MEM_TOTAL"
    echo "  已使用：$MEM_USED"
    echo "  空闲：$MEM_FREE"
    echo "  可用：$MEM_AVAILABLE"
    echo ""
    
    # 虚拟内存（Swap）
    SWAP_TOTAL=$(free -h | grep Swap | awk '{print $2}')
    SWAP_USED=$(free -h | grep Swap | awk '{print $3}')
    SWAP_FREE=$(free -h | grep Swap | awk '{print $4}')
    
    echo "  虚拟内存总量：$SWAP_TOTAL"
    echo "  已使用：$SWAP_USED"
    echo "  空闲：$SWAP_FREE"
    echo ""
    
    # 6. 硬盘信息
    echo -e "${CYAN}【硬盘信息】${NC}"
    
    # 获取根分区所在磁盘
    ROOT_DISK=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/mapper\///')
    
    # 硬盘类型检测（SSD/HDD）
    DISK_TYPE="未知"
    if [ -b "$ROOT_DISK" ]; then
        DISK_NAME=$(basename "$ROOT_DISK")
        if [ -f /sys/block/$DISK_NAME/queue/rotational ]; then
            ROTATIONAL=$(cat /sys/block/$DISK_NAME/queue/rotational)
            if [ "$ROTATIONAL" -eq 0 ]; then
                DISK_TYPE="SSD (固态硬盘)"
            else
                DISK_TYPE="HDD (机械硬盘)"
            fi
        fi
    fi
    
    # 硬盘容量
    DISK_TOTAL=$(df -h / | tail -1 | awk '{print $2}')
    DISK_USED=$(df -h / | tail -1 | awk '{print $3}')
    DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
    DISK_USE_PERCENT=$(df -h / | tail -1 | awk '{print $5}')
    
    echo "  硬盘类型：$DISK_TYPE"
    echo "  硬盘总容量：$DISK_TOTAL"
    echo "  已使用：$DISK_USED ($DISK_USE_PERCENT)"
    echo "  可用空间：$DISK_AVAIL"
    echo ""
    
    # 7. 运行时间
    echo -e "${CYAN}【运行时间】${NC}"
    UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
    echo "  系统运行时间：$UPTIME"
    echo ""
    
    echo "===================================================="
    echo -e "${YELLOW}提示：按回车键返回主菜单${NC}"
    read -p ""
}

# 7. 显示主菜单函数
show_main_menu() {
    clear
    echo "===================================================="
    echo "    $TITLE"
    echo "===================================================="
    echo ""
    
    # 显示选项
    echo "  1) 【一键安装所有项目】"
    for i in $(seq 0 $((ITEM_COUNT - 1))); do
        name=$(jq -r ".items[$i].name" "$CONFIG_FILE")
        desc=$(jq -r ".items[$i].desc" "$CONFIG_FILE")
        echo "  $((i + 2))) $name ($desc)"
    done
    echo "  $((ITEM_COUNT + 2))) 更换系统软件源"
    echo "  $((ITEM_COUNT + 3))) 显示本机信息"
    echo "  $((ITEM_COUNT + 4))) 退出脚本"
    echo ""
    echo "===================================================="
}

# 8. 主循环
while true; do
    show_main_menu
    
    read -p "请输入选项数字 [1-$((ITEM_COUNT + 4))]: " choice
    
    case $choice in
        1)
            echo "开始执行全量安装任务..."
            for i in $(seq 0 $((ITEM_COUNT - 1))); do
                execute_task $i
            done
            echo "--- 所有任务已处理完毕 ---"
            read -p "按回车键继续..."
            ;;
        $((ITEM_COUNT + 2)))
            change_repo_source
            ;;
        $((ITEM_COUNT + 3)))
            show_system_info
            ;;
        $((ITEM_COUNT + 4)))
            echo "已退出，再见！"
            break
            ;;
        *)
            choice_idx=$((choice - 2))
            if [ "$choice_idx" -ge 0 ] && [ "$choice_idx" -lt "$ITEM_COUNT" ]; then
                execute_task $choice_idx
                read -p "按回车键继续..."
            else
                echo -e "${RED}无效输入，请重新选择${NC}"
                read -p "按回车键继续..."
            fi
            ;;
    esac
done
