#!/usr/bin/env bash
# ==========================================================
# Cloudflare DDNS - cfautochangeip_awssg.sh
#
# 单文件版：
#   1. 直接执行 ./cfautochangeip_awssg.sh = 自动安装 / 覆盖 / 重启服务
#   2. 安装后执行 txcfddns = 打开管理面板
#   3. CF_API_TOKEN / ZONE_ID 已内置在本文件；默认以脚本内置值为准
#   4. 主域名已改为 894454.xyz，子域名保留 awssg1 / awssg1-v6，并新增 awssg1v4v6 双栈合并记录
#   5. 已删除旧版云解析 API 签名逻辑，全部改为 Cloudflare API v4
# ==========================================================

if [ -z "${BASH_VERSION:-}" ]; then
  echo "错误：请用 bash 执行，不要用 sh。"
  exit 2
fi

set -u
set -o pipefail
umask 077

# ================== 内置配置区 ==================
# 你要求单文件使用，所以 Cloudflare API Token 和 Zone ID 直接写在这里。
# 当前按你的要求使用脚本内置值；配置文件只作为脚本内置值为空时的备用。
# 已内置 Cloudflare Zone ID；有 Zone ID 时不需要再调用 /zones?name= 自动查询。
# 本版额外维护 awssg1v4v6.894454.xyz 的 A + AAAA 合并双栈解析。

SCRIPT_CF_API_TOKEN="cfut_7rdFRfP6nfFcsZ4VA4C3pJpmDjvhybCjGocnL8DO70c2b845"
SCRIPT_ZONE_ID="1c9f9461ebf0bed6b7e02874d37a8d30"

# 已固定 894454.xyz 的 Cloudflare Zone ID；不再依赖自动查询 Zone。
# ddnsgo 不要求手动填 Zone ID，是因为程序内部会自动查询/匹配；Cloudflare DNS API 本身仍然按 zone_id 管理 DNS 记录。

CONFIG_FILE="/etc/txcfddns/cfddns.conf"

