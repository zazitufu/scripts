#!/bin/bash
# 用来提取json文件内不同数组里的不同元素
# 默认提取outbounds里的第一个元素，-n 为提取其它数组名称， -e 数值0，则提取数组内所有元素，数值1，则提取数组内第一个元素，以此类推。
# https://github.com/zazitufu/scripts/blob/master/extjson.sh
# 版本：0.0.3
# 时间：2023年12月4日

##
version=0.0.3
btime=2023-12-04

# 初始化默认值
ELEMENT_INDEX=0
ARRAY_NAME="outbounds"
EXTRACT_ALL=false
JSON_FILE=""

# 解析命令行选项和参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -n)
      ARRAY_NAME="$2"
      shift 2
      ;;
    -e)
      ELEMENT_INDEX="$2"
      if [ "$ELEMENT_INDEX" -eq 0 ]; then
        EXTRACT_ALL=true
      else
        ELEMENT_INDEX=$(($ELEMENT_INDEX - 1))
      fi
      shift 2
      ;;
    -*)
      echo "Invalid option: $1" >&2
      exit 1
      ;;
    *)
      JSON_FILE="$1"
      shift
      ;;
  esac
done

# 检查是否提供了 JSON 文件名
if [ -z "$JSON_FILE" ]; then
    echo
    echo "Version: $version   Built: $btime"
    echo
    echo "Usage: extjson.sh [-n array-name] [-e element-index] <json-file>"
    echo -e 'eg: extjson.sh jsonfile                   # extract the 1st element in array "outbounds"'
    echo -e 'eg: extjson.sh jsonfile -e 1              # extract the 1st element in array "outbounds"'
    echo -e 'eg: extjson.sh jsonfile -n inbounds -e 0  # extract all element in array "inbounds"'
    echo
    exit 1
fi

# 定义输出文件的名称，格式为 "ext.输入文件名"
OUTPUT_FILE="ext.$JSON_FILE"

# 使用 jq 工具提取指定数组的元素并构造新的 JSON
# 确保已经安装了 jq：sudo apt-get install jq
if [ "$EXTRACT_ALL" = true ]; then
  jq "{${ARRAY_NAME}: .${ARRAY_NAME}}" "$JSON_FILE" > "$OUTPUT_FILE"
else
  jq "{${ARRAY_NAME}: [.${ARRAY_NAME}[$ELEMENT_INDEX]]}" "$JSON_FILE" > "$OUTPUT_FILE"
fi

# 打印新 JSON 文件的内容
echo "Extracted JSON saved to $OUTPUT_FILE"
