#!/bin/bash
# 版本: 0.4.1 
# Date:2023-11-29 02:45
# https://github.com/zazitufu/scripts/blob/master/plping.sh
# eg: ./plping ipfile
# eg: ./plping ipfile -c 100 -t tag
# eg：./plping ipfile1 ipfile2 ipfile3 ... -c 5 -t tag
# eg: ./plping ipfile* -c 3 -t tag
# ipfile 格式：每行一个ip/domain ，如果有备注就在ip/domain后先加空格再写。
# ipfile 例： 1.1.1.1 cloudflare
##
version=0.4.1
btime=2023-11-29
# 记录开始时间
start_time=`date +%s`
start_time2=$(date)
sleep 1
# 脚本开始
# 初始化默认值
runtimes=10
tag=""
# 接收命令行变量
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
    echo "Error: No file specified."
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
    if [[ $iplist == *".log"* ]]; then
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
# 输出文件为输入文件名后面加.log,  详细输出文件为输入文件名后面加.logb
sum_report=$iplist.log
report=$iplist.logb
tmp=tmp.plpingtmp

### 避免上次中断产生临时文件存在，影响本次运行结果查询，先删除一次。
rm $tmp >/dev/null 2>&1
##
# 统计输入文件的总行数
total_line=$(sed -n '$=' $iplist)
##
### 子shell：进度条显。进度按照1秒ping一次计算。
processBar()
{
while [ $process -lt $(( runtimes + 2 ))  ]
do
    let process++
    now=$process
    all=$(( runtimes + 2 ))
    percent=`awk BEGIN'{printf "%f", ('100*$now'/'$all')}'`
    len=`awk BEGIN'{printf "%d", '$percent'}'`
    bar='>'
    for((i=0;i<len/2-1;i++))
    do
        bar="="$bar
    done
    printf "\e[31m%s \e[37m%s \e[32m[%-50s]\e[33m[%.2f%%]\e[m\r" Total-IPs: $total_line $bar $percent
    sleep 1
done
printf "\n"
}
##
### 子shell：ping的进程
goping()
  {
   current_ip=$(echo $LINE | tr -d '\015' | awk '{print $1}')
   current_note=$(echo $LINE | tr -d '\015' |awk '{print $2}')
   if [ ! -n "$current_note" ];then current_note=~~~~~~; fi
   ping -q -W 2 -c $runtimes $current_ip  2>/dev/null | sed '1,2d; s/---/No:'$current_line' ~~~/ ; s/ping/~ '$current_note' ~~~ ping/'| xargs >> $tmp
   }
######
### 子shell：从输出tmp结果提取信息
getinfo()
{
   current_ip=$(echo $LINE | tr -d '\015' | awk '{print $1}')
   current_note=$(echo $LINE | tr -d '\015' |awk '{print $2}')
   if [ ! -n "$current_note" ];then current_note=~~~~~~; fi
   _Loss=~VoiD~
   _Avg=~~~~~   
   _Mdev=~~~~~
   eval $(cat $tmp | grep No:"$current_line " | awk -F"[/, ]" -v str="loss" -v str2="=" '{v="";for (i=1;i<=NF;i++)  if ($i==str) v=v?"":i;w="";for (k=1;k<=NF;k++)  if ($k==str2) w=w?"":k;if (v) printf("_Loss=%.2f%%; _Avg=%sms; _Mdev=%sms" ,$(v-2), $(w+2), $(w+4))}') 
   printf "%2s of %-2s Loss:%-7s Avg:%-10s Mdev:%-10s %-18s : %-16s\n" $current_line $total_line $_Loss $_Avg $_Mdev $current_note $current_ip >> $sum_report
   printf "\033[36m%2s \033[37mof \033[35m%-2s \033[33mLoss:%-7s \033[34mAvg:%-10s \033[36mMdev:%-10s \033[33m%-18s \033[32m: \033[36m%-16s\033[0m\n" $current_line $total_line $_Loss $_Avg $_Mdev $current_note  $current_ip 
 } 

########### 子shell 定义完毕
## 输入本次信息到log和logb
echo -e "$tag \n## ↓↓↓ $start_time2 ↓↓↓ ######    File:$iplist" >> $sum_report
echo -e "$tag \n## ↓↓↓ $start_time2 ↓↓↓ ######    File:$iplist" >> $report
echo >> $sum_report
echo >> $report
##
process=0
processBar &
PID=$!
### 开始多进程ping处理ip
current_line=0
while read LINE  || [[ -n ${LINE} ]] 
do
     ((current_line++))
   goping &
done < $iplist
wait
sort -t : -k 2 -n tmp.plpingtmp -o tmp.plpingtmp #将临时文件进行排序并保存。
### 开始读取临时文件的信息进行处理
current_line=0
while read LINE  || [[ -n ${LINE} ]] 
do
     ((current_line++))
   getinfo
done < $iplist
{ kill $PID && wait $PID; } 2>/dev/null
echo
### 将临时文件整理并输出到detail文件，然后删除临时文件。
cat tmp.plpingtmp | sed "$(printf 's/$/\\\n/');$(printf 's/---/\\\n/');$(printf 's/loss/loss\\\n/')" >> $report
rm $tmp >/dev/null 2>&1
##
# 脚本完成时间，运行总时长统计
finish_time=`date +%s`
duration=$(echo $(( finish_time - start_time )) | awk '{t=split("60 s 60 m 24 h 999 d",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')
##
# 输出时间到文件
echo "Finish Time: $(date)" >> $report
echo "Duration of this script: $duration" >> $report
echo -e "\n" >> $report
echo >> $sum_report 
echo "Duration of this script: $duration   Count: $runtimes" >> $sum_report
echo -e "\n" >> $sum_report
# 输出运行用时到屏幕
echo -e "\033[34mFinish Time:\033[0m $(date)"
echo -e "\033[34mOutput File:\033[0m $sum_report   \033[34mDetail File:\033[0m $report"
echo -e "\033[34mDuration of this script: \033[0m$duration    \033[34mCount: \033[0m$runtimes" 
if [ -n "$tag" ]; then
    echo -e "\033[34mTag: \033[0m$tag "
else
    echo "" 
fi
echo
    else
        echo "Skipping file '$iplist': First column is not an IP or domain."
    fi
done
# 脚本完结撒花 O(∩_∩)O
