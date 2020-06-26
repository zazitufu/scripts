#!/bin/bash
# 版本 0.1.2     2020年6月26日
# 主要update：系统版本判断后的动作，修改为变量更替，不再使用多行重复代码。
# eg: ./plping ipfile
# eg: ./plping ipfile 100
##
# 记录开始时间
start_time=`date "+%Y-%m-%d %H:%M:%S"`
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
  echo
exit
elif [ ! -n "$runtimes" ];then
	runtimes=10
fi
echo
echo "O(∩_∩)O Relax... Take a cup of coffee? tea?   Not me !!!"
echo 
##
# 输出文件为输入文件名后面加.log,  详细输出文件为输入文件名后面加.logb
sum_report=$iplist.log
report=$iplist.logb
##
# 统计输入文件的总行数
total_line=$(sed -n '$=' $iplist)
current_line=0
##
# 预处理输入文件，将回车符号^M删掉。Windows和Dos下编辑的文件有可能产生这个问题。
sed -i "s/\r//g" $iplist
##
#### 进行Linux系统 和 MAC OS X的区分 时间转换的参数设定 ####################
if [ "$(uname)" = "Linux" ];then
    echo "Running on Linux"
    option_date=$(echo "-d")
  elif [ "$(uname)" = "Darwin" ];then
    echo echo "Running on MacOS"
    option_date=$(echo "-j -f \"%Y-%m-%d %H:%M:%S\"")
fi
##
# 开始处理输入文件内的IP
echo "## ↓↓↓ $(date) ↓↓↓ ######" >> $sum_report
echo >> $sum_report
echo "Start time: $start_time" >> $report
while read LINE  || [[ -n ${LINE} ]]
do
	 ((current_line++))
   echo "#### ↓↓↓  $current_line of $total_line ↓↓↓ ##########################################" >> $report
   current_ip=$(echo $LINE | awk '{print $1}')
   current_note=$(echo $LINE | awk '{print $2}')
   echo $current_note >> $report
   ping -q -c $runtimes $current_ip | sed '1,2d' >> $report
   los_avg=$(echo -e Loss:$(echo $(tail -n 4 $report | grep -Eo "[0-9]+*%") Avg:$(echo $(tail -n 3 $report | grep "avg") | awk -F"/" '{print $5}')))
   echo $'\n' >> $report
   echo "$current_line of $total_line $los_avg Addr: $LINE " >> $sum_report
   echo -e "\033[36m$current_line \033[37mof \033[35m$total_line \033[33m$los_avg \033[32mFinished: \033[36m$current_ip \033[33m$current_note\033[0m"
done < $iplist
echo
##
# 脚本完成时间，运行总时长统计
finish_time=`date "+%Y-%m-%d %H:%M:%S"`
duration=$(echo $(($(date $option_date "$finish_time" +%s )-$(date $option_date "$start_time" +%s))) | awk '{t=split("60 s 60 m 24 h 999 d",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')
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
