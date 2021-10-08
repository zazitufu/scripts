#!/bin/bash
### 用来记录公网IP的变化。使用crontab定时执行此脚本。sed不适配Darwin
### eg:
### ./iplog.sh ./outputfilename
### 2021年10月8日 16点23分
### 有时会返回html内容，造成混乱，增加了过滤器过滤掉这类返回内容。改变过滤条件为<{;字符。同时修改IP的获取方式，不再用awk，换grep。
### 版本0.0.6

reportfile=$1
if $(tail -n 1 "$reportfile" | grep -q "Check") ;then
 sed -i '/Check/d' $reportfile
fi
last_ip=$(tail -n 1 $reportfile|grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
c_ip=$(curl -s myip.ipip.net |sed -e "s/^/$(date "+%Y-%m-%d %H:%M:%S") /" |sed -e '/[<{;]/d')
n_ip=$(echo $c_ip|grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}")
if [ -n "$c_ip" ] && [ "$last_ip" != "$n_ip" ];then
	echo $c_ip >> $reportfile
fi 
echo Check Time: $(date "+%Y-%m-%d %H:%M:%S") >> $reportfile
