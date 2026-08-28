#!/usr/bin/env bash
set -Eeuo pipefail

readonly V2BX_VERSION="v0.4.0"
readonly NFU_TESTED_VERSION="v1.0.4"
readonly V2BX_INSTALL_URL="https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh"
readonly CONFIG_URL="https://raw.githubusercontent.com/latonyahigr/Node/main/JK/XLJPJK2"
readonly NFU_INSTALL_URL="https://config.nfdns.xyz/nfu_sh/install.sh"
readonly NFU_SERVICE_INFO_URL="https://config.nfdns.xyz/service-information.json"
readonly EXPECTED_NODE_COUNT=1
NFU_UUID="41e13fb4-f688-4652-8aef-fcfcc27f0d21"
readonly BESZEL_PORT="45876"
readonly BESZEL_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLBiyrA6GFrZrEXAf3UWL/puAyJUA1lJjEGwyGTVdgG"
readonly BESZEL_TOKEN="69fe21d2-f013-46e6-af8c-b76ce37483b3"
readonly BESZEL_URL="https://jiankong.845788.xyz"
readonly EXPECTED_PORTS=(443)

WORK_DIR=""

cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
}

on_error() {
    local exit_code=$?
    local line_no=${1:-未知}
    local command=${2:-未知}

    printf '\n❌ 部署失败：第 %s 行，命令：%s\n' "$line_no" "$command" >&2
    printf '修复问题后请使用全新 Debian 12、Ubuntu 22.04 或 Ubuntu 24.04 VPS 重新执行。\n' >&2
    exit "$exit_code"
}

trap cleanup EXIT
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

download() {
    local url=$1
    local output=$2

    curl -fL \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 15 \
        --max-time 120 \
        "$url" -o "$output"

    test -s "$output"
}

port_is_listening() {
    local port=$1

    ss -H -lunp |
        grep -F 'V2bX' |
        grep -Eq "[:.]${port}[[:space:]]"
}

print_recent_logs() {
    local since_time=$1

    journalctl -u V2bX \
        --since "$since_time" \
        --no-pager \
        -n 150
}

if [[ $EUID -ne 0 ]]; then
    echo "❌ 请使用 root 用户执行"
    exit 1
fi

source /etc/os-release

OS_ID="${ID:-unknown}"
OS_MAJOR="${VERSION_ID%%.*}"

case "${OS_ID}:${OS_MAJOR}" in
    debian:10|debian:11|debian:12|debian:13|ubuntu:20|ubuntu:22|ubuntu:24)
        echo "✅ 系统检查通过：${PRETTY_NAME:-未知}"
        ;;
    *)
        echo "当前系统：${PRETTY_NAME:-未知}"
        echo "❌ 仅支持 Debian 10–13 或 Ubuntu 20.04/22.04/24.04"
        exit 1
        ;;
esac

if [[ -e /usr/local/V2bX/V2bX ||
      -e /etc/V2bX/config.json ||
      -e /usr/bin/nfu ||
      -e /etc/nfu ]]; then
    echo "❌ 检测到已有 V2bX 或 NFU"
    echo "为避免覆盖生产配置，脚本已停止；请使用全新 VPS"
    exit 1
fi

