#!/bin/bash
# 记录开始时间
start_time=`date --date='0 days ago' "+%Y-%m-%d %H:%M:%S"`
sleep 1
# 脚本开始
# 接收命令行变量
runtimes=$2
iplist=$1

# 判断是否有参数输入
if [ ! -f "$iplist" ] && [ ! -n "$runtimes" ];then
	echo
	echo "Example: plmtr [filename] [count] (default count = 10)"
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

# 统计输入文件的总行数
total_line=$(sed -n '$=' $iplist)
current_line=0

# 预处理输入文件，将符号^M删掉
sed -i "s/\x0D//g" $iplist

# 开始处理文件内IP
while read LINE  || [[ -n ${LINE} ]]
do
	 ((current_line++))
   echo "##################################### $LINE #### | ↓↓↓↓  $current_line of $total_line ↓↓↓↓" >> $report
   mtr -r -c $runtimes $LINE >> $report
   echo $'\n'>> $report
   echo -e "\033[36m$current_line \033[37mof \033[35m$total_line \033[32mFinished: $LINE\033[0m"
done < $iplist
echo

# 脚本运行总时长统计
finish_time=`date --date='0 days ago' "+%Y-%m-%d %H:%M:%S"`
duration=$(echo $(($(date +%s -d "$finish_time")-$(date +%s -d "$start_time"))) | awk '{t=split("60 s 60 m 24 h 999 d",a);for(n=1;n<t;n+=2){if($1==0)break;s=$1%a[n]a[n+1]s;$1=int($1/a[n])}print s}')

# 输出结束时和运行用时到文件
echo Finish Time: $(date) >> $report
echo This shell script execution duration: $duration >> $report
echo -e "\n" >> $report

# 输出运行时间和output文件到屏幕
echo -e "\033[34mOutput File:\033[0m $report"
echo -e "\033[34mThis shell script execution duration: \033[0m $duration" 
echo
