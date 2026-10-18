#!/system/bin/sh
# INFO: [patch] Fallback re-deploy of the standalone per-UID ksu_susfs tool.
#   KernelSU ksud re-links its applet to /data/adb/ksu/bin/ksu_susfs on every boot.
MODDIR=/data/adb/modules/hma_oss_zygisk
TOOL="$MODDIR/susfs/ksu_susfs"
[ -f "$TOOL" ] || exit 0
mkdir -p /data/adb/ksu/bin 2>/dev/null
_want="$(sha256sum "$TOOL" 2>/dev/null | cut -d' ' -f1)"
_have="$(sha256sum /data/adb/ksu/bin/ksu_susfs 2>/dev/null | cut -d' ' -f1)"
if [ -n "$_want" ] && [ "$_want" != "$_have" ]; then
    rm -f /data/adb/ksu/bin/ksu_susfs
    cp -f "$TOOL" /data/adb/ksu/bin/ksu_susfs
    chmod 755 /data/adb/ksu/bin/ksu_susfs
fi
exit 0