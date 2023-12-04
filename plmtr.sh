#!/bin/bash
# 版本 0.3.1     2023年12月4日15:01:57
# 主要update：批量处理多文件，适配通配符
# nali使用的版本：https://github.com/zu1k/nali。下载后应该首先使用nali update进行ip库下载。
# 注意事项：nali 无论用什么版本，命令行应该alias为nali
# eg: ./plmtr ipfile -c 5 -t tag1
# eg: ./plmtr ip* -c 5
# eg: ./plmtr ip*
##
version=0.3.1
btime=2023-12-04
# 记录开始时间
start_time=`date +%s`
sleep 1
# 脚本开始
# 初始化默认值
runtimes=10
tag=""
# 接收命令行变量
# 判断是否有输入文件名和运行次数
# 创建一个数组来存储文件名
declare -a files

# 正则表达式，用于匹配 IP 地址和域名
ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
domain_regex="^([a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"

# 手动解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -c)
      runtimes=$2
      shift # 移过值
      ;;
    -t)
      tag=$2
      shift # 移过值
      ;;
    *) # 不是选项参数，视为文件名
      files+=("$1")
      ;;
  esac
  shift # 移过参数
done

# 检查是否提供了文件名
if [ ${#files[@]} -eq 0 ]; then
  echo
  echo "Version: $version   Built: $btime"
  echo
cat << EOF
Eg1: plmtr.sh [filename] [-c count (default = 10)] [-t tag]
Eg2: plmtr.sh ipfile1 ipfile2 ipfile3 ... -c 42 -t tag
Eg3: plmtr.sh -c 42 ipfile*

IPfile eg:
1.1.1.1 cfdns
8.8.8.8 
google.com what

EOF
    exit 1
fi

# 处理每个文件
for iplist in "${files[@]}"; do
    # 检查文件是否存在
    if [ ! -f "$iplist" ]; then
        echo "Warning: File '$iplist' not found, skipping."
        continue
    fi

    # 检查文件名是否包含 ".log"
    if [[ $iplist == *".mtr"* ]]; then
     #   echo "Skipping file '$iplist' as it contains '.log'."
        continue
    fi

    # 读取文件的第一行的第一列
    first_column=$(head -n 1 "$iplist" | awk '{print $1}')

    # 检查第一列是否为 IP 地址或域名
    if [[ $first_column =~ $ip_regex ]] || [[ $first_column =~ $domain_regex ]]; then
    #    echo
    #    echo "Processing file '$iplist' for $runtimes times with Tag '$tag'"
    # ... 处理每个文件的其他代码 ...
echo
echo "O(∩_∩)O Relax... Take a cup of coffee? tea?   Not me !!!"
echo "Version: $version   Built: $btime"
##
# 定义输出文件为输入文件名后面加.mtr
report=$iplist.mtr
##
# 统计输入文件的总行数
total_line=$(sed -n '$=' $iplist)
current_line=0
##
# 开始处理文件内IP
while read LINE  || [[ -n ${LINE} ]]
do
   ((current_line++))
   current_ip=$(echo $LINE | tr -d '\015' | awk '{print $1}')
   current_note=$(echo $LINE | tr -d '\015'  |awk '{print $2}')
   if [ ! -n "$current_note" ];then current_note=~~~~~~; fi
   echo -e "$tag \n### ↓↓↓  $current_line of $total_line ↓↓↓ ### | ###### $(date) ######" >> $report
   echo "File:$iplist    Note:$current_note    IP/Domain: $current_ip" >> $report
 if command -v nali >/dev/null 2>&1 ;then
   mtr -r -c $runtimes $current_ip 2>/dev/null | sed '1d' | awk '{printf "~%6s~%6s~%6s~%6s~%6s~%6s~%6s~%5s~%-15s\n",$1, $3, $4, $5, $6, $7, $8, $9, $2}'  | nali | awk -F '[]~[]' '{printf "%6s%-16s%6s%6s%6s%6s%6s%6s %5s %-5s\n",$2, $10,$3, $4, $5, $6, $7, $8,$9, $11}' >> $report
   else
   mtr -r -c $runtimes $current_ip 2>/dev/null | sed '1d' >> $report
 fi
   echo $'\n'>> $report
   printf "\033[36m%2s \033[37mof \033[35m%2s \033[32mFinished: \033[33m%-18s \033[32m: \033[36m%-16s \033[0m\n" $current_line $total_line $current_note $current_ip
done < $iplist
echo
### 脚本运行时长计算
finish_time=`date +%s`
duration=$(echo $(( finish_time - start_time )) | awk '{t=split("60 s 60 m 24 h 999 d",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')
##
# 输出结束时和运行用时到文件
echo Finish Time: $(date) >> $report
echo This shell script execution duration: $duration >> $report
echo -e "\n" >> $report
##
# 输出运行时间和output文件到屏幕
echo -e "\033[34mOutput File:\033[0m $report   \033[34mCount:\033[0m $runtimes"
echo -e "\033[34mThis shell script execution duration: \033[0m $duration" 
echo 
    else
        echo "Skipping file '$iplist': First column is not an IP or domain."
    fi
done
### 脚本完结撒花！！！ O(∩_∩)O