# 只读取新的 Cloudflare 专用配置文件，避免旧配置污染。
if [ -r "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE" 2>/dev/null || true
fi

CF_API_TOKEN="${SCRIPT_CF_API_TOKEN:-${CF_API_TOKEN:-}}"
ZONE_ID="${SCRIPT_ZONE_ID:-${ZONE_ID:-}}"

DOMAIN="${DOMAIN:-894454.xyz}"
SUB_DOMAIN="${SUB_DOMAIN:-awssg1}"
FULL_DOMAIN="${SUB_DOMAIN}.${DOMAIN}"

RECORD_TYPE="${RECORD_TYPE:-A}"
RECORD_COMMENT="${RECORD_COMMENT:-awssg1}"

# IPv6 备用测试记录：默认更新 awssg1-v6.894454.xyz 的 AAAA 记录。
# 若机器没有 IPv6 出口，只会记录日志并跳过，不影响 awssg1 IPv4。
V6_ENABLE="${V6_ENABLE:-1}"
V6_SUB_DOMAIN="${V6_SUB_DOMAIN:-awssg1-v6}"
V6_FULL_DOMAIN="${V6_SUB_DOMAIN}.${DOMAIN}"
V6_RECORD_TYPE="${V6_RECORD_TYPE:-AAAA}"
V6_RECORD_COMMENT="${V6_RECORD_COMMENT:-awssg1-v6}"
# 可选：指定优先读取 IPv6 的网卡，例如 eth0。留空则自动扫描所有网卡。
V6_INTERFACE="${V6_INTERFACE:-}"

# IPv4 + IPv6 合并双栈记录：默认同时维护 awssg1v4v6.894454.xyz 的 A 和 AAAA。
# A 记录使用当前公网 IPv4；AAAA 记录使用当前公网 IPv6。
MERGED_ENABLE="${MERGED_ENABLE:-1}"
MERGED_SUB_DOMAIN="${MERGED_SUB_DOMAIN:-awssg1v4v6}"
MERGED_FULL_DOMAIN="${MERGED_SUB_DOMAIN}.${DOMAIN}"
MERGED_A_RECORD_TYPE="${MERGED_A_RECORD_TYPE:-A}"
MERGED_AAAA_RECORD_TYPE="${MERGED_AAAA_RECORD_TYPE:-AAAA}"
MERGED_A_RECORD_COMMENT="${MERGED_A_RECORD_COMMENT:-awssg1v4v6-A}"
MERGED_AAAA_RECORD_COMMENT="${MERGED_AAAA_RECORD_COMMENT:-awssg1v4v6-AAAA}"

# Cloudflare TTL：1 表示自动；A/AAAA 非代理记录通常可用 60 秒。
TTL="${TTL:-60}"

# 是否开启 Cloudflare 代理。DDNS 默认 false，避免 IP 被 Cloudflare 代理状态影响。
CF_PROXIED="${CF_PROXIED:-false}"

# 后台守护模式下，每隔多少秒执行一次 DDNS。
# 60 = 1 分钟；如需每 5 分钟检测一次，请改成 300。
894454.xyz

# 执行失败后，多少秒后重试。
RETRY_SLEEP="${RETRY_SLEEP:-60}"

# Cloudflare API 超时配置。
API_CONNECT_TIMEOUT="${API_CONNECT_TIMEOUT:-3}"
API_MAX_TIME="${API_MAX_TIME:-10}"

# ================== 固定安装配置 ==================

INSTALL_PATH="/usr/local/sbin/cfautochangeip_awssg.sh"
UNIT_NAME="txcfddns.service"
UNIT_PATH="/etc/systemd/system/${UNIT_NAME}"

PANEL_CMD="txcfddns"
PANEL_PATH="/usr/local/bin/${PANEL_CMD}"

LOG_DIR="/var/log/txcfddns"
LOG_FILE="${LOG_DIR}/txcfddns.log"

CF_API_BASE="https://api.cloudflare.com/client/v4"

# ==========================================================

mkdir -p "$LOG_DIR" 2>/dev/null || true

log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

print_log() {
  echo "$*"
  log "$*"
}

need_cmds() {
  local c missing=0

  for c in bash curl awk sed tr date grep head tail mkdir cat id install chmod ps rm sleep kill; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "缺少命令：$c"
      log "缺少命令：$c"
      missing=1
    fi
  done

  return "$missing"
}

has_systemd() {
  command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

script_path() {
  local src="${BASH_SOURCE[0]}"

  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$src" 2>/dev/null && return 0
  fi

  cd "$(dirname "$src")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$src")"
}

SCRIPT_PATH="$(script_path)"

mask_value() {
  local v="${1:-}"
  local len="${#v}"

  if [ "$len" -le 8 ]; then
    printf '已填写'
  else
    printf '%s****%s' "${v:0:6}" "${v: -4}"
  fi
}

token_ready() {
  [ -n "${CF_API_TOKEN:-}" ]
}

is_ipv4() {
  local ip="$1" IFS=. a b c d x

  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  read -r a b c d <<< "$ip"

  for x in "$a" "$b" "$c" "$d"; do
    [[ "$x" =~ ^[0-9]+$ ]] || return 1
    [ "$x" -ge 0 ] 2>/dev/null && [ "$x" -le 255 ] 2>/dev/null || return 1
  done

  return 0
}

is_ipv6() {
  local ip="$1" lower without_double double_count part nonempty=0
  local first first_dec
  local -a parts

  ip="${ip#[}"
  ip="${ip%]}"

  case "$ip" in
    *%*) ip="${ip%%\%*}" ;;
  esac

  [ -n "$ip" ] || return 1
  [[ "$ip" == *:* ]] || return 1
  [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ "$ip" == *:::* ]] && return 1

  without_double="${ip//::/}"
  double_count=$(( (${#ip} - ${#without_double}) / 2 ))
  [ "$double_count" -le 1 ] || return 1

  lower="$(printf '%s' "$ip" | tr '[:upper:]' '[:lower:]')"

  IFS=':' read -r -a parts <<< "$lower"
  for part in "${parts[@]}"; do
    [ -n "$part" ] || continue
    [[ "$part" =~ ^[0-9a-f]{1,4}$ ]] || return 1
    nonempty=$((nonempty + 1))
  done

  if [[ "$lower" == *::* ]]; then
    [ "$nonempty" -le 7 ] || return 1
  else
    [ "$nonempty" -eq 8 ] || return 1
  fi

  # 只接受公网全局单播 IPv6：2000::/3。
  # 这样可以排除 ULA 内网、链路本地、回环、组播、文档/测试地址等。
  first="${lower%%:*}"
  [[ "$first" =~ ^[0-9a-f]{1,4}$ ]] || return 1
  first_dec=$((16#$first))
  [ "$first_dec" -ge $((16#2000)) ] && [ "$first_dec" -le $((16#3fff)) ] || return 1

  case "$lower" in
    2001:db8:*|3fff:*)
      return 1
      ;;
  esac

  return 0
}

extract_ipv6_candidate() {
  local text="$1" candidates candidate

  candidates="$(printf '%s\n' "$text" | grep -Eo '([0-9A-Fa-f]{0,4}:){2,}[0-9A-Fa-f:]{0,4}' || true)"

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if is_ipv6 "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done <<< "$candidates"

  return 1
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_bool() {
  case "${1:-false}" in
    1|yes|YES|true|TRUE|on|ON)
      printf 'true'
      ;;
    *)
      printf 'false'
      ;;
  esac
}

cf_error_summary() {
  local response="$1" msg

  msg="$(printf '%s' "$response" | grep -oE '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 3 | sed 's/^"message"[[:space:]]*:[[:space:]]*"//; s/"$//' | tr '\n' '; ')"
  [ -n "$msg" ] && printf '%s' "$msg" || printf '%s' "$response" | head -c 300
}

cf_api_raw() {
  local method="$1" endpoint="$2" payload="${3:-}"
  local response

  if [ -n "$payload" ]; then
    response="$(curl -sS \
      --connect-timeout "$API_CONNECT_TIMEOUT" \
      --max-time "$API_MAX_TIME" \
      -X "$method" "${CF_API_BASE}${endpoint}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$payload" 2>/dev/null)" || {
        print_log "Cloudflare API 请求失败：${method} ${endpoint}"
        return 1
      }
  else
    response="$(curl -sS \
      --connect-timeout "$API_CONNECT_TIMEOUT" \
      --max-time "$API_MAX_TIME" \
      -X "$method" "${CF_API_BASE}${endpoint}" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" 2>/dev/null)" || {
        print_log "Cloudflare API 请求失败：${method} ${endpoint}"
        return 1
      }
  fi

  printf '%s' "$response"
}

cf_api() {
  local method="$1" endpoint="$2" payload="${3:-}"
  local response errmsg

  response="$(cf_api_raw "$method" "$endpoint" "$payload")" || return 1

  if ! printf '%s' "$response" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
    errmsg="$(cf_error_summary "$response")"
    print_log "Cloudflare API 返回错误：${method} ${endpoint}${errmsg:+ | $errmsg}"
    return 1
  fi

  printf '%s' "$response"
}

extract_first_id() {
  local response="$1" id

  id="$(printf '%s' "$response" | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | sed 's/^"id"[[:space:]]*:[[:space:]]*"//; s/"$//')"
  [ -n "$id" ] && printf '%s' "$id"
}

extract_first_content() {
  local response="$1" content

  content="$(printf '%s' "$response" | grep -oE '"content"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/^"content"[[:space:]]*:[[:space:]]*"//; s/"$//')"
  [ -n "$content" ] && printf '%s' "$content"
}

is_record_exists_error() {
  local response="$1"

  printf '%s' "$response" | grep -qiE 'already exists|record.*exist|81057|同名|已经存在'
}

get_zone_id() {
  local response zid

  if [ -n "${ZONE_ID:-}" ]; then
    printf '%s' "$ZONE_ID"
    return 0
  fi

  response="$(cf_api "GET" "/zones?name=$(json_escape "$DOMAIN")&page=1&per_page=1")" || return 1
  zid="$(extract_first_id "$response")"

  if [ -z "$zid" ]; then
    print_log "错误：无法获取 Cloudflare Zone ID：${DOMAIN}"
    print_log "请确认 894454.xyz 已加入 Cloudflare；如果未内置 Zone ID，Token 需要 Zone:Read；已内置 Zone ID 时主要需要 DNS:Edit。"
    return 1
  fi

  printf '%s' "$zid"
}

record_payload() {
  local name="$1" type="$2" content="$3" comment="$4"

  printf '{"type":"%s","name":"%s","content":"%s","ttl":%s,"proxied":%s,"comment":"%s"}' \
    "$(json_escape "$type")" \
    "$(json_escape "$name")" \
    "$(json_escape "$content")" \
    "$TTL" \
    "$(json_bool "$CF_PROXIED")" \
    "$(json_escape "$comment")"
}

describe_record_id() {
  local name="$1" type="$2"
  local zid response rid

  zid="$(get_zone_id)" || return 1
  response="$(cf_api "GET" "/zones/${zid}/dns_records?type=$(json_escape "$type")&name=$(json_escape "$name")&page=1&per_page=100")" || return 1
  rid="$(extract_first_id "$response")"

  [ -n "$rid" ] || return 1
  printf '%s' "$rid"
}

get_record_content() {
  local name="$1" type="$2"
  local zid response content

  zid="$(get_zone_id)" || return 1
  response="$(cf_api "GET" "/zones/${zid}/dns_records?type=$(json_escape "$type")&name=$(json_escape "$name")&page=1&per_page=1")" || return 1
  content="$(extract_first_content "$response")"

  [ -n "$content" ] || return 1
  printf '%s' "$content"
}

create_record() {
  local name="$1" type="$2" comment="$3" ip="$4"
  local zid payload response rid

  zid="$(get_zone_id)" || return 1
  payload="$(record_payload "$name" "$type" "$ip" "$comment")"
  response="$(cf_api_raw "POST" "/zones/${zid}/dns_records" "$payload")" || return 1

  if ! printf '%s' "$response" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
    print_log "Cloudflare API 返回错误：Create DNS Record | $(cf_error_summary "$response")"

    if is_record_exists_error "$response"; then
      print_log "记录已存在，改为重新查询 Record ID 后更新。"
      if rid="$(describe_record_id "$name" "$type" 2>/dev/null)"; then
        print_log "重新查询到已有记录：${name}，Record ID=${rid}"
        modify_record "$rid" "$name" "$type" "$comment" "$ip"
        return $?
      fi
      print_log "记录存在但仍无法查询到 Record ID，请检查记录类型/子域名是否一致。"
    fi

    return 1
  fi

  rid="$(extract_first_id "$response")"

  if [ -z "$rid" ]; then
    print_log "创建失败：Cloudflare 没有返回 Record ID"
    return 1
  fi

  print_log "已创建记录：${name}"
  print_log "类型：${type}"
  print_log "备注：${comment}"
  print_log "TTL：${TTL}"
  print_log "代理：$(json_bool "$CF_PROXIED")"
  print_log "IP：${ip}"
  print_log "Record ID：${rid}"
}

modify_record() {
  local rid="$1" name="$2" type="$3" comment="$4" ip="$5"
  local zid payload current

  zid="$(get_zone_id)" || return 1

  current="$(get_record_content "$name" "$type" 2>/dev/null || true)"
  if [ -n "$current" ] && [ "$current" = "$ip" ]; then
    print_log "无需更新：${name} 当前已是 ${ip}"
    return 0
  fi

  payload="$(record_payload "$name" "$type" "$ip" "$comment")"
  cf_api "PATCH" "/zones/${zid}/dns_records/${rid}" "$payload" >/dev/null || return 1

  print_log "更新成功：${name}"
  print_log "类型：${type}"
  print_log "备注：${comment}"
  print_log "TTL：${TTL}"
  print_log "代理：$(json_bool "$CF_PROXIED")"
  print_log "IP：${ip}"
  print_log "Record ID：${rid}"
}

update_dns_record() {
  local sub_domain="$1"
  local record_type="$2"
  local record_comment="$3"
  local ip="$4"
  local full_name="${sub_domain}.${DOMAIN}"
  local rid

  if rid="$(describe_record_id "$full_name" "$record_type" 2>/dev/null)"; then
    print_log "找到已有记录：${full_name}，Record ID=${rid}"
    modify_record "$rid" "$full_name" "$record_type" "$record_comment" "$ip" || return 1
  else
    print_log "没有找到记录，准备创建：${full_name}"
    create_record "$full_name" "$record_type" "$record_comment" "$ip" || return 1
  fi
}

get_public_ipv4() {
  local ip url

  for url in \
    "https://api.ipify.org" \
    "https://checkip.amazonaws.com" \
    "https://ifconfig.me/ip" \
    "https://ipv4.icanhazip.com"
  do
    ip="$(curl -4 -fsS --connect-timeout 2 --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)"

    if [ -n "$ip" ] && is_ipv4 "$ip" && [[ ! "$ip" =~ ^127\. ]]; then
      printf '%s' "$ip"
      return 0
    fi
  done

  return 1
}

get_public_ipv6_from_interface() {
  local lines line ip pass source_desc

  command -v ip >/dev/null 2>&1 || return 1

  if [ -n "${V6_INTERFACE:-}" ]; then
    source_desc="${V6_INTERFACE}"
    lines="$(ip -o -6 addr show dev "$V6_INTERFACE" scope global 2>/dev/null || true)"
  else
    source_desc="所有网卡"
    lines="$(ip -o -6 addr show scope global 2>/dev/null || true)"
  fi

  [ -n "$lines" ] || return 1

  # 第一轮优先稳定公网 IPv6；如果只有 temporary 地址，第二轮再兜底使用。
  for pass in stable temporary; do
    while IFS= read -r line; do
      [ -n "$line" ] || continue

      case " $line " in
        *" tentative "*|*" dadfailed "*|*" deprecated "*)
          continue
          ;;
      esac

      if [ "$pass" = "stable" ]; then
        case " $line " in
          *" temporary "*) continue ;;
        esac
      else
        case " $line " in
          *" temporary "*) : ;;
          *) continue ;;
        esac
      fi

      ip="$(printf '%s\n' "$line" | awk '{for (i=1;i<=NF;i++) if ($i=="inet6") {print $(i+1); exit}}' | sed 's#/.*##')"

      if [ -n "$ip" ] && is_ipv6 "$ip"; then
        log "网卡 IPv6 检测成功：${ip}（来源：${source_desc}，模式：${pass}）"
        printf '%s' "$ip"
        return 0
      fi
    done <<< "$lines"
  done

  return 1
}

