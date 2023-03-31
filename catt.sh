### 用来查找文件内存在的字符串，并显示上下行的内容，默认上下5行
##  ./catt.sh 文件名 字符串 上下行数（不输入则默认5行）
## 2023年3月31日15:46:40
#!/bin/bash

# 检查参数数量
if [ $# -lt 2 ]; then
    echo "Usage: catt.sh <file> <string> [<context>]"
    exit 1
fi

# 获取参数
file="$1"
string="$2"
context=${3:-5}

# 设置 ANSI 转义序列
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'


# 查找匹配行号
lines=($(grep -n "$string" "$file" | awk -F: '{print $1}'))

# 如果没有匹配行，输出错误信息
if [ ${#lines[@]} -eq 0 ]; then
    echo "String not found in file."
    exit 1
fi

# 遍历匹配行
for line in "${lines[@]}"; do
    # 输出上下文
    start=$(expr $line - $context)
    end=$(expr $line + $context)
    if [ $start -lt 1 ]; then
        start=1
    fi
    echo -e "${YELLOW}上${context}行：${NC}"
    tail -n +$start "$file" | head -n $context | sed "s/$string/${RED}$string${NC}/g"
    echo -e "${YELLOW}查找结果：${NC}"
#    sed -n "${line}p" "$file" | sed "s/$string/${RED}$string${NC}/g"
echo -e "${RED}$(sed -n "${line}p" "$file" )${NC}"
    echo -e "${YELLOW}下${context}行：${NC}"
    tail -n +$(expr $line + 1) "$file" | head -n $context | sed "s/$string/${RED}$string${NC}/g"
done
