#!/system/bin/sh

# ref: https://github.com/PerformanC/ReZygisk/blob/main/module/src/rezygisk.sh

# INFO: This script gets moved to /data/adb/post-fs-data.d/hmaoss.sh

# INFO: This script is utilized so that when HMA-OSS is disabled, it still can clean up its
#         module.prop, making it not have traces of its old status.

MODDIR=/data/adb/modules/hma_oss_zygisk

# ABK: the ONLY target whose hidden packages also get their uid hidden.
# add_hidden_uid is global in the kernel, so it must never be applied for
# every target: doing that hid the detector's own uid (other apps hide the
# detector too) and turned uid-visibility probes into "incomplete".
UID_HIDE_TARGET="${UID_HIDE_TARGET:-com.chunqiunativecheck}"

# INFO: [patch] Deploy the standalone per-UID ksu_susfs tool to ONE private path.
#   KernelSU ksud is a multi-call applet: it re-links /data/adb/ksu/bin/ksu_susfs
#   to itself on boot and again whenever the manager runs, and that applet
#   rejects add_hidden_uid_from / add_sus_path_hide_from.
#   ABK: this module therefore never writes to /data/adb/ksu/bin and never
#   resolves the tool through PATH. /data/adb/hma_susfs/bin/ksu_susfs:
KSU_SUSFS=/data/adb/hma_susfs/bin/ksu_susfs

if [ -f "$MODDIR/susfs/ksu_susfs" ]; then
    chmod 755 "$MODDIR/susfs/ksu_susfs" 2>/dev/null
    mkdir -p /data/adb/hma_susfs/bin 2>/dev/null
    rm -f "$KSU_SUSFS"
    cp -f "$MODDIR/susfs/ksu_susfs" "$KSU_SUSFS"
    chmod 755 "$KSU_SUSFS"
fi

set -e

# INFO: Resets HMA-OSS module.prop to its default state which is saved upon installation.
cp "$MODDIR/module.prop.bak" "$MODDIR/module.prop"

(
    sleep 5

    try=1
    while [ "$try" -le 10 ]; do
        STATUS_FILE=$(printf '%s' /data/misc/hide_my_applist_*/status.json)
        [ -n "$STATUS_FILE" ] && [ -s "$STATUS_FILE" ] && break
        sleep 1
        try=$((try + 1))
    done

    sh "$MODDIR/update_desc.sh"
) &

