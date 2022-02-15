#!/bin/bash
## 因为宝塔的自动续签脚本acme_v2.py，经常出现续签失败超过3次，就不再尝试续签的问题，写了个脚本来手动解决这个问题。
## 如果需要自动化，可以结合计划任务执行这个脚本。这个脚本基本一周执行一次应该就没问题了。
echo
echo "Backup to /www/server/panel/config/letsencrypt.json.bak"
cp /www/server/panel/config/letsencrypt.json /www/server/panel/config/letsencrypt.json.bak 2>/dev/null
echo "Modify retry_count from 3 to 0"
sed -i 's/\"retry_count\": 3/\"retry_count\": 0/g' /www/server/panel/config/letsencrypt.json 2>/dev/null
echo