get_public_ipv6_from_api() {
  local body ip url

  for url in \
    "https://speed.neu6.edu.cn/getIP.php" \
    "https://v6.ident.me" \
    "https://6.ipw.cn" \
    "https://v6.yinghualuo.cn/bejson"
  do
    body="$(curl -6 -fsS --connect-timeout 2 --max-time 5 "$url" 2>/dev/null || true)"
    ip="$(extract_ipv6_candidate "$body" || true)"

    if [ -n "$ip" ] && is_ipv6 "$ip"; then
      log "API IPv6 检测成功：${ip}（来源：${url}）"
      printf '%s' "$ip"
      return 0
    fi
  done

  return 1
}

get_public_ipv6() {
  local ip

  ip="$(get_public_ipv6_from_interface 2>/dev/null || true)"
  if [ -n "$ip" ] && is_ipv6 "$ip"; then
    printf '%s' "$ip"
    return 0
  fi

  ip="$(get_public_ipv6_from_api 2>/dev/null || true)"
  if [ -n "$ip" ] && is_ipv6 "$ip"; then
    printf '%s' "$ip"
    return 0
  fi

  return 1
}

run_once() {
  local ip4 ip6 zid

  need_cmds || return 1

  if ! token_ready; then
    print_log "错误：CF_API_TOKEN 为空"
    return 1
  fi

  zid="$(get_zone_id)" || return 1
  log "Cloudflare Zone ID：${zid}"

  print_log "正在获取公网 IPv4..."

  ip4="$(get_public_ipv4)" || {
    print_log "错误：无法获取公网 IPv4"
    return 1
  }

  print_log "当前公网 IPv4：${ip4}"
  update_dns_record "$SUB_DOMAIN" "$RECORD_TYPE" "$RECORD_COMMENT" "$ip4" || return 1

  case "${MERGED_ENABLE:-1}" in
    1|yes|YES|true|TRUE|on|ON)
      print_log "正在更新合并双栈记录 IPv4：${MERGED_FULL_DOMAIN} ${MERGED_A_RECORD_TYPE}"
      update_dns_record "$MERGED_SUB_DOMAIN" "$MERGED_A_RECORD_TYPE" "$MERGED_A_RECORD_COMMENT" "$ip4" || return 1
      ;;
    *)
      print_log "合并双栈记录已禁用，跳过 IPv4：${MERGED_FULL_DOMAIN}"
      ;;
  esac

  case "${V6_ENABLE:-1}" in
    1|yes|YES|true|TRUE|on|ON)
      if [ -n "${V6_INTERFACE:-}" ]; then
        print_log "正在获取公网 IPv6，优先检查网卡：${V6_INTERFACE}，失败后再用 API..."
      else
        print_log "正在获取公网 IPv6，优先检查本机网卡，失败后再用 API..."
      fi

      if ip6="$(get_public_ipv6)"; then
        print_log "当前公网 IPv6：${ip6}"
        update_dns_record "$V6_SUB_DOMAIN" "$V6_RECORD_TYPE" "$V6_RECORD_COMMENT" "$ip6" \
          || print_log "警告：IPv6 备用记录更新失败：${V6_FULL_DOMAIN}"

        case "${MERGED_ENABLE:-1}" in
          1|yes|YES|true|TRUE|on|ON)
            print_log "正在更新合并双栈记录 IPv6：${MERGED_FULL_DOMAIN} ${MERGED_AAAA_RECORD_TYPE}"
            update_dns_record "$MERGED_SUB_DOMAIN" "$MERGED_AAAA_RECORD_TYPE" "$MERGED_AAAA_RECORD_COMMENT" "$ip6" \
              || print_log "警告：合并双栈 AAAA 记录更新失败：${MERGED_FULL_DOMAIN}"
            ;;
          *)
            print_log "合并双栈记录已禁用，跳过 IPv6：${MERGED_FULL_DOMAIN}"
            ;;
        esac
      else
        print_log "未获取到公网 IPv6，跳过备用 IPv6 记录：${V6_FULL_DOMAIN}"
        case "${MERGED_ENABLE:-1}" in
          1|yes|YES|true|TRUE|on|ON)
            print_log "未获取到公网 IPv6，跳过合并双栈 AAAA 记录：${MERGED_FULL_DOMAIN}"
            ;;
        esac
      fi
      ;;
    *)
      print_log "IPv6 备用记录已禁用：${V6_FULL_DOMAIN}"
      ;;
  esac

  print_log "本轮 DDNS 完成。主记录：${FULL_DOMAIN}；IPv6备用：${V6_FULL_DOMAIN}；合并双栈：${MERGED_FULL_DOMAIN}"
}

