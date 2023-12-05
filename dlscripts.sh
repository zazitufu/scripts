#!/bin/bash
### 批量下载自制脚本文件

scriptfile=(
    plmtr.sh
    plping.sh
    iplog.sh
    chomz.sh
    acme320.sh
    prettyping
    publish.sh
    traffic.sh
    testip.sh
    dlscripts.sh
    lastbcount.sh
    installf2b.sh
    bns.sh
    extjson.sh
    enano.sh
    set_alias.sh
)

base_url="https://raw.githubusercontent.com/zazitufu/scripts/master"
total_files=0
downloaded_files=0

for index in "${!scriptfile[@]}"; do
    filename=${scriptfile[$index]}
    printf "%d. 正在检查 %s ..." "$((index + 1))" "$filename"

    local_file="$filename"
    remote_file="${base_url}/${filename}"

    # 检查本地文件是否存在并是否相同
    if [ -f "$local_file" ] && curl -sf "$remote_file" | diff - "$local_file" >/dev/null; then
        echo " 本地文件已是最新版本，跳过下载。"
    else
        attempt=0
        max_attempts=3
        success=false

        while [ $attempt -lt $max_attempts ]; do
            ((attempt++))
            if curl -sfO "$remote_file"; then
                echo -n " 下载成功。"
                chmod +x "$filename"
                success=true
                ((downloaded_files++))
                break
            else
                echo -n " 下载失败，尝试重试... "
            fi
        done

        if [ "$success" = false ]; then
            echo "下载失败超过3次，跳过。"
        else
            echo ""
        fi
    fi

    ((total_files++))
done

echo "处理完成。总文件数：$total_files，已下载：$downloaded_files"
