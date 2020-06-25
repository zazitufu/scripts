#!/bin/bash
# 版本 0.1.1
# 此版本开始进行OS判断，因MAC OS 与 Linux 有些运行参数不同。
# eg: sudo ./plmtr.sh ipfile
# eg: sudo ./plmtr.sh ipfile 100
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
	echo "Example: sudo ./plmtr.sh [filename] [count] (default count = 10)"
  echo
exit
elif [ ! -n "$runtimes" ];then
	runtimes=10
fi
echo
echo "O(∩_∩)O Relax... Take a cup of coffee? tea?   Not me !!!"
echo 
# 定义输出文件为输入文件名后面加.mtr
report=$iplist.mtr
##
# 统计输入文件的总行数
total_line=$(sed -n '$=' $iplist)
current_line=0
##
# 预处理输入文件，将符号^M删掉
# sed -i "s/\x0D//g" $iplist ##此方式在Linux生效，Mac OS无效
sed -i "s/\r//g" $iplist
# 开始处理文件内IP
while read LINE  || [[ -n ${LINE} ]]
do
   ((current_line++))
   current_ip=$(echo $LINE | awk '{print $1}')
   current_note=$(echo $LINE | awk '{print $2}')
   echo "### ↓↓↓  $current_line of $total_line ↓↓↓ ### | ###### $(date) ######" >> $report
   echo "Note:$current_note    IP/Domain: $current_ip" >> $report
   mtr -r -c $runtimes $current_ip | sed '1d' >> $report
   echo $'\n'>> $report
   echo -e "\033[36m$current_line \033[37mof \033[35m$total_line \033[32mFinished: \033[36m$current_ip \033[33m$current_note\033[0m"
done < $iplist
echo
finish_time=`date "+%Y-%m-%d %H:%M:%S"`
##
##### 脚本运行时长计算，此处Linux 与 Mac OS有区别
### Linux 下的运行
if [ "$(uname)" = "Linux" ];then
duration=$(echo $(($(date +%s -d "$finish_time")-$(date +%s -d "$start_time"))) | awk '{t=split("60 s 60 m 24 h 999 d",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')
### Mac OS 下的运行
 elif [ "$(uname)" = "Darwin" ];then  
duration=$(echo $(($(date -j -f "%Y-%m-%d %H:%M:%S" "$finish_time" +%s )-$(date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" +%s))) | awk '{t=split("60 s 60 m 24 h 999 d",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')
fi
# 输出结束时和运行用时到文件
echo Finish Time: $(date) >> $report
echo This shell script execution duration: $duration >> $report
echo -e "\n" >> $report
##
# 输出运行时间和output文件到屏幕
echo -e "\033[34mOutput File:\033[0m $report   \033[34mCount:\033[0m $runtimes"
echo -e "\033[34mThis shell script execution duration: \033[0m $duration" 
echo 
