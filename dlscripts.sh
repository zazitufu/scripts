#!/bin/bash
### 批量下载自制脚本文件
scriptfile=(
	plmtr.sh
	plping.sh
	iplog.sh
	chomz.sh
	acme320.sh
	prettyping
	publish.sh
	traffic.sh
	testip.sh
	dlscripts.sh
	lastbcount.sh
	installf2b.sh
 	bns.sh
	)
for filename in ${scriptfile[@]}
do
	curl -O https://raw.githubusercontent.com/zazitufu/scripts/master/$filename
	chmod +x $filename
done
