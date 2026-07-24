bash <<'CLEAN'
set -u

echo "===== 停止并删除 V2bX 服务 ====="
systemctl disable --now V2bX.service 2>/dev/null || true
rm -f -- /etc/systemd/system/V2bX.service
systemctl daemon-reload
systemctl reset-failed V2bX.service 2>/dev/null || true

echo "===== 删除 V2bX ====="
rm -rf -- /usr/local/V2bX
rm -rf -- /etc/V2bX
rm -f -- /usr/bin/V2bX
rm -f -- /usr/bin/v2bx

echo "===== 删除 NFU ====="
rm -rf -- /etc/nfu
rm -f -- /usr/bin/nfu
rm -f -- /tmp/service-information.json

hash -r

echo "===== 检查清理结果 ====="
if systemctl list-unit-files |
   grep -qi '^V2bX\.service'; then
    echo "❌ V2bX 服务仍然存在"
else
    echo "✅ V2bX 服务已删除"
fi

for TARGET in \
    /usr/local/V2bX \
    /etc/V2bX \
    /usr/bin/V2bX \
    /usr/bin/v2bx \
    /usr/bin/nfu \
    /etc/nfu
do
    if [[ -e "$TARGET" || -L "$TARGET" ]]; then
        echo "❌ 残留：$TARGET"
    else
        echo "✅ 已清除：$TARGET"
    fi
done

echo
echo "✅ V2bX 和 NFU 部署内容已清理，可以重新运行 hy2.sh"
CLEAN
