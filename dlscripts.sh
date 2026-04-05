#!/bin/bash
### 批量下载 GitHub 脚本 - 全环境兼容终极版
### 2026年4月6日
# --- 配置区 ---
REPO_OWNER="zazitufu"
REPO_NAME="scripts"
BRANCH="master"

# 代理列表（去除了不稳定的镜像）
PROXY_LIST=(
    "direct"
    "https://gh-proxy.com/"
    "https://ghproxy.net/"
)

# 超时与速度限制
CONN_TIMEOUT=5    
LOW_SPEED_LIMIT=10 
LOW_SPEED_TIME=10  

# 智能锁定变量
USE_PROXY_ONLY=false
LOCKED_PROXY_INDEX=0
# --- ------ ---

# 1. 环境检查：检测 sudo 和权限
check_env() {
    # 检查是否为 root
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo &> /dev/null; then
            echo -e "\e[31m错误：当前不是 root 用户且系统中未安装 sudo。\e[0m"
            echo "请先运行 'su -' 切换到 root 用户，或联系管理员安装 sudo。"
            exit 1
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# 2. 自动安装 jq 解析器
install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "未检测到 jq，正在尝试安装..."
        if command -v apt &> /dev/null; then
            $SUDO apt update && $SUDO apt install -y jq
        elif command -v yum &> /dev/null; then
            $SUDO yum install -y jq
        elif command -v pacman &> /dev/null; then
            $SUDO pacman -Sy --noconfirm jq
        else
            echo "错误：无法识别的包管理器，请手动安装 jq 后再运行。"
            exit 1
        fi
    fi
}

check_env
install_jq

echo "正在获取文件列表..."
api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents?ref=${BRANCH}"

get_file_list() {
    local raw_json
    raw_json=$(curl -sfL --connect-timeout $CONN_TIMEOUT "$api_url")
    [ -n "$raw_json" ] && echo "$raw_json" && return 0
    raw_json=$(curl -sfL --connect-timeout $CONN_TIMEOUT "${PROXY_LIST[1]}$api_url")
    echo "$raw_json"
}

files_json=$(get_file_list)

if [ -z "$files_json" ] || [[ "$files_json" == *"rate limit exceeded"* ]]; then
    echo "错误：无法获取 API 数据（网络超时或触发频率限制）。"
    exit 1
fi

# 使用 jq 精准提取文件
script_files=$(echo "$files_json" | jq -r '.[] | select(.type == "file") | .name')

if [ -z "$script_files" ] || [ "$script_files" == "null" ]; then
    echo "未发现有效文件。请检查仓库路径或分支名称。"
    exit 0
fi

# 下载逻辑：支持节点锁定
download_logic() {
    local fname=$1
    local raw_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/${fname}"
    
    local start_index=0
    [ "$USE_PROXY_ONLY" = true ] && start_index=$LOCKED_PROXY_INDEX

    for ((i=start_index; i<${#PROXY_LIST[@]}; i++)); do
        local proxy="${PROXY_LIST[$i]}"
        local target_url
        local node_name
        
        if [ "$proxy" == "direct" ]; then
            target_url="$raw_url"
            node_name="直连"
        else
            target_url="${proxy}${raw_url}"
            node_name=$(echo "$proxy" | sed -E 's|https?://([^/]+)/?|\1|')
        fi

        if curl -sSLf \
            --connect-timeout $CONN_TIMEOUT \
            --speed-limit $LOW_SPEED_LIMIT \
            --speed-time $LOW_SPEED_TIME \
            -o "$fname" "$target_url" 2>tmp_curl_err; then
            
            echo -n " [$node_name]"
            
            if [ "$proxy" != "direct" ] && [ "$USE_PROXY_ONLY" = false ]; then
                USE_PROXY_ONLY=true
                LOCKED_PROXY_INDEX=$i
                echo -n " (已锁定加速节点)"
            fi
            return 0
        else
            local err_msg=$(cat tmp_curl_err | tr -d '\n' | cut -c1-30)
            echo -n " [$node_name:失败]"
            [ "$USE_PROXY_ONLY" = false ] && [ -n "$err_msg" ] && echo -n "($err_msg)"
        fi
    done
    return 1
}

echo "开始同步文件..."
echo "---------------------------------------"

for filename in $script_files; do
    [ "$filename" == "dlscripts.sh" ] && continue
    
    ((total_files++))
    printf "[%02d] %-22s" "$total_files" "$filename"

    if download_logic "$filename"; then
        echo -e " \e[32m[成功]\e[0m"
        # 仅对脚本赋权
        [[ "$filename" == *.sh ]] && chmod +x "$filename"
        ((downloaded_files++))
    else
        echo -e " \e[31m[全部跳过]\e[0m"
    fi
done

rm -f tmp_curl_err
echo "---------------------------------------"
echo "处理完成。发现文件：$total_files，同步成功：$downloaded_files"
