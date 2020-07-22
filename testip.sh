#!/bin/bash
# 版本 0.0.2 
# 最好用在软路由上，如N1等上面进行目标ip健康度检测
# eg： ./testip.sh ip
# 单次执行意义不大，放在crontab计划任务执行。自己定义几分钟执行一次，脚本ping是每次ping 10次
# 后缀文件.log是统计记录，以覆盖方式写入每次结果。过几个小时或者半天时间可以自己cat 方式查看统计记录。
# 后缀文件.tmp是ping结果处理过的记录，用来生成.log的统计结果。以追加方式写入。
goip=$1
###  默认输出文件路径是当前用户的~路径。建议自己修改
tmpfile=~/${goip}.tmp
reportfile=~/${goip}.log
#
ping -q -c 10 $goip| sed "1,3d" |xargs|sed "s/^/Hour\|$(date +%H)\|/ ; s/ /\|/g ; s/\//\|/g">> $tmpfile
#
gota=$(tail -n 1 $tmpfile |awk -F"[|]" -v str="=" '{v="";for (i=1;i<=NF;i++)  if ($i==str) v=v?"":i;if (v) print v}' )
#
count_total_A=$(cat $tmpfile | awk -F"|" '{if ($2>=22 || $2<5) print $0}' | awk -F '|' 'BEGIN {sum=0}{sum += $3} END {print sum}')
count_receive_A=$(cat $tmpfile | awk -F"|" '{if ($2>=22 || $2<5) print $0}' | awk -F '|' 'BEGIN {sum=0}{sum += $6} END {print sum}')
min_A=$(cat $tmpfile | awk -F"|" '{if ($2>=22 || $2<5 && $6!="0") print $0}' |awk -F '|' 'BEGIN {min=9999} {if($('$gota'+1)<min){min=$('$gota'+1)}} END {print min}')
max_A=$(cat $tmpfile | awk -F"|" '{if ($2>=22 || $2<5 && $6!="0") print $0}' |awk -F '|' 'BEGIN {max=0} {if($('$gota'+3)>max){max=$('$gota'+3)}} END {print max}')
avg_A=$(cat $tmpfile | awk -F"|" '{if ($2>=22 || $2<5 && $6!="0") print $0}' |awk -F '|' '{sum += $('$gota'+2)} END {if(NR != 0) print sum/NR;else print "0"}')
overtime_A=$((count_total_A - count_receive_A))
loss_A=$(awk 'BEGIN{if('$count_total_A' > 0) printf "%.2f%%",('$overtime_A'/'$count_total_A')*100;else print "0"}')
#
count_total_B=$(cat $tmpfile | awk -F"|" '{if ($2>=5 && $2<11) print $0}' | awk -F '|' 'BEGIN {sum=0}{sum += $3} END {print sum}')
count_receive_B=$(cat $tmpfile | awk -F"|" '{if ($2>=5 && $2<11) print $0}' | awk -F '|' 'BEGIN {sum=0}{sum += $6} END {print sum}')
min_B=$(cat $tmpfile | awk -F"|" '{if ($2>=5 && $2<11 && $6!="0") print $0}' |awk -F '|' 'BEGIN {min=9999} {if($('$gota'+1)<min){min=$('$gota'+1)}} END {print min}')
max_B=$(cat $tmpfile | awk -F"|" '{if ($2>=5 && $2<11 && $6!="0") print $0}' |awk -F '|' 'BEGIN {max=0} {if($('$gota'+3)>max){max=$('$gota'+3)}} END {print max}')
avg_B=$(cat $tmpfile | awk -F"|" '{if ($2>=5 && $2<11 && $6!="0") print $0}' |awk -F '|' '{sum += $('$gota'+2)} END {if(NR != 0) print sum/NR;else print "0"}')
overtime_B=$((count_total_B - count_receive_B))
loss_B=$(awk 'BEGIN{if('$count_total_B' > 0) printf "%.2f%%",('$overtime_B'/'$count_total_B')*100;else print "0"}')
#
count_total_C=$(cat $tmpfile | awk -F"|" '{if ($2>=11 && $2<17) print $0}' | awk -F '|' 'BEGIN {sum=0}{sum += $3} END {print sum}')
count_receive_C=$(cat $tmpfile | awk -F"|" '{if ($2>=11 && $2<17) print $0}' | awk -F '|' 'BEGIN {sum=0}{sum += $6} END {print sum}')
min_C=$(cat $tmpfile | awk -F"|" '{if ($2>=11 && $2<17 && $6!="0") print $0}' |awk -F '|' 'BEGIN {min=9999} {if($('$gota'+1)<min){min=$('$gota'+1)}} END {print min}')
max_C=$(cat $tmpfile | awk -F"|" '{if ($2>=11 && $2<17 && $6!="0") print $0}' |awk -F '|' 'BEGIN {max=0} {if($('$gota'+3)>max){max=$('$gota'+3)}} END {print max}')
avg_C=$(cat $tmpfile | awk -F"|" '{if ($2>=11 && $2<17 && $6!="0") print $0}' |awk -F '|' '{sum += $('$gota'+2)} END {if(NR != 0) print sum/NR;else print "0"}')
overtime_C=$((count_total_C - count_receive_C))
loss_C=$(awk 'BEGIN{if('$count_total_C' > 0) printf "%.2f%%",('$overtime_C'/'$count_total_C')*100;else print "0"}')
#
count_total_D=$(cat $tmpfile | awk -F"|" '{if ($2>=17 && $2<23) print $0}' | awk -F '|' 'BEGIN {sum=0}{sum += $3} END {print sum}')
count_receive_D=$(cat $tmpfile | awk -F"|" '{if ($2>=17 && $2<23 ) print $0}' | awk -F '|' 'BEGIN {sum=0}{sum += $6} END {print sum}')
min_D=$(cat $tmpfile | awk -F"|" '{if ($2>=17 && $2<23 && $6!="0") print $0}' |awk -F '|' 'BEGIN {min=9999} {if($('$gota'+1)<min){min=$('$gota'+1)}} END {print min}')
max_D=$(cat $tmpfile | awk -F"|" '{if ($2>=17 && $2<23 && $6!="0") print $0}' |awk -F '|' 'BEGIN {max=0} {if($('$gota'+3)>max){max=$('$gota'+3)}} END {print max}')
avg_D=$(cat $tmpfile | awk -F"|" '{if ($2>=17 && $2<23 && $6!="0") print $0}' |awk -F '|' '{sum += $('$gota'+2)} END {if(NR != 0) print sum/NR;else print "0"}')
overtime_D=$((count_total_D - count_receive_D))
loss_D=$(awk 'BEGIN{if('$count_total_D' > 0) printf "%.2f%%",('$overtime_D'/'$count_total_D')*100;else print "0"}')
#
count_total=$((count_total_D + count_total_C + count_total_B + count_total_A))
count_receive_total=$((count_receive_D + count_receive_C + count_receive_B + count_receive_A))
overtime_total=$((count_total - count_receive_total))
min_total=$(cat $tmpfile | awk -F"|" '{if ($6!="0") print $0}' |awk -F '|' 'BEGIN {min=9999} {if($('$gota'+1)<min){min=$('$gota'+1)}} END {print min}')
max_total=$(cat $tmpfile | awk -F"|" '{if ($6!="0") print $0}' |awk -F '|' 'BEGIN {max=0} {if($('$gota'+3)>max){max=$('$gota'+3)}} END {print max}')
avg_total=$(cat $tmpfile | awk -F"|" '{if ($6!="0") print $0}' |awk -F '|' '{sum += $('$gota'+2)} END {if(NR != 0) print sum/NR;else print "0"}')
loss_total=$(awk 'BEGIN{if('$count_total' > 0) printf "%.2f%%",('$overtime_total'/'$count_total')*100;else print "0"}')
#
echo > $reportfile
printf "+++ %-14s => %35s\n" 远程延迟监测    $goip >> $reportfile
echo "---------------------------------------------------------" >> $reportfile
printf "| %-27s  | %-25s    |\n"  "子 23:00 ~丑~ 4:59 寅"   "卯 5:00 ~辰~ 10:59 巳"  >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"  最低延迟： ${min_A}ms 最低延迟： ${min_B}ms >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"  最高延迟： ${max_A}ms 最高延迟： ${max_B}ms >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"  平均延迟： ${avg_A}ms 平均延迟： ${avg_B}ms >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"  丢包率： $loss_A 丢包率： $loss_B >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"  超时次数： $overtime_A 超时次数： $overtime_B >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"  测试次数： $count_total_A 测试次数： $count_total_B >> $reportfile
echo "---------------------------------------------------------" >> $reportfile
printf "| %-27s  | %-25s    |\n" "午 11:00 ~未~ 16:59 申" "酉 17:00 ~戌~ 22:59亥" >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"   最低延迟： ${min_C}ms 最低延迟： ${min_D}ms >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"   最高延迟： ${max_C}ms 最高延迟： ${max_D}ms >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"   平均延迟： ${avg_C}ms 平均延迟： ${avg_D}ms >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"   丢包率： $loss_C 丢包率： $loss_D >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"   超时次数： $overtime_C 超时次数： $overtime_D >> $reportfile
printf "| %-14s %-10s     | %-14s %-15s|\n"   测试次数： $count_total_C 测试次数： $count_total_D>> $reportfile
echo "---------------------------------------------------------" >> $reportfile
printf "| %-58s|\n" 全局统计 >> $reportfile
printf "| %-14s %-10s       %-14s %-15s|\n" 最低延迟： ${min_total}ms 丢包率： $loss_total >> $reportfile
printf "| %-14s %-10s       %-14s %-15s|\n" 平均延迟： ${avg_total}ms 超时次数： $overtime_total >> $reportfile
printf "| %-14s %-10s       %-14s %-15s|\n" 最高延迟： ${max_total}ms 测试次数： $count_total >> $reportfile
echo "---------------------------------------------------------" >> $reportfile
echo>> $reportfile
### 完结撒花 O(∩_∩)O
