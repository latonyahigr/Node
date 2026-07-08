sudo bash -c '
set -e

export DEBIAN_FRONTEND=noninteractive

echo "========== 更新系统 =========="
apt-get update
apt-get -y upgrade

echo "========== 设置时区 =========="
timedatectl set-timezone Asia/Shanghai

echo "========== 开启官方 BBR =========="
cat >/etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null

echo "========== 检查当前 SSH 来源 =========="

CURRENT_IP=$(echo "$SSH_CLIENT" | awk "{print \$1}")

ALLOWED_IPV4="159.195.32.77 178.104.148.114"

if [[ -n "$CURRENT_IP" ]]; then
    if ! echo "$ALLOWED_IPV4" | grep -qw "$CURRENT_IP"; then
        echo
        echo "错误：当前 SSH 来源 IP ($CURRENT_IP) 不在白名单中。"
        echo "为了防止把自己锁在服务器外，脚本已停止。"
        exit 1
    fi
fi

echo "当前 SSH 来源 IP：$CURRENT_IP"
echo "白名单检查通过。"

echo "========== 配置 SSH 白名单 =========="

apt-get install -y iptables-persistent

mkdir -p /etc/iptables

iptables -N SSHGUARD 2>/dev/null || true
iptables -C INPUT -p tcp --dport 22 -j SSHGUARD 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 22 -j SSHGUARD
iptables -F SSHGUARD
iptables -A SSHGUARD -s 159.195.32.77/32 -j ACCEPT
iptables -A SSHGUARD -s 178.104.148.114/32 -j ACCEPT
iptables -A SSHGUARD -j DROP

ip6tables -N SSHGUARD 2>/dev/null || true
ip6tables -C INPUT -p tcp --dport 22 -j SSHGUARD 2>/dev/null || ip6tables -I INPUT 1 -p tcp --dport 22 -j SSHGUARD
ip6tables -F SSHGUARD
ip6tables -A SSHGUARD -s 2a01:4f8:1c18:fd00::1/128 -j ACCEPT
ip6tables -A SSHGUARD -s 2a0a:4cc0:c1:60d8:2444:ceff:fe11:f6f0/128 -j ACCEPT
ip6tables -A SSHGUARD -j DROP

iptables-save >/etc/iptables/rules.v4
ip6tables-save >/etc/iptables/rules.v6

systemctl enable netfilter-persistent >/dev/null 2>&1
systemctl restart netfilter-persistent

echo
echo "========== 初始化完成 =========="
echo "时区：$(timedatectl show --property=Timezone --value)"
echo "内核：$(uname -r)"
echo "BBR：$(sysctl -n net.ipv4.tcp_congestion_control)"
echo "队列算法：$(sysctl -n net.core.default_qdisc)"
'