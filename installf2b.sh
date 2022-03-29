#!/bin/bash
### 安装并设置fail2ban
##
apt-get -y install fail2ban iptables
cat << "EOF" > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = -1
findtime  = 60m
maxretry = 4

[sshd]
enabled = true
port    = ssh,20202
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF
sleep 1
systemctl enable fail2ban
sleep 1
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd
### The End ###
