#!/bin/bash
### 这个脚本用来在vps上使用iptables，因为有些厂家自己系统没有防火墙。
# 确认脚本运行风险
echo "警告: 运行此脚本将会应用新的防火墙规则。"
echo "请确保 SSH 端口 (通常是 22) 已在允许列表中，否则你可能会失去远程访问权限。"
echo "你想继续吗？ (yes/no)"

read answer
if [ "$answer" != "yes" ]; then
    echo "操作已取消。"
    exit
fi

# 清除现有的 iptables 和 ip6tables 规则
iptables -F
ip6tables -F

# 设置默认策略
iptables -P INPUT DROP
iptables -P FORWARD DROP
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
ip6tables -P OUTPUT ACCEPT

# 定义端口
ports="22,80,443,12345:54321"

# 允许特定的入站端口（IPv4）
iptables -A INPUT -p tcp -m multiport --dports $ports -j ACCEPT
iptables -A INPUT -p udp -m multiport --dports $ports -j ACCEPT

# 允许特定的入站端口（IPv6）
ip6tables -A INPUT -p tcp -m multiport --dports $ports -j ACCEPT
ip6tables -A INPUT -p udp -m multiport --dports $ports -j ACCEPT

# 允许来自本地环回接口的数据
iptables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT

# 允许已建立和相关的入站连接
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 允许 ICMP (ping) - IPv4
iptables -A INPUT -p icmp -j ACCEPT

# 允许 ICMPv6 (ping) - IPv6
ip6tables -A INPUT -p icmpv6 -j ACCEPT

echo "Iptables (IPv4) 和 ip6tables (IPv6) 规则已成功设置。"

# 检查 iptables-persistent 是否已安装
if ! dpkg -s iptables-persistent > /dev/null 2>&1; then
    echo "正在安装 iptables-persistent..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
fi

# 保存 iptables 和 ip6tables 规则
netfilter-persistent save

echo "iptables 和 ip6tables 规则已成功保存。"
