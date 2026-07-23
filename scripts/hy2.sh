bash <<'AUTOMATION'
set -Eeuo pipefail

trap 'echo "❌ 阶段一失败：第 $LINENO 行，命令：$BASH_COMMAND"' ERR

if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 用户执行"
    exit 1
fi

source /etc/os-release

if [[ "${ID:-}" != "debian" || "${VERSION_ID%%.*}" != "12" ]]; then
    echo "当前系统：${PRETTY_NAME:-未知}"
    echo "本轮只验证 Debian 12，已停止"
    exit 1
fi

if [[ -e /usr/local/V2bX/V2bX || -e /etc/V2bX/config.json ]]; then
    echo "检测到已有 V2bX，不是干净环境。为避免覆盖，已停止"
    exit 1
fi

V2BX_VERSION="v0.4.0"
INSTALL_URL="https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh"
CONFIG_URL="https://raw.githubusercontent.com/latonyahigr/Node/main/CJJP4"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "===== 1. 安装基础组件 ====="
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl wget jq unzip tar cron socat

echo "===== 2. 下载部署文件 ====="
curl -fL --retry 3 --connect-timeout 15 \
    "$INSTALL_URL" -o "$WORK_DIR/v2bx-install.sh"

curl -fL --retry 3 --connect-timeout 15 \
    "$CONFIG_URL" -o "$WORK_DIR/config.json"

test -s "$WORK_DIR/v2bx-install.sh"
test -s "$WORK_DIR/config.json"
jq empty "$WORK_DIR/config.json"

echo "===== 3. 校验 CJJP4 配置 ====="
NODE_COUNT="$(jq '.Nodes | length' "$WORK_DIR/config.json")"

if [[ "$NODE_COUNT" -ne 3 ]]; then
    echo "CJJP4 节点数量异常：$NODE_COUNT，预期为 3"
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
        (.CertConfig.CertMode == "self")
    ))
' "$WORK_DIR/config.json" >/dev/null

jq -e '
    any(.Cores[];
        .Type == "sing" and
        .OriginalPath == "/etc/V2bX/sing_origin.json"
    )
' "$WORK_DIR/config.json" >/dev/null

UNIQUE_IDS="$(jq '[.Nodes[].NodeID] | unique | length' "$WORK_DIR/config.json")"

if [[ "$UNIQUE_IDS" -ne "$NODE_COUNT" ]]; then
    echo "CJJP4 存在重复 Node ID"
    exit 1
fi

echo "节点配置校验通过："
jq -r '.Nodes[] |
    "NodeID=\(.NodeID)  Type=\(.NodeType)  ApiHost=\(.ApiHost)"' \
    "$WORK_DIR/config.json"

echo "===== 4. 检查三个面板域名解析 ====="
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

echo "===== 5. 安装固定版本 V2bX ====="
printf 'n\n' | bash "$WORK_DIR/v2bx-install.sh" "$V2BX_VERSION"

test -x /usr/local/V2bX/V2bX
test -d /etc/V2bX
systemctl stop V2bX 2>/dev/null || true

echo "===== 6. 安装经过校验的 CJJP4 ====="
install -m 600 "$WORK_DIR/config.json" /etc/V2bX/config.json
jq empty /etc/V2bX/config.json

echo "===== 阶段一结果 ====="
/usr/local/V2bX/V2bX version 2>/dev/null || true

echo
echo "节点总数：$(jq '.Nodes | length' /etc/V2bX/config.json)"
echo "OriginalPath："
jq -r '.Cores[] | select(.Type == "sing") | .OriginalPath' \
    /etc/V2bX/config.json

if systemctl is-active --quiet V2bX; then
    echo "❌ V2bX 意外启动"
    exit 1
else
    echo "✅ V2bX 已安装，当前保持停止状态"
fi

echo
echo "✅ 阶段一通过：V2bX + CJJP4 自动部署完成"
echo "下一阶段：自动安装 NFU、生成 JP Out、启动并验收三个节点"
AUTOMATION
