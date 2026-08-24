#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly SSH_PORT=22

readonly ALLOWED_IPV4=(
    "159.195.32.77"
    "178.104.148.114"
    "47.239.7.216"
)

readonly ALLOWED_IPV6=(
    "2a01:4f8:1c18:fd00::1"
    "2a0a:4cc0:c1:60d8:2444:ceff:fe11:f6f0"
)

on_error() {
    local exit_code=$?
    local line_no=${1:-未知}
    local command=${2:-未知}

    printf '\n❌ 执行失败：第 %s 行，命令：%s\n' \
        "$line_no" "$command" >&2

    exit "$exit_code"
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

if [[ $EUID -ne 0 ]]; then
    echo "❌ 请使用 root 用户执行"
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "❌ 无法读取系统版本"
    exit 1
fi

source /etc/os-release

case "${ID:-}:${VERSION_ID%%.*}" in
    debian:12|ubuntu:22|ubuntu:24)
        echo "✅ 系统检查通过：${PRETTY_NAME:-未知}"
        ;;
    *)
        echo "当前系统：${PRETTY_NAME:-未知}"
        echo "❌ 仅支持 Debian 12、Ubuntu 22.04 或 Ubuntu 24.04"
        exit 1
        ;;
esac

echo "========== 检查当前 SSH 来源 =========="

CURRENT_IP="${SSH_CLIENT:-}"
CURRENT_IP="${CURRENT_IP%% *}"

if [[ -z "$CURRENT_IP" && -n "${SSH_CONNECTION:-}" ]]; then
    CURRENT_IP="${SSH_CONNECTION%% *}"
fi

if [[ -z "$CURRENT_IP" ]]; then
    echo "❌ 无法识别当前 SSH 来源 IP"
    echo "为防止锁死 SSH，脚本已停止，没有修改防火墙"
    exit 1
fi

IP_ALLOWED=0

for ip in "${ALLOWED_IPV4[@]}" "${ALLOWED_IPV6[@]}"; do
    if [[ "$CURRENT_IP" == "$ip" ]]; then
        IP_ALLOWED=1
        break
    fi
done

if [[ "$IP_ALLOWED" -ne 1 ]]; then
    echo "❌ 当前 SSH 来源 IP 不在白名单：$CURRENT_IP"
    echo "为防止锁死 SSH，脚本已停止，没有修改防火墙"
    exit 1
fi

echo "✅ 当前 SSH 来源 IP：$CURRENT_IP"
echo "✅ SSH 白名单检查通过"

echo "========== 安装必要组件 =========="

apt-get update

if command -v debconf-set-selections >/dev/null 2>&1; then
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean false" \
        | debconf-set-selections

    echo "iptables-persistent iptables-persistent/autosave_v6 boolean false" \
        | debconf-set-selections
fi

apt-get install -y \
    chrony \
    iptables \
    iptables-persistent \
    kmod

echo "========== 配置时间同步 =========="

systemctl enable --now chrony

if ! systemctl is-active --quiet chrony; then
    echo "❌ Chrony 服务启动失败"
    systemctl status chrony --no-pager || true
    exit 1
fi

if chronyc makestep >/dev/null 2>&1; then
    echo "✅ 系统时间已同步"
else
    echo "⚠️ Chrony 已运行，但暂时无法立即校准时间"
fi

chronyc tracking || true

echo "========== 开启官方 BBR =========="

modprobe tcp_bbr 2>/dev/null || true

cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null

CURRENT_BBR="$(sysctl -n net.ipv4.tcp_congestion_control)"
CURRENT_QDISC="$(sysctl -n net.core.default_qdisc)"

if [[ "$CURRENT_BBR" != "bbr" ]]; then
    echo "❌ BBR 未成功启用，当前算法：$CURRENT_BBR"
    exit 1
fi

if [[ "$CURRENT_QDISC" != "fq" ]]; then
    echo "❌ fq 队列算法未成功启用，当前算法：$CURRENT_QDISC"
    exit 1
fi

echo "✅ BBR：$CURRENT_BBR"
echo "✅ 队列算法：$CURRENT_QDISC"

echo "========== 配置 IPv4 SSH 白名单 =========="

iptables -N SSHGUARD 2>/dev/null || true
iptables -F SSHGUARD

for ip in "${ALLOWED_IPV4[@]}"; do
    iptables -A SSHGUARD -s "${ip}/32" -j ACCEPT
done

iptables -A SSHGUARD -j DROP

if ! iptables -C INPUT \
    -p tcp \
    --dport "$SSH_PORT" \
    -j SSHGUARD 2>/dev/null; then

    iptables -I INPUT 1 \
        -p tcp \
        --dport "$SSH_PORT" \
        -j SSHGUARD
fi

echo "✅ IPv4 SSH 白名单配置完成"

IPV6_ENABLED=0

if [[ -s /proc/net/if_inet6 ]] &&
   ip6tables -L -n >/dev/null 2>&1; then
    IPV6_ENABLED=1
fi

if [[ "$IPV6_ENABLED" -eq 1 ]]; then
    echo "========== 配置 IPv6 SSH 白名单 =========="

    ip6tables -N SSHGUARD 2>/dev/null || true
    ip6tables -F SSHGUARD

    for ip in "${ALLOWED_IPV6[@]}"; do
        ip6tables -A SSHGUARD -s "${ip}/128" -j ACCEPT
    done

    ip6tables -A SSHGUARD -j DROP

    if ! ip6tables -C INPUT \
        -p tcp \
        --dport "$SSH_PORT" \
        -j SSHGUARD 2>/dev/null; then

        ip6tables -I INPUT 1 \
            -p tcp \
            --dport "$SSH_PORT" \
            -j SSHGUARD
    fi

    echo "✅ IPv6 SSH 白名单配置完成"
else
    echo "ℹ️ 服务器未启用 IPv6，已跳过 IPv6 白名单"
fi

echo "========== 保存防火墙规则 =========="

mkdir -p /etc/iptables

iptables-save >/etc/iptables/rules.v4

if [[ "$IPV6_ENABLED" -eq 1 ]]; then
    ip6tables-save >/etc/iptables/rules.v6
fi

systemctl enable netfilter-persistent >/dev/null
systemctl restart netfilter-persistent

if ! systemctl is-active --quiet netfilter-persistent; then
    echo "❌ 防火墙持久化服务启动失败"
    systemctl status netfilter-persistent --no-pager || true
    exit 1
fi

echo
echo "========== 配置完成 =========="
echo "✅ 系统：${PRETTY_NAME:-未知}"
echo "✅ 内核：$(uname -r)"
echo "✅ BBR：$(sysctl -n net.ipv4.tcp_congestion_control)"
echo "✅ 队列算法：$(sysctl -n net.core.default_qdisc)"
echo "✅ SSH 端口：${SSH_PORT}"
echo "✅ 当前 SSH 来源：${CURRENT_IP}"

echo
echo "允许登录的 IPv4："

for ip in "${ALLOWED_IPV4[@]}"; do
    echo "  - $ip"
done

if [[ "$IPV6_ENABLED" -eq 1 ]]; then
    echo
    echo "允许登录的 IPv6："

    for ip in "${ALLOWED_IPV6[@]}"; do
        echo "  - $ip"
    done
fi

echo
echo "✅ 时间同步、BBR 和 SSH 白名单全部配置完成"
