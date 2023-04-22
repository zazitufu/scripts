## cat一些文件里面存在timestamp，将其转换为可读的时间格式
## eg： cat .zsh_history | ./catdate.sh
## 2023年4月23日00点37分

#!/bin/bash

# This script converts timestamp to human readable date format

while read line; do
    ts=`echo $line | grep -o '[0-9]\{10\}'` 
    if [[ ! -z "$ts" ]]; then
        formatted_date=`date -d @$ts +"%Y-%m-%d %H:%M:%S"`
        echo "$line" | sed "s/$ts/$formatted_date/g"
    fi 
done
