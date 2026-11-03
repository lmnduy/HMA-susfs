#!/system/bin/sh
# ABK BOOT_DELAY_ABK: rebuild the sus_path tables once, two minutes after boot,
# instead of during the boot itself (which delayed the boot and ran before the
# per-app data dirs were resolvable).  The kernel forgets every entry across a
# reboot, so this pass starts from an empty state dictionary (--reset).
# Install at: /data/adb/service.d/hma_late_sync.sh (0755)
(
  sleep 120
  if [ -x /data/adb/hma_susfs/bin/ksu_susfs ]; then
    sh /data/adb/hma_susfs/sync.sh --reset
  else
    # fall back to the module boot script when the sync script is not deployed
    sh /data/adb/boot-completed.d/hmaoss.sh >/dev/null 2>&1
  fi
) &