daemon_loop() {
  print_log "Cloudflare DDNS 后台守护启动"
  print_log "主记录：${FULL_DOMAIN}"
  print_log "IPv6备用：${V6_FULL_DOMAIN}"
  print_log "合并双栈：${MERGED_FULL_DOMAIN}"
  print_log "成功间隔：${CHECK_INTERVAL}s"
  print_log "失败重试：${RETRY_SLEEP}s"

  while true; do
    if run_once; then
      sleep "$CHECK_INTERVAL" || true
    else
      print_log "本轮失败，${RETRY_SLEEP}s 后重试"
      sleep "$RETRY_SLEEP" || true
    fi
  done
}

disable_legacy_txcfddns_services() {
  if ! has_systemd; then
    return 0
  fi

  systemctl list-units --type=service --all --no-legend \
    | awk '{print $1}' \
    | grep -Ei 'txcfddns|cfddns|cloudflare|ddns' \
    | grep -v "^${UNIT_NAME}$" \
    | while read -r svc; do
        [ -n "$svc" ] || continue
        echo "停止并禁用旧服务：$svc"
        systemctl disable --now "$svc" >/dev/null 2>&1 || true
      done
}

kill_legacy_ddns_processes() {
  local pids pid

  # 清理旧版非 systemd 后台进程，例如 txcfddns-* / /root/.txcfddns-*。
  # 不杀当前脚本自己。
  pids="$(ps -eo pid=,args= 2>/dev/null | awk -v self="$$" -v install_path="$INSTALL_PATH" '
    {
      pid=$1
      $1=""
    }
    pid == self { next }
    index($0, install_path " daemon") { print pid; next }
    index($0, "txcfddns-") { print pid; next }
    index($0, "/root/.txcfddns-") { print pid; next }
  ')"

  [ -n "$pids" ] || return 0

  echo "发现旧版 DDNS 后台进程，准备停止：$pids"
  for pid in $pids; do
    kill "$pid" 2>/dev/null || true
  done
  sleep 1
  for pid in $pids; do
    kill -9 "$pid" 2>/dev/null || true
  done
}

