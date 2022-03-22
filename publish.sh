#!/bin/bash
### 获取订阅内容，写入本地文件，并将本地文件并传送至订阅连接。
## Version 0.1
## 2022年3月22日17点18分
read -p "Input Subscribe:" subscribe
read -s -p "Remote Host Password:" pwd1
echo $subscribe > filename
scp -P port filename user@hostname:/www/wwwroot/pathname/
cat << EOF >/dev/null
$pwd1
EOF
