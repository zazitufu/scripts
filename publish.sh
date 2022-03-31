#!/bin/bash
### 获取订阅内容，写入本地文件，并将本地文件并传送至订阅连接。
## Version 0.2
## 2022年3月31日13点40分
read -e -p "Input Subscribe:" subscribe
read -s -p "Remote Host Password:" pwd1
echo $subscribe > filename
#scp -P port filename user@hostname:/www/wwwroot/pathname/
#ssh -p port user@hostname "echo $subscribe > www/wwwroot/pathname/kk"
echo $subscribe > kk
cat << EOF >/dev/null
$pwd1
EOF
