#!/bin/bash
# 版本 0.1.6 
# 主要update：增加每行IP的进度条。避免在次数多的时候感觉停滞。
# eg: ./plping ipfile
# eg: ./plping ipfile 100
##
version=0.1.6
btime=2020-06-30
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
##
# 统计输入文件的总行数
total_line=$(sed -n '$=' $iplist)
current_line=0
##
### 进度条显。进度按照1秒ping一次计算。
processBar()
{
while [ $process -lt $runtimes ]
do
    let process++
    now=$process
    all=$runtimes
    percent=`awk BEGIN'{printf "%f", ('100*$now'/'$all')}'`
    len=`awk BEGIN'{printf "%d", '$percent'}'`
    bar='>'
    for((i=0;i<len/4-1;i++))
    do
        bar="="$bar
    done
    printf "\e[34m%s \e[37m%s \e[35m%s \e[32m[%-25s]\e[33m[%.2f%%]\e[m\r" $current_line of $total_line $bar $percent
    sleep 1
done
sleep 10
printf "\n"
}
###
# 开始处理输入文件内的IP
echo "## ↓↓↓ $start_time2 ↓↓↓ ######" >> $sum_report
echo >> $sum_report
echo "Start time: $start_time2" >> $report
##
while read LINE  || [[ -n ${LINE} ]] 
do
	 ((current_line++))
	 process=0
   echo "#### ↓↓↓  $current_line of $total_line ↓↓↓ ##########################################" >> $report
   current_ip=$(echo $LINE | tr -d '\015' | awk '{print $1}')
   current_note=$(echo $LINE | tr -d '\015' |awk '{print $2}')
   echo $current_note >> $report
   processBar &
   PID=$!
   ping -q -c $runtimes $current_ip | sed '1,2d' >> $report
   kill $PID
   los_avg=$( echo -e Loss:$( tail -n 4 $report |  awk -F"[, ]" -v str="loss" '{v="";for (i=1;i<=NF;i++)  if ($i==str) v=v?"":i;if (v) print $(v-2)}' ) Avg:$( tail -n 3 $report | grep "avg" | awk -F"/" '{print $5}'))
   echo $'\n' >> $report
   echo "$current_line of $total_line $los_avg Addr: $current_ip $current_note " >> $sum_report
   echo -e "\033[36m$current_line \033[37mof \033[35m$total_line \033[33m$los_avg \033[32mFinished: \033[36m$current_ip \033[33m$current_note\033[0m"
done < $iplist
echo
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
