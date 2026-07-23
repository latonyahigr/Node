
image(22).png
image(23).png
image(24).png
image(25).png
CJJP4这个是配置，公开的。我输入安装v2bx命令wget -N https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh && bash install.sh 具体流程如图， 我输入解锁命令bash <(curl -Ls https://config.nfdns.xyz/nfu_sh/install.sh)，具体流程看后面三张图。 你整理一下流程，然后看如何实现我的要求


粘贴的文本 (1)(1).txt
文档
V2bX 的官方安装脚本本身允许第一次安装时回答 n，跳过配置生成器。安装脚本源码，你说的这个办法我试过，但是不行。但是我还想按照你的建议尝试下。试试看。

不行，不停的弹出

验证通过，三个节点已全部正常启动：

8443/UDP

8080/UDP

27017/UDP

三个端口均由同一个 V2bX 进程监听

最近 5 分钟无错误或警告

三个 ApiHost 均已使用正确的新域名

说明新 VPS 的完整流程已经成功：

安装 V2bX v0.4.0
→ 安装 CJJP4
→ 安装 NFU
→ 选择 JP Out
→ 生成 sing_origin.json
→ 启动 V2bX
→ 三个节点全部上线
有一点需要修正：NFU 配置完成后曾把 V2bX 停止，因此最终自动化脚本必须主动执行：

systemctl restart V2bX
然后等待 20 秒，并强制检查三个 UDP 端口。只有三个端口全部出现，才显示部署成功。

当前这台新 VPS 已经可以投入使用。接下来可以把 NFU 阶段合并进 GitHub 的 hy2.sh，最终保留一次输入 NFU UUID，后面的 JP Out 选择、启动和验收全部自动完成。UUID 和面板 API Key 不应写死在公开仓库中。


好的。那你完善下这个脚本

思考了 2m 52s
已完善并保存最终版：hy2.sh

主要改进：

一次隐藏输入 NFU UUID，不写入脚本。

固定 V2bX v0.4.0。

自动安装 NFU，并仅允许已验证的 v1.0.4。

自动选择 JP Out 并退出菜单。

强制重启、启用 V2bX。

最长等待 60 秒。

强制验收 8443/UDP、8080/UDP、27017/UDP。

检查本次启动日志，发现 DNS、端口冲突等错误立即停止。

检测到旧 V2bX/NFU 时拒绝覆盖，只适用于全新 Debian 12。

把文件替换到 GitHub 的：

scripts/hy2.sh
然后在全新 VPS 执行：

bash <(curl -fsSL https://raw.githubusercontent.com/latonyahigr/Node/main/scripts/hy2.sh)
注意：CJJP4 如果包含真实 ApiKey，目前公开放在 GitHub 仍有泄露风险。脚本本身没有写入 UUID，但公开配置中的面板密钥也应该更换并改为私密保存。



--2026-07-23 07:06:16--  https://config.nfdns.xyz/nfu_sh/version.json
Resolving config.nfdns.xyz (config.nfdns.xyz)... 2606:4700:3032::6815:3b83, 2606:4700:3035::ac43:b1e7, 104.21.59.131, ...
Connecting to config.nfdns.xyz (config.nfdns.xyz)|2606:4700:3032::6815:3b83|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 27 [application/json]
Saving to: ‘/etc/nfu/version.json’

/etc/nfu/version.json 100%[=======================>]      27  --.-KB/s    in 0s      

2026-07-23 07:06:17 (16.2 MB/s) - ‘/etc/nfu/version.json’ saved [27/27]

--2026-07-23 07:06:17--  https://config.nfdns.xyz/nfu_sh/nfu.sh
Resolving config.nfdns.xyz (config.nfdns.xyz)... 2606:4700:3032::6815:3b83, 2606:4700:3035::ac43:b1e7, 104.21.59.131, ...
Connecting to config.nfdns.xyz (config.nfdns.xyz)|2606:4700:3032::6815:3b83|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 12571 (12K) [application/octet-stream]
Saving to: ‘/usr/bin/nfu’

/usr/bin/nfu          100%[=======================>]  12.28K  --.-KB/s    in 0s      

2026-07-23 07:06:17 (27.5 MB/s) - ‘/usr/bin/nfu’ saved [12571/12571]


nfu v1.0.4 管理脚本使用方法: 
------------------------------------------
nfu                    - 显示管理菜单 (功能更多)
nfu update             - 升级 nfu 脚本
nfu xrayr              - 快速配置 XrayR
nfu soga               - 快速配置 soga
nfu x-ui               - 快速配置 x-ui
nfu V2bX (xray)        - 快速配置 V2bX (xray)
nfu V2bX (sing)        - 快速配置 V2bX (sing)
------------------------------------------
❌ NFU 菜单结构与已验证版本不一致，自动化已停止
root@localhost:~#   有这个提示，怎么办，可以忽略版本吗？关于选项应该不会变

思考了 2m 21s
可以继续，但不是“忽略版本”。NFU 确实是已验证的 v1.0.4，报错来自脚本中的错误检查：

JP Out 不在 /usr/bin/nfu 中。

它由 NFU 运行时从远程服务列表读取。

因此脚本把正常结构误判成了异常。

当前 VPS 不要重新运行完整脚本，会因检测到已安装 V2bX/NFU 而停止。直接继续执行：

bash <<'EOF'
set -Eeuo pipefail

[[ "$(jq -r '.Version' /etc/nfu/version.json)" == "v1.0.4" ]]

wget -qO /tmp/service-information.json \
  https://config.nfdns.xyz/service-information.json

jq -e '.[2].name == "JP Out"' \
  /tmp/service-information.json >/dev/null

echo "✅ 已确认第 3 项仍为 JP Out"

printf '3\n\n0\n' | timeout 180 nfu v2bx-sing

test -s /etc/V2bX/sing_origin.json

systemctl enable V2bX >/dev/null
systemctl restart V2bX
sleep 25

systemctl is-active --quiet V2bX

for PORT in 8443 8080 27017; do
  ss -H -lunp |
    grep -F V2bX |
    grep -Eq "[:.]${PORT}[[:space:]]" ||
    {
      echo "❌ ${PORT}/UDP 未监听"
      exit 1
    }

  echo "✅ ${PORT}/UDP"
done

echo "✅ JP Out 配置和三个节点均已启动"
EOF
我也修正了最终脚本：

保留 NFU 版本校验。

动态确认服务列表第 3 项确实是 JP Out。

修正自动输入为 3 → 空回车确认 → 0。

增加 180 秒超时和配置结果检查。

修正版：hy2.sh

用它替换 GitHub 的 scripts/hy2.sh。不能简单假定选项永远不变，因为服务列表可以在 NFU 版本不变时单独更新。


库
/
技术问题
/
hy2.sh


#!/usr/bin/env bash
set -Eeuo pipefail

readonly V2BX_VERSION="v0.4.0"
readonly NFU_TESTED_VERSION="v1.0.4"
readonly V2BX_INSTALL_URL="https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh"
readonly CONFIG_URL="https://raw.githubusercontent.com/latonyahigr/Node/main/CJJP4"
readonly NFU_INSTALL_URL="https://config.nfdns.xyz/nfu_sh/install.sh"
readonly NFU_SERVICE_INFO_URL="https://config.nfdns.xyz/service-information.json"
readonly EXPECTED_NODE_COUNT=3
readonly EXPECTED_PORTS=(8443 8080 27017)

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
    printf '修复问题后请使用一台全新 Debian 12 VPS 重新执行。\n' >&2
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

if [[ "${ID:-}" != "debian" || "${VERSION_ID%%.*}" != "12" ]]; then
    echo "当前系统：${PRETTY_NAME:-未知}"
    echo "❌ 本脚本只允许在全新 Debian 12 VPS 上运行"
    exit 1
fi

if [[ -e /usr/local/V2bX/V2bX ||
      -e /etc/V2bX/config.json ||
      -e /usr/bin/nfu ||
      -e /etc/nfu ]]; then
    echo "❌ 检测到已有 V2bX 或 NFU"
    echo "为避免覆盖生产配置，脚本已停止；请使用全新 VPS"
    exit 1
fi

if [[ ! -t 0 ]]; then
    echo "❌ 当前没有交互终端，无法安全读取 NFU UUID"
    echo "请使用下面的方式运行："
    echo "bash <(curl -fsSL https://raw.githubusercontent.com/latonyahigr/Node/main/scripts/hy2.sh)"
    exit 1
fi

read -rsp "请输入 NFU UUID（输入内容不会显示）: " NFU_UUID
echo

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

echo "等待三个节点创建入站，最长 60 秒..."
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
    echo "❌ 三个 UDP 端口未在 60 秒内全部启动"
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
echo "请确认云服务商防火墙已放行：8443/UDP、8080/UDP、27017/UDP"
echo "随后更新客户端订阅并逐个测试三个节点。"
库
/
技术问题
/
hy2.sh


#!/usr/bin/env bash
set -Eeuo pipefail

readonly V2BX_VERSION="v0.4.0"
readonly NFU_TESTED_VERSION="v1.0.4"
readonly V2BX_INSTALL_URL="https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh"
readonly CONFIG_URL="https://raw.githubusercontent.com/latonyahigr/Node/main/CJJP4"
readonly NFU_INSTALL_URL="https://config.nfdns.xyz/nfu_sh/install.sh"
readonly NFU_SERVICE_INFO_URL="https://config.nfdns.xyz/service-information.json"
readonly EXPECTED_NODE_COUNT=3
readonly EXPECTED_PORTS=(8443 8080 27017)

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
    printf '修复问题后请使用一台全新 Debian 12 VPS 重新执行。\n' >&2
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

if [[ "${ID:-}" != "debian" || "${VERSION_ID%%.*}" != "12" ]]; then
    echo "当前系统：${PRETTY_NAME:-未知}"
    echo "❌ 本脚本只允许在全新 Debian 12 VPS 上运行"
    exit 1
fi

if [[ -e /usr/local/V2bX/V2bX ||
      -e /etc/V2bX/config.json ||
      -e /usr/bin/nfu ||
      -e /etc/nfu ]]; then
    echo "❌ 检测到已有 V2bX 或 NFU"
    echo "为避免覆盖生产配置，脚本已停止；请使用全新 VPS"
    exit 1
fi

if [[ ! -t 0 ]]; then
    echo "❌ 当前没有交互终端，无法安全读取 NFU UUID"
    echo "请使用下面的方式运行："
    echo "bash <(curl -fsSL https://raw.githubusercontent.com/latonyahigr/Node/main/scripts/hy2.sh)"
    exit 1
fi

read -rsp "请输入 NFU UUID（输入内容不会显示）: " NFU_UUID
echo

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

echo "等待三个节点创建入站，最长 60 秒..."
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
    echo "❌ 三个 UDP 端口未在 60 秒内全部启动"
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
echo "请确认云服务商防火墙已放行：8443/UDP、8080/UDP、27017/UDP"
echo "随后更新客户端订阅并逐个测试三个节点。"
