#!/bin/bash
## 用来快速备份->清空->nano编辑文件

# 检查是否有传入文件名
if [ "$#" -ne 1 ]; then
    echo "Usage: enano.sh filename"
    exit 1
fi

file=$1
backup_file="${file}.bak1"

# 如果文件不存在或文件内容为空，则直接使用 nano 编辑
if [[ ! -f $file ]] || [[ ! -s $file ]]; then
    nano $file
    exit 0
fi

# 查找下一个可用的备份文件名
while [[ -f $backup_file ]]; do
    number=$(echo $backup_file | grep -o -E '[0-9]+$')
    number=$((number + 1))
    backup_file="${file}.bak${number}"
done

# 创建备份
cp $file $backup_file && echo "Backup created: $backup_file"

# 检查备份是否成功
if [[ -f $backup_file ]]; then
    # 清空原文件
    > $file

    # 使用 nano 编辑文件
    nano $file
else
    echo "Backup failed, aborting edit."
    exit 1
fi
