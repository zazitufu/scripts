#!/bin/bash
### 用来记录公网IP的变化。使用crontab定时执行此脚本。sed不适配Darwin
### eg:
### ./iplog.sh ./outputfilename
### 2021年8月13日 14点37分
### 有时会返回html内容，造成混乱，增加了过滤器过滤掉这类返回内容。
### 版本0.0.4
reportfile=$1
if $(tail -n 1 "$reportfile" | grep -q "Check") ;then
 sed -i '/Check/d' $reportfile
fi
last_ip=$(tail -n 1 $reportfile|awk -F"[ ：]" '{print $7}')
c_ip=$(curl -s myip.ipip.net |sed -e "s/^/$(date "+%Y-%m-%d %H:%M:%S") /" |sed -e '/html/d')
n_ip=$(echo $c_ip|awk -F"[ ：]" '{print $7}')
if [ -n "$c_ip" ] && [ "$last_ip" != "$n_ip" ];then
	echo $c_ip >> $reportfile
fi 
echo Check Time: $(date "+%Y-%m-%d %H:%M:%S") >> $reportfile