cleanup_legacy_shortcuts() {
  local f

  for f in /usr/local/bin/txcfddns-* /usr/local/sbin/txcfddns-* /usr/local/bin/cfddns-* /usr/local/sbin/cfddns-*; do
    [ -e "$f" ] || continue
    [ "$f" = "$PANEL_PATH" ] && continue
    [ "$f" = "$INSTALL_PATH" ] && continue
    echo "删除旧快捷命令：$f"
    rm -f "$f" 2>/dev/null || true
  done
}

preinstall_cleanup() {
  if has_systemd; then
    echo "停止旧服务：${UNIT_NAME}"
    systemctl stop "$UNIT_NAME" >/dev/null 2>&1 || true
  fi

  # 安装/覆盖时只处理当前脚本自己的服务，不自动停止或删除其他 DDNS。
  # 如确认需要清理旧服务，可安装后在管理面板中手动选择第 10 项。
}

install_service() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "install 需要 root 权限，请用 root 或 sudo 执行。"
    return 1
  fi

  if ! has_systemd; then
    echo "当前系统没有可用 systemd，无法安装开机自启。"
    return 1
  fi

  need_cmds || return 1

  echo "开始安装/覆盖：${FULL_DOMAIN} + ${V6_FULL_DOMAIN} + ${MERGED_FULL_DOMAIN}"
  echo "当前脚本：${SCRIPT_PATH}"
  echo "安装路径：${INSTALL_PATH}"

  preinstall_cleanup

  install -d -m 755 /usr/local/sbin /usr/local/bin
  install -d -m 755 "$LOG_DIR"

  if [ "$SCRIPT_PATH" != "$INSTALL_PATH" ]; then
    install -m 700 "$SCRIPT_PATH" "$INSTALL_PATH"
  else
    chmod 700 "$INSTALL_PATH"
  fi

  cat > "$UNIT_PATH" <<UNIT
