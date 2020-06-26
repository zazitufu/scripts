#!/bin/bash
# 版本 0.1.2     2020年6月26日
# 主要update：各函数使用Linux和Mac OS通用的参数。不再进行系统版本判断。
# 不再修改源文件处理回车符，改为在内存处理，源文件保持不变。
# eg: sudo ./plmtr ipfile
# eg: sudo ./plmtr ipfile 100
##
version=0.1.2
btime=2020-06-26
# 记录开始时间
start_time=`date +%s`
sleep 1
# 脚本开始
# 接收命令行变量
runtimes=$2
iplist=$1
##
# 判断是否有输入文件名和运行次数
if [ ! -f "$iplist" ] && [ ! -n "$runtimes" ];then
  echo
  echo "Example: sudo ./plmtr [filename] [count] (default count = 10)"
  echo "Version: $version   Built: $btime"
exit
elif [ ! -n "$runtimes" ];then
	runtimes=10
fi
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
   current_ip=$(echo $LINE | sed 's/\r//' | awk '{print $1}')
   current_note=$(echo $LINE | sed 's/\r//' |awk '{print $2}')
   echo "### ↓↓↓  $current_line of $total_line ↓↓↓ ### | ###### $(date) ######" >> $report
   echo "Note:$current_note    IP/Domain: $current_ip" >> $report
   mtr -r -c $runtimes $current_ip | sed '1d' >> $report
   echo $'\n'>> $report
   echo -e "\033[36m$current_line \033[37mof \033[35m$total_line \033[32mFinished: \033[36m$current_ip \033[33m$current_note\033[0m"
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
### 脚本完结撒花！！！ O(∩_∩)O