# INFO: SUSFS package path hiding sync
#
# INFO: The manager app writes the package/path lists to /data/adb/hma_susfs
#         when the "SUSFS package path hiding sync" option is enabled.
#         sus_path entries only live in the kernel memory, so they have to be
#         re-applied on every boot. This block is idempotent and it silently
#         skips itself when ksu_susfs is unavailable.
(
    set +e

    SUSFS_DIR=/data/adb/hma_susfs
    PKGS_FILE="$SUSFS_DIR/pkgs.txt"
    EXTRA_FILE="$SUSFS_DIR/extra_paths.txt"

    # INFO: KernelSU's ksud is a multi-call applet and re-creates
    #         /data/adb/ksu/bin/ksu_susfs as a hard link to itself on every boot.
    #         That applet does NOT accept the per-UID argument, so re-deploy the
    #         standalone per-UID tool (shipped with this module) before syncing.
    # ABK: single tool path (see top of file). Never the ksud applet in
    #      /data/adb/ksu/bin, never PATH.
    KSU_SUSFS=/data/adb/hma_susfs/bin/ksu_susfs

    susfs_usable() {
        [ -x "$KSU_SUSFS" ] || return 1
        "$KSU_SUSFS" 2>&1 | grep -q 'add_hidden_uid_from'
    }

    try=1
    while [ "$try" -le 60 ]; do
        susfs_usable && break

        # re-deploy from the module mount if the private copy is missing or wrong
        if [ -f "$MODDIR/susfs/ksu_susfs" ]; then
            mkdir -p /data/adb/hma_susfs/bin 2>/dev/null
            cp -f "$MODDIR/susfs/ksu_susfs" "$KSU_SUSFS" 2>/dev/null
            chmod 755 "$KSU_SUSFS" 2>/dev/null
        fi

        # wait for the module mount to settle, ksu_susfs may appear late
        sleep 2
        try=$((try + 1))
    done

    if ! susfs_usable; then
        echo "[hma] $KSU_SUSFS missing or lacks add_hidden_uid_from; per-target sync skipped" >&2
        exit 0
    fi
    [ -d "$SUSFS_DIR" ] || exit 0

    # only apply the lists when the sync is enabled in the manager app
    [ "$(cat "$SUSFS_DIR/enabled" 2>/dev/null)" = "1" ] || exit 0

    add_sus_path() {
        _path="$1"
        _uid="$2"
        _loop="$3"

        [ -z "$_path" ] && return 0
        [ -e "$_path" ] || return 0

        if [ "$_loop" = "1" ]; then
            "$KSU_SUSFS" add_sus_path_loop "$_path" "$_uid" >/dev/null 2>&1
        else
            "$KSU_SUSFS" add_sus_path "$_path" "$_uid" >/dev/null 2>&1
        fi

        return 0
    }

    sync_pkg() {
        _pkg="$1"

        [ -z "$_pkg" ] && return 0

        _uid="$(stat -c %u "/data/user/0/$_pkg" 2>/dev/null)" || true
        [ -z "$_uid" ] && _uid="-1"

        add_sus_path "/data/user/0/$_pkg" "$_uid" 0
        add_sus_path "/data/user_de/0/$_pkg" "$_uid" 0
        add_sus_path "/data/data/$_pkg" "$_uid" 0
        add_sus_path "/data_mirror/data_ce/null/$_pkg" "$_uid" 0
        add_sus_path "/data_mirror/data_de/null/$_pkg" "$_uid" 0

        for _p in /mnt/asec/"$_pkg"* /mnt/obb/"$_pkg"*; do
            add_sus_path "$_p" "$_uid" 0
        done

        # ABK (all-in mode): hide install dir + external storage too.
        for _p in /data/app/*/"$_pkg"-* /data/app/*/"$_pkg" \
                  "/storage/emulated/0/Android/data/$_pkg" \
                  "/data/media/0/Android/data/$_pkg"; do
            add_sus_path "$_p" "$_uid" 0
        done

        return 0
    }

    if [ -s "$PKGS_FILE" ]; then
        while IFS= read -r _line; do
            case "$_line" in
                ""|"#"*) continue ;;
            esac

            sync_pkg "$_line"
        done < "$PKGS_FILE"
    fi

    if [ -s "$EXTRA_FILE" ]; then
        while IFS= read -r _line; do
            case "$_line" in
                ""|"#"*) continue ;;
            esac

            case "$_line" in
                *"<PKG>"*)
                    if [ -s "$PKGS_FILE" ]; then
                        while IFS= read -r _pkg; do
                            case "$_pkg" in
                                ""|"#"*) continue ;;
                            esac

                            _uid="$(stat -c %u "/data/user/0/$_pkg" 2>/dev/null)" || true
                            [ -z "$_uid" ] && _uid="-1"

                            _expanded="$(printf '%s' "$_line" | sed "s|<PKG>|$_pkg|g")" || true
                            add_sus_path "$_expanded" "$_uid" 0
                        done < "$PKGS_FILE"
                    fi
                    ;;
                *)
                    add_sus_path "$_line" "-1" 0
                    ;;
            esac
        done < "$EXTRA_FILE"
    fi
    # ABK: per-target hiding (mirrors the API layer per target)
    #   targets.txt lines are "<targetPkg><TAB><hiddenPkg>"
    TARGETS_FILE="$SUSFS_DIR/targets.txt"

    add_hide_from() {
        _path="$1"
        _uid="$2"

        [ -z "$_path" ] && return 0
        [ -e "$_path" ] || return 0

        "$KSU_SUSFS" add_sus_path_hide_from "$_path" "$_uid" >/dev/null 2>&1
        return 0
    }

    sync_target_hides() {
        [ -s "$TARGETS_FILE" ] || return 0

        _tab="$(printf '\t')"

        # ABK: the boot-time background sync can be reaped before it reaches
        # the end of targets.txt.  Pass 1 handles the detector's own hides
        # first, pass 2 the rest, so the critical pairs always land.
        for _pass in 1 2; do
        while IFS="$_tab" read -r _target _hidden _mode; do
            if [ "$_pass" = "1" ] && [ "$_target" != "$UID_HIDE_TARGET" ]; then continue; fi
            if [ "$_pass" = "2" ] && [ "$_target" = "$UID_HIDE_TARGET" ]; then continue; fi
            case "$_target" in ""|"#"*) continue ;; esac
            case "$_hidden" in ""|"#"*) continue ;; esac

            # ABK: set -e is active and an uninstalled hidden package makes
            # stat fail; without "|| true" the whole loop aborted early and
            # every later target (including the detector) was skipped.
            _tuid="$(stat -c %u "/data/user/0/$_target" 2>/dev/null)" || true
            [ -n "$_tuid" ] || _tuid="$(stat -c %u "/data/data/$_target" 2>/dev/null)" || true
            [ -z "$_tuid" ] && continue

            # ABK: per-target uid hiding (CMD_SUSFS_ADD_HIDDEN_UID_FROM).
            # One private (hidden_uid, target_uid) pair per line; other apps
            # keep their own view and a target can never hide itself.
            _huid="$(stat -c %u "/data/user/0/$_hidden" 2>/dev/null)" || true
            if [ -n "$_huid" ] && [ -n "$_tuid" ]; then
                "$KSU_SUSFS" add_hidden_uid_from "$_huid" "$_tuid" >/dev/null 2>&1 || true
            fi

            if [ "$_mode" = "data" ]; then
                _paths="/data/user/0/$_hidden /data/user_de/0/$_hidden /data/data/$_hidden /data_mirror/data_ce/null/$_hidden /data_mirror/data_de/null/$_hidden /storage/emulated/0/Android/data/$_hidden /data/media/0/Android/data/$_hidden"
            else
                _paths="/data/user/0/$_hidden /data/user_de/0/$_hidden /data/data/$_hidden /data_mirror/data_ce/null/$_hidden /data_mirror/data_de/null/$_hidden /storage/emulated/0/Android/data/$_hidden /data/media/0/Android/data/$_hidden /data/app/*/$_hidden-* /data/app/*/$_hidden"
            fi

            for _p in $_paths
            do
                add_hide_from "$_p" "$_tuid"
            done
        done < "$TARGETS_FILE"
        done

        return 0
    }

    mkdir -p /data/local/tmp/.hma_hf_probe 2>/dev/null
    if [ -n "$KSU_SUSFS" ] && "$KSU_SUSFS" add_sus_path_hide_from /data/local/tmp/.hma_hf_probe 0 >/dev/null 2>&1; then
        sync_target_hides
        # ABK: at boot-completed the per-app data dirs are not always
        # resolvable yet, so targets listed late (the detector) were skipped.
        # A second pass after the system settles makes the table complete.
        sleep 30
        sync_target_hides
    fi
    rmdir /data/local/tmp/.hma_hf_probe 2>/dev/null
) &

true