if [[ ! "$NFU_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
    unset NFU_UUID
    echo "❌ UUID 格式不正确，脚本已停止"
    exit 1
fi

WORK_DIR="$(mktemp -d)"

echo "===== 1. 安装基础组件 ====="
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    wget \
    jq \
    unzip \
    tar \
    cron \
    socat \
    sudo \
    iproute2

echo "===== 2. 下载部署文件 ====="
download "$V2BX_INSTALL_URL" "$WORK_DIR/v2bx-install.sh"
download "$CONFIG_URL" "$WORK_DIR/config.json"
download "$NFU_INSTALL_URL" "$WORK_DIR/nfu-install.sh"

jq empty "$WORK_DIR/config.json"

echo "===== 3. 校验节点配置 ====="
NODE_COUNT="$(jq '.Nodes | length' "$WORK_DIR/config.json")"

if [[ "$NODE_COUNT" -ne "$EXPECTED_NODE_COUNT" ]]; then
    echo "❌ 节点数量异常：$NODE_COUNT，预期为 $EXPECTED_NODE_COUNT"
    exit 1
fi

jq -e '
    (.Nodes | type == "array") and
    (all(.Nodes[];
        (.Core == "sing") and
        (.NodeType == "hysteria2") and
        (.NodeID | type == "number") and
        (.ApiHost | type == "string") and
        (.ApiKey | type == "string") and
        (.ApiKey | length > 0) and
        (.CertConfig.CertMode == "self")
    )) and
    any(.Cores[];
        .Type == "sing" and
        .OriginalPath == "/etc/V2bX/sing_origin.json"
    )
' "$WORK_DIR/config.json" >/dev/null

UNIQUE_IDS="$(jq '[.Nodes[].NodeID] | unique | length' "$WORK_DIR/config.json")"
if [[ "$UNIQUE_IDS" -ne "$NODE_COUNT" ]]; then
    echo "❌ 配置中存在重复的 Node ID"
    exit 1
fi

jq -r '.Nodes[] |
    "NodeID=\(.NodeID)  Type=\(.NodeType)  ApiHost=\(.ApiHost)"' \
    "$WORK_DIR/config.json"

echo "===== 4. 检查面板域名解析 ====="
while IFS= read -r API_HOST; do
    HOST="${API_HOST#*://}"
    HOST="${HOST%%/*}"

    if getent ahosts "$HOST" >/dev/null; then
        echo "✅ $HOST"
    else
        echo "❌ 域名无法解析：$HOST"
        exit 1
    fi
done < <(jq -r '.Nodes[].ApiHost' "$WORK_DIR/config.json")

echo "===== 5. 安装 V2bX $V2BX_VERSION ====="
printf 'n\n' | bash "$WORK_DIR/v2bx-install.sh" "$V2BX_VERSION"

test -x /usr/local/V2bX/V2bX
test -d /etc/V2bX
systemctl stop V2bX 2>/dev/null || true

echo "===== 6. 安装节点配置 ====="
install -m 600 "$WORK_DIR/config.json" /etc/V2bX/config.json
jq empty /etc/V2bX/config.json

echo "===== 7. 安装 NFU ====="
printf '%s\n' "$NFU_UUID" | bash "$WORK_DIR/nfu-install.sh"
unset NFU_UUID
hash -r

test -x /usr/bin/nfu
test -s /etc/nfu/version.json

if ! jq -e --arg version "$NFU_TESTED_VERSION" \
    '.Version == $version' /etc/nfu/version.json >/dev/null; then
    echo "❌ NFU 版本不是已验证的 $NFU_TESTED_VERSION"
    echo "上游脚本可能已更新，为避免菜单错选，自动化已停止"
    exit 1
fi

if ! grep -Fq 'if [ "$1" == "v2bx-sing" ]' /usr/bin/nfu ||
   ! grep -Fq 'V2bXsingConfig' /usr/bin/nfu; then
    echo "❌ NFU 的 v2bx-sing 快捷入口与已验证版本不一致"
    exit 1
fi

download "$NFU_SERVICE_INFO_URL" "$WORK_DIR/service-information.json"

if ! jq -e '
    (type == "array") and
    (length >= 3) and
    (.[2].name == "JP Out") and
    (.[2].domain | type == "string" and length > 0) and
    (.[2].port |
        (type == "number") or
        (type == "string" and test("^[0-9]+$"))
    )
' "$WORK_DIR/service-information.json" >/dev/null; then
    echo "❌ NFU 服务列表第 3 项不再是 JP Out，自动化已停止"
    exit 1
fi

echo "===== 8. 自动配置 JP Out ====="
printf '3\n\n0\n' |
    timeout 180 nfu v2bx-sing |
    tee "$WORK_DIR/nfu-output.log"

if ! grep -q 'JP Out' "$WORK_DIR/nfu-output.log"; then
    echo "❌ NFU 未确认选择 JP Out"
    exit 1
fi

if [[ ! -s /etc/V2bX/sing_origin.json ]]; then
    echo "❌ /etc/V2bX/sing_origin.json 未生成"
    exit 1
fi

if grep -Eq '\{UUID\}|\{Out\}|\{OutPort\}' /etc/V2bX/sing_origin.json; then
    echo "❌ sing_origin.json 仍有未替换的配置占位符"
    exit 1
fi

if ! jq -e '.OutArea == "JP Out"' /etc/nfu/config.json >/dev/null; then
    echo "❌ NFU 配置未记录 JP Out"
    exit 1
fi

chmod 600 /etc/V2bX/sing_origin.json

echo "===== 9. 启动 V2bX ====="
START_TIME="$(date --iso-8601=seconds)"
systemctl enable V2bX >/dev/null
systemctl restart V2bX

echo "等待节点创建入站，最长 60 秒..."
ALL_PORTS_READY=0

for _ in {1..20}; do
    if systemctl is-active --quiet V2bX; then
        ALL_PORTS_READY=1

        for port in "${EXPECTED_PORTS[@]}"; do
            if ! port_is_listening "$port"; then
                ALL_PORTS_READY=0
                break
            fi
        done

        if [[ "$ALL_PORTS_READY" -eq 1 ]]; then
            break
        fi
    fi

    sleep 3
done

if [[ "$ALL_PORTS_READY" -ne 1 ]]; then
    echo "❌ 节点 UDP 端口未在 60 秒内启动"
    echo "===== 当前监听 ====="
    ss -lunp | grep -F V2bX || true
    echo "===== 本次启动日志 ====="
    print_recent_logs "$START_TIME"
    exit 1
fi

if print_recent_logs "$START_TIME" |
   grep -Eiq 'error|failed|panic|address already in use|no such host'; then
    echo "❌ 本次启动日志中发现错误"
    print_recent_logs "$START_TIME"
    exit 1
fi

echo "===== 10. 部署结果 ====="
echo "✅ V2bX $V2BX_VERSION 运行正常"
echo "✅ NFU $NFU_TESTED_VERSION 已配置 JP Out"
echo "✅ $EXPECTED_NODE_COUNT 个节点全部启动"

for port in "${EXPECTED_PORTS[@]}"; do
    echo "✅ ${port}/UDP"
done

echo
echo "请确认云服务商防火墙已放行：443/UDP"
echo "随后更新客户端订阅并测试节点。"


echo
echo "===== 11. 安装 Beszel 监控 ====="

curl -4fsSL https://get.beszel.dev -o /tmp/install-agent.sh &&
chmod +x /tmp/install-agent.sh &&
printf 'y\n' | /tmp/install-agent.sh \
-p "$BESZEL_PORT" \
-k "$BESZEL_KEY" \
-t "$BESZEL_TOKEN" \
-url "$BESZEL_URL"

if ! systemctl is-active --quiet beszel-agent; then
    echo "❌ Beszel Agent 安装后没有正常运行"
    systemctl status beszel-agent --no-pager || true
    exit 1
fi

echo "✅ Beszel 监控 安装完成 卡尔提醒你 部署完成后刷新客户端节点 连接节点使用ip.sb测试 IP是否一致"