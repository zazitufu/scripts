#!/bin/bash
# 版本 0.2.6 
# 主要update：从原来0.1.x版本的串行处理，改为多进程并行处理。暂时未限定ip进程数，个人使用不应该用上百个把！？
# 次要update：1，格式化输出界面；2,ping的错误信息输出null；3，无法解析的域名，loss用Void标识；4，备注在ip前面显示，方便和情况对照; 5,增加mdev數據
# eg: ./plping ipfile
# eg: ./plping ipfile 100
##
version=0.2.6
btime=2023-11-25
# 记录开始时间
start_time=`date +%s`
start_time2=$(date)
sleep 1
# 脚本开始
# 接收命令行变量
runtimes=$2
iplist=$1
##
# 判断是否有输入文件名和运行次数
if [ ! -f "$iplist" ] && [ ! -n "$runtimes" ];then
  echo
  echo "Example: plping [filename] [count] (default count = 10)"
  echo "Version: $version   Built: $btime"
exit
elif [ ! -n "$runtimes" ];then
    runtimes=10
fi
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
echo "## ↓↓↓ $start_time2 ↓↓↓ ######" >> $sum_report
echo "## ↓↓↓ $start_time2 ↓↓↓ ######" >> $report
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
echo
# 脚本完结撒花 O(∩_∩)O