[Unit]
Description=Cloudflare DDNS ${FULL_DOMAIN} + ${V6_FULL_DOMAIN} + ${MERGED_FULL_DOMAIN}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash ${INSTALL_PATH} daemon
Restart=always
RestartSec=5
TimeoutStopSec=10
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
UNIT

  cat > "$PANEL_PATH" <<PANEL
#!/usr/bin/env bash
if [ "\$#" -eq 0 ]; then
  exec /bin/bash ${INSTALL_PATH} menu
else
  exec /bin/bash ${INSTALL_PATH} "\$@"
fi
PANEL

  chmod 755 "$PANEL_PATH"

  systemctl daemon-reload
  systemctl enable "$UNIT_NAME" >/dev/null 2>&1

  if token_ready; then
    systemctl restart "$UNIT_NAME"
    echo "后台运行：已重启"
  else
    echo "后台运行：未启动，因为 CF_API_TOKEN 未填写"
  fi

  echo "安装完成 / 已覆盖：${UNIT_NAME}"
  echo "开机自启：已启用"
  echo "崩溃重启：Restart=always"
  echo "面板命令：${PANEL_CMD}"
  echo
  echo "以后直接输入下面命令打开面板："
  echo "  ${PANEL_CMD}"
}

uninstall_service() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "uninstall 需要 root 权限。"
    return 1
  fi

  if has_systemd; then
    systemctl disable --now "$UNIT_NAME" >/dev/null 2>&1 || true
    rm -f "$UNIT_PATH"
    systemctl daemon-reload
  fi

  rm -f "$PANEL_PATH"

  echo "已卸载服务：${UNIT_NAME}"
  echo "脚本文件仍保留：${INSTALL_PATH}"
  echo "日志仍保留：${LOG_FILE}"
}

start_service() {
  if has_systemd && [ -f "$UNIT_PATH" ]; then
    if systemctl is-active --quiet "$UNIT_NAME"; then
      echo "服务已经在运行：${UNIT_NAME}"
    else
      systemctl start "$UNIT_NAME"
      echo "已启动：${UNIT_NAME}"
    fi
  else
    echo "服务未安装。请先执行：bash $SCRIPT_PATH install"
    return 1
  fi
}

stop_service() {
  if has_systemd && [ -f "$UNIT_PATH" ]; then
    systemctl stop "$UNIT_NAME" || true
    echo "已停止：${UNIT_NAME}"
  else
    echo "服务未安装。"
  fi
}

restart_service() {
  if has_systemd && [ -f "$UNIT_PATH" ]; then
    systemctl restart "$UNIT_NAME"
    echo "已重启：${UNIT_NAME}"
  else
    echo "服务未安装。请先执行 install。"
    return 1
  fi
}

