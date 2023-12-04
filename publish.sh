#!/bin/bash
### 获取订阅内容并将其传送至远程服务器上的文件

# 版本信息和日期
version="0.3"
date="2023年12月5日"

# 读取用户输入的订阅链接
read -e -p "Input Subscribe: " subscribe
# 读取远程主机存放订阅链接的文件名
read -e -p "Subscribe file name:" subscribefile

# 将订阅链接传送到远程服务器的文件中
# 确保已设置 SSH 密钥认证，否则可能需要手动输入密码
# 自行修改domain / port / user / hostname
remote_path="/www/wwwroot/domain/$subscribefile"
ssh -p port user@hostname "echo '$subscribe' > $remote_path" || echo "SSH 命令执行失败。"

echo "脚本执行完毕。版本：$version，日期：$date"
