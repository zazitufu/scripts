#!/bin/bash
#记录开始时间
start_time=`date --date='0 days ago' "+%Y-%m-%d %H:%M:%S"`
sleep 2
#脚本开始
echo
echo "Example: plmtr [filename] [count] "
echo
#接收命令行变量
runtimes=$2
iplist=$1
#输出文件为输入文件名后面加.log
report=$iplist.log
#统计输入文件的总行数
total_line=$(sed -n '$=' $iplist)
current_line=0
while read LINE
do
	 ((current_line++))
   echo "↓↓↓↓  $current_line of $total_line ↓↓↓↓ | #### $LINE #####################################" >> $report
   mtr -r -c $runtimes $LINE | sed '1d' >> $report
   echo $'\n'>>$report
   echo -e "\033[36m$current_line \033[37mof \033[35m$total_line \033[32mFinished: $LINE\033[0m"
done < $iplist
echo
echo -e "\033[34mOutput File:\033[0m $report"
#脚本运行总时长统计
finish_time=`date --date='0 days ago' "+%Y-%m-%d %H:%M:%S"`
duration=$(echo $(($(date +%s -d "$finish_time")-$(date +%s -d "$start_time"))) | awk '{t=split("60 s 60 m 24 h 999 d",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')
#输出结束时间
echo Finish Time: $(date) >> $report
#输出运行用时
echo This shell script execution duration: $duration >> $report
echo -e "\033[34mThis shell script execution duration: \033[0m $duration" 