show_status() {
  echo "======================================"
  echo " Cloudflare DDNS 状态"
  echo "======================================"
  echo "脚本当前路径：$SCRIPT_PATH"
  echo "安装路径：$INSTALL_PATH"
  echo "服务名：$UNIT_NAME"
  echo "面板命令：$PANEL_CMD"
  echo "日志：$LOG_FILE"
  echo
  echo "主记录：$FULL_DOMAIN"
  echo "主记录类型：$RECORD_TYPE"
  echo "IPv6备用：$V6_FULL_DOMAIN"
  echo "IPv6类型：$V6_RECORD_TYPE"
  echo "合并双栈：$MERGED_FULL_DOMAIN"
  echo "合并双栈类型：$MERGED_A_RECORD_TYPE + $MERGED_AAAA_RECORD_TYPE"
  echo "合并双栈开关：$MERGED_ENABLE"
  echo "主记录备注：$RECORD_COMMENT"
  echo "IPv6备注：$V6_RECORD_COMMENT"
  echo "合并 A 备注：$MERGED_A_RECORD_COMMENT"
  echo "合并 AAAA 备注：$MERGED_AAAA_RECORD_COMMENT"
  echo "TTL：$TTL 秒"
  echo "代理：$(json_bool "$CF_PROXIED")"
  echo
  echo "Cloudflare Token：$(mask_value "$CF_API_TOKEN")"
  echo "Zone ID：${ZONE_ID:-未填写，将自动查询}"
  echo "配置文件：${CONFIG_FILE}，可选；脚本内置值优先"
  echo

  if has_systemd && [ -f "$UNIT_PATH" ]; then
    systemctl status "$UNIT_NAME" --no-pager -l || true
  else
    echo "systemd 服务：未安装"
  fi

  echo
  echo "相关进程："
  ps aux | grep -Ei '[t]xcfddns|[c]fddns|[c]loudflare|awssg1|awssg1-v6|awssg1v4v6' || true
}

show_logs() {
  tail -n 100 "$LOG_FILE" 2>/dev/null || echo "暂无日志：$LOG_FILE"
}

follow_logs() {
  mkdir -p "$LOG_DIR"
  touch "$LOG_FILE"
  tail -f "$LOG_FILE"
}

show_config() {
  echo "当前配置："
  echo "CF_API_TOKEN：$(mask_value "$CF_API_TOKEN")"
  echo "Zone ID：${ZONE_ID:-未填写，将自动查询}"
  echo "主记录域名：${FULL_DOMAIN}"
  echo "主记录类型：${RECORD_TYPE}"
  echo "IPv6备用域名：${V6_FULL_DOMAIN}"
  echo "IPv6备用类型：${V6_RECORD_TYPE}"
  echo "合并双栈域名：${MERGED_FULL_DOMAIN}"
  echo "合并双栈类型：${MERGED_A_RECORD_TYPE} + ${MERGED_AAAA_RECORD_TYPE}"
  echo "合并双栈开关：${MERGED_ENABLE}"
  echo "主记录备注：${RECORD_COMMENT}"
  echo "IPv6备用备注：${V6_RECORD_COMMENT}"
  echo "合并 A 备注：${MERGED_A_RECORD_COMMENT}"
  echo "合并 AAAA 备注：${MERGED_AAAA_RECORD_COMMENT}"
  echo "IPv6备用开关：${V6_ENABLE}"
  echo "IPv6优先网卡：${V6_INTERFACE:-自动扫描}"
  echo "TTL：${TTL} 秒"
  echo "代理：$(json_bool "$CF_PROXIED")"
  echo "后台检查间隔：${CHECK_INTERVAL} 秒"
  echo "失败重试间隔：${RETRY_SLEEP} 秒"
  echo "日志：${LOG_FILE}"
  echo
  echo "说明："
  echo "1. 当前是 Cloudflare 单文件版，脚本内置 CF_API_TOKEN 和 Zone ID。"
  echo "2. ${CONFIG_FILE} 仍可选；但脚本内置 Token / Zone ID 非空时，会优先使用脚本内置值。"
  echo "3. 即使 Token 是所有区域可用，Cloudflare DNS API 请求仍使用 zone_id 路径；本脚本已内置 Zone ID，所以不会再自动查询 Zone。"
  echo "4. 不缓存 IP。"
  echo "5. 不缓存 Record ID。"
  echo "6. 每次执行都会实时查询 Cloudflare DNS 记录。"
  echo "7. 主域名固定默认 894454.xyz，保留 awssg1 和 awssg1-v6，并新增 awssg1v4v6 合并双栈记录。"
  echo "8. awssg1v4v6 会同时维护 A 和 AAAA：A 使用公网 IPv4，AAAA 使用公网 IPv6。"
  echo "9. IPv6 优先从本机网卡读取公网 2000::/3 地址；如果网卡没有可用公网 IPv6，再按 API 列表兜底。"
  echo "10. 如果当前机器没有 IPv6 出口，会跳过 IPv6 备用记录和合并双栈 AAAA，不影响 IPv4。"
  echo "11. install 后自动开机自启并立即运行。"
  echo "12. 后续输入 txcfddns 只打开面板。"
}

disable_other_ddns_services() {
  if ! has_systemd; then
    echo "当前系统没有 systemd。"
    return 1
  fi

  echo "将停止其他 txcfddns / cfddns / ddns / cloudflare 相关服务，但保留当前服务：${UNIT_NAME}"

  systemctl list-units --type=service --all --no-legend \
    | awk '{print $1}' \
    | grep -Ei 'txcfddns|cfddns|ddns|cloudflare' \
    | grep -v "^${UNIT_NAME}$" \
    | while read -r svc; do
        [ -n "$svc" ] || continue
        echo "停止并禁用：$svc"
        systemctl disable --now "$svc" >/dev/null 2>&1 || true
      done

  echo "其他 DDNS 相关 systemd 服务已处理。"
}

