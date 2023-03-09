## 用来给.bashrc 或者其他的添加alias用。会先备份$2文件为 backup.$2
# 用法： ./setalias.sh 源文件 目标文件
# 源文件有 目标文件有，则在目标文件对应行开头加注释符号
# 源文件有 目标文件无，复制过去。
# 源文件无 目标文件有，保留行。
# 2023年3月9日

#!/bin/bash
set_alias() {
    alias_from="$1"
    alias_to="$2"
    backup="$alias_to"

    # 检查 $alias_from 文件是否存在
    if [[ ! -f "$alias_from" ]]; then
        echo "Error: $alias_from does not exist."
        return 1
    fi

    # 检查 $alias_to 文件是否存在或有写权限
    if [[ ! -f "$alias_to" && ! -w "$(dirname "$alias_to")" ]]; then
        echo "Error: $alias_to does not exist and $(dirname "$alias_to") is not writable."
        return 1
    fi

    if [[ -f "$alias_to" ]]; then
        i=1
        while [[ -f "backup$i.$alias_to" ]]; do
            ((i++))
        done
        backup="backup$i.$alias_to"
    fi

    cp "$alias_to" "$backup" 2>/dev/null

    while IFS= read -r line; do
        alias_name=$(echo "$line" | sed 's/^alias \([^=]*\)=.*$/\1/')
        if [[ -n "$alias_name" ]]; then
            if grep -q "^alias $alias_name=" "$alias_to"; then
                sed -i "s/^alias $alias_name=/#alias $alias_name=/" "$alias_to"
            fi
            if ! grep -q "^alias $alias_name=" "$alias_to"; then
                echo "$line" >> "$alias_to"
            fi
        fi
    done < "$alias_from"

    while IFS= read -r line; do
        alias_name=$(echo "$line" | sed 's/^alias \([^=]*\)=.*$/\1/')
        if [[ -n "$alias_name" && ! $(grep -q "^alias $alias_name=" "$alias_from") ]]; then
            echo "$line" >> "$alias_from"
        fi
    done < "$alias_to"
}

set_alias "$1" "$2"
