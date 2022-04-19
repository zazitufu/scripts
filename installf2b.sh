#!/bin/bash
### 安装并设置fail2ban
##
apt update
apt-get -y install fail2ban iptables
echo 
read -p "Input SSH port:" sshport
read -p "Ignore IP:" inputip
ignoreip=$( ping -q -c 1  $inputip  2>/dev/null | grep PING | sed -e "s/).*//" | sed -e "s/.*(//" )
echo 
cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 $ignoreip
bantime  = -1
findtime  = 60m
maxretry = 4
[sshd]
enabled = true
port    = ssh,$sshport
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

sleep 1
systemctl enable fail2ban
sleep 1
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd

echo "Fail2ban User config file path: /etc/fail2ban/jail.local"
echo 
### The End ###