menu() {
  while true; do
    clear 2>/dev/null || true
    echo "======================================"
    echo " Cloudflare DDNS 面板 - ${FULL_DOMAIN} + ${V6_FULL_DOMAIN} + ${MERGED_FULL_DOMAIN}"
    echo "======================================"
    echo "1. 立即执行一次 DDNS"
    echo "2. 安装 / 覆盖 / 修复 systemd 开机自启"
    echo "3. 启动后台服务"
    echo "4. 停止后台服务"
    echo "5. 重启后台服务"
    echo "6. 查看服务状态"
    echo "7. 查看最近日志"
    echo "8. 实时日志"
    echo "9. 查看当前配置"
    echo "10. 停止其他 DDNS 相关 systemd 服务"
    echo "11. 卸载当前 systemd 服务"
    echo "0. 退出面板"
    echo "======================================"
    read -r -p "请选择 [0-11]: " choice

    case "$choice" in
      1)
        echo
        run_once
        echo
        read -r -p "按回车返回面板..." _
        ;;
      2)
        echo
        install_service
        echo
        read -r -p "按回车返回面板..." _
        ;;
      3)
        echo
        start_service
        echo
        read -r -p "按回车返回面板..." _
        ;;
      4)
        echo
        stop_service
        echo
        read -r -p "按回车返回面板..." _
        ;;
      5)
        echo
        restart_service
        echo
        read -r -p "按回车返回面板..." _
        ;;
      6)
        echo
        show_status
        echo
        read -r -p "按回车返回面板..." _
        ;;
      7)
        echo
        show_logs
        echo
        read -r -p "按回车返回面板..." _
        ;;
      8)
        echo "实时日志中，按 Ctrl+C 退出实时日志。"
        follow_logs
        ;;
      9)
        echo
        show_config
        echo
        read -r -p "按回车返回面板..." _
        ;;
      10)
        echo
        disable_other_ddns_services
        echo
        read -r -p "按回车返回面板..." _
        ;;
      11)
        echo
        uninstall_service
        echo
        read -r -p "按回车返回面板..." _
        ;;
      0)
        echo "已退出面板。"
        exit 0
        ;;
      *)
        echo "无效选择。"
        sleep 1
        ;;
    esac
  done
}

usage() {
  cat <<USAGE
用法：
  bash $SCRIPT_PATH                 安装/覆盖 systemd，并立即后台运行
  bash $SCRIPT_PATH install         安装/覆盖 systemd，并立即后台运行
  bash $SCRIPT_PATH menu            打开面板
  bash $SCRIPT_PATH once            立即执行一次 DDNS
  bash $SCRIPT_PATH daemon          前台进入守护循环
  bash $SCRIPT_PATH uninstall       卸载 systemd 服务
  bash $SCRIPT_PATH start           启动后台服务
  bash $SCRIPT_PATH stop            停止后台服务
  bash $SCRIPT_PATH restart         重启后台服务
  bash $SCRIPT_PATH status          查看状态
  bash $SCRIPT_PATH logs            查看最近日志
  bash $SCRIPT_PATH follow          实时日志
  bash $SCRIPT_PATH config          查看配置
  bash $SCRIPT_PATH disable-others  停止其他 DDNS 相关 systemd 服务

安装后面板命令：
  ${PANEL_CMD}

当前管理：
  主记录：${FULL_DOMAIN}
  主记录类型：${RECORD_TYPE}
  IPv6备用：${V6_FULL_DOMAIN}
  IPv6备用类型：${V6_RECORD_TYPE}
  合并双栈：${MERGED_FULL_DOMAIN}
  合并双栈类型：${MERGED_A_RECORD_TYPE} + ${MERGED_AAAA_RECORD_TYPE}
  主记录备注：${RECORD_COMMENT}
  IPv6备用备注：${V6_RECORD_COMMENT}
  合并 A 备注：${MERGED_A_RECORD_COMMENT}
  合并 AAAA 备注：${MERGED_AAAA_RECORD_COMMENT}
  TTL：${TTL} 秒
  代理：$(json_bool "$CF_PROXIED")
USAGE
}

cmd="${1:-install}"
if [ "$#" -eq 0 ] && [ "$(basename "$0")" = "$PANEL_CMD" ]; then
  cmd="menu"
fi

case "$cmd" in
  install)
    install_service
    ;;
  menu)
    menu
    ;;
  once)
    run_once
    ;;
  daemon)
    daemon_loop
    ;;
  uninstall)
    uninstall_service
    ;;
  start)
    start_service
    ;;
  stop)
    stop_service
    ;;
  restart)
    restart_service
    ;;
  status)
    show_status
    ;;
  logs)
    show_logs
    ;;
  follow)
    follow_logs
    ;;
  config)
    show_config
    ;;
  disable-others)
    disable_other_ddns_services
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
