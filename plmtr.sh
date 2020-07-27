#!/bin/bash
# 版本 0.2.4     2020年7月27日 22点23分
# 主要update：配合使用nali做管道，输出各ip的geo信息。nali命令是否存在都可以执行。
# nali使用的版本：https://github.com/zu1k/nali。下载后应该首先使用nali update进行ip库下载。
# 注意事项：nali 无论用什么版本，命令行应该alias为nali
# eg: sudo ./plmtr ipfile
# eg: sudo ./plmtr ipfile 100
##
version=0.2.4
btime=2020-07-27
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
   current_ip=$(echo $LINE | tr -d '\015' | awk '{print $1}')
   current_note=$(echo $LINE | tr -d '\015'  |awk '{print $2}')
   echo "### ↓↓↓  $current_line of $total_line ↓↓↓ ### | ###### $(date) ######" >> $report
   echo "Note:$current_note    IP/Domain: $current_ip" >> $report
 if command -v nali >/dev/null 2>&1 ;then
   mtr -r -c $runtimes $current_ip 2>/dev/null | sed '1d' | awk '{printf "~%6s~%6s~%6s~%6s~%6s~%6s~%6s~%5s~%-15s\n",$1, $3, $4, $5, $6, $7, $8, $9, $2}'  | nali | awk -F '[]~[]' '{printf "%6s%-16s%6s%6s%6s%6s%6s%6s %5s %-5s\n",$2, $10,$3, $4, $5, $6, $7, $8,$9, $11}' >> $report
   else
   mtr -r -c $runtimes $current_ip 2>/dev/null | sed '1d' >> $report
 fi
   echo $'\n'>> $report
   printf "\033[36m%2s \033[37mof \033[35m%2s \033[32mFinished: \033[36m%-16s\033[33m%-10s\033[0m\n" $current_line $total_line $current_ip $current_note
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
