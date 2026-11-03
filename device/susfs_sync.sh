#!/system/bin/sh

# HMA-OSS SUSFS sus_path sync script
#
# Shipped inside the manager APK (assets/susfs_sync.sh), pushed to
# /data/adb/hma_susfs/sync.sh by SusfsSyncer, executed as root.
#
# ABK FAST_PIPELINE_ABK: the pass has two phases so a no-op sync costs almost
# nothing:
#
#   1. render the DESIRED set ("mode|uid|path", plus "uid_from|huid|tuid") using
#      a package -> uid map built with one stat pass and awk joins - no fork per
#      pair;
#   2. sort it, diff against the STATE dictionary with comm, apply only the
#      delta.
#
# Previously every pair forked `stat` and `ksu_susfs`, so a full pass took over
# two minutes and even a no-change sync re-applied a third of the list.

SUSFS_DIR=/data/adb/hma_susfs
PKGS_FILE="$SUSFS_DIR/pkgs.txt"
EXTRA_FILE="$SUSFS_DIR/extra_paths.txt"
TARGETS_FILE="$SUSFS_DIR/targets.txt"
STATE_FILE="$SUSFS_DIR/state.tsv"
DESIRED_FILE="$SUSFS_DIR/desired.tmp"
DELTA_FILE="$SUSFS_DIR/delta.tmp"
UID_MAP="$SUSFS_DIR/uids.tmp"
TARGET_UID_MAP="$SUSFS_DIR/target_uids.tmp"
TARGET_NAMES="$SUSFS_DIR/target_names.tmp"
JOINED_FILE="$SUSFS_DIR/targets_joined.tmp"

# ABK: see hmaoss.sh - uid hiding is global, so only the detector target gets it.
UID_HIDE_TARGET="${UID_HIDE_TARGET:-com.chunqiunativecheck}"

# ABK: ONE hard-coded path. KernelSU's ksud re-links
# /data/adb/ksu/bin/ksu_susfs to its multi-call applet, which rejects the
# per-UID / per-target subcommands, and PATH lookup can hit that applet too.
KSU_SUSFS=/data/adb/hma_susfs/bin/ksu_susfs

if [ ! -x "$KSU_SUSFS" ]; then
    _mod=/data/adb/modules/hma_oss_zygisk/susfs/ksu_susfs
    if [ -f "$_mod" ]; then
        mkdir -p /data/adb/hma_susfs/bin 2>/dev/null
        cp -f "$_mod" "$KSU_SUSFS" 2>/dev/null
        chmod 755 "$KSU_SUSFS" 2>/dev/null
    fi
fi

if [ ! -x "$KSU_SUSFS" ]; then
    echo "SUSFS_SYNC_ERROR: $KSU_SUSFS is missing (the ksud applet is not accepted)"
    exit 2
fi

# Self-test: the tool MUST expose the per-target subcommands.
if ! "$KSU_SUSFS" 2>&1 | grep -q 'add_hidden_uid_from'; then
    echo "SUSFS_SYNC_ERROR: $KSU_SUSFS does not support add_hidden_uid_from"
    exit 3
fi

# ABK STATE_DICT_ABK: runtime dictionary of what is already applied.
# One "mode|uid|path" line per entry; --reset drops it (used on boot, where the
# kernel forgot every entry).
STATE_MODE="append"
case "${1:-}" in
    --reset) STATE_MODE="reset" ;;
esac
[ "${SUSFS_STATE_RESET:-0}" = "1" ] && STATE_MODE="reset"

mkdir -p "$SUSFS_DIR" 2>/dev/null
[ "$STATE_MODE" = "reset" ] && : > "$STATE_FILE" 2>/dev/null
[ -f "$STATE_FILE" ] || : > "$STATE_FILE" 2>/dev/null
: > "$DESIRED_FILE" 2>/dev/null

# ABK UID_MAP_ABK: package -> uid, one stat pass.  Every later lookup is a text
# join instead of a fork.
build_uid_map() {
    # One stat call for every data dir: forking stat per package costs ~25ms
    # each, which was 10s on this device.
    stat -c '%u %n' /data/user/0/* 2>/dev/null \
        | awk '{ p = $2; sub(/.*\//, "", p); if (p != "") print p "=" $1 }' > "$UID_MAP" 2>/dev/null
    return 0
}

pkg_uid() {
    awk -F= -v p="$1" '$1 == p { print $2; exit }' "$UID_MAP" 2>/dev/null
}

# Appending to a file costs a full open/write/close (~25ms on this device), so
# the pairs are buffered in a shell variable and flushed once in phase 2.
DESIRED_BUF=""
DESIRED_COUNT=0
emit_pair() {
    _mode="$1"
    _path="$2"
    _uid="$3"

    [ -n "$_path" ] || return 0
    DESIRED_BUF="$DESIRED_BUF$_mode|$_uid|$_path
"
    DESIRED_COUNT=$((DESIRED_COUNT + 1))

    # Flush in chunks: one big variable can exceed the shell/ARG_MAX limits, a
    # chunk of 200 lines (~12 KB) is safe and still only costs 30 file opens.
    if [ "$DESIRED_COUNT" -ge 200 ]; then
        printf '%s' "$DESIRED_BUF" >> "$DESIRED_FILE" 2>/dev/null
        DESIRED_BUF=""
        DESIRED_COUNT=0
    fi
    return 0
}

flush_desired() {
    if [ -n "$DESIRED_BUF" ]; then
        printf '%s' "$DESIRED_BUF" >> "$DESIRED_FILE" 2>/dev/null
    fi
    DESIRED_BUF=""
    DESIRED_COUNT=0
}

# ABK per-target helper: hide a path from ONE target uid only (kernel 'hide_from').
add_hide_from() {
    _path="$1"
    _uid="$2"

    [ -z "$_path" ] && return 0
    [ -e "$_path" ] || return 0

    emit_pair hide_from "$_path" "$_uid"
    return 0
}

# ABK SUS_PATH_LOOP_MODE_ABK: plain hide-list paths go through the loop variant;
# the kernel re-resolves and re-flags them on every app spawn, so inode churn
# cannot lose the hiding.  The loop form accepts paths that do not exist yet.
add_sus_path() {
    _path="$1"
    _uid="$2"

    [ -z "$_path" ] && return 0

    emit_pair loop "$_path" "$_uid"
    return 0
}

# ABK per-target sync: targets.txt lines are "<target><TAB><hidden>[<TAB>data]".
sync_target_hides() {
    _tf="$1"
    [ -s "$_tf" ] || return 0

    # One awk pass joins both columns against the uid map, so the shell loop
    # below never forks.
    awk -F'\t' -v uids="$UID_MAP" '
        BEGIN { while ((getline line < uids) > 0) { split(line, a, "="); U[a[1]] = a[2] } }
        {
            t = $1; h = $2; m = $3
            if (t == "" || h == "") next
            if (t ~ /^#/ || h ~ /^#/) next
            if (!(t in U) || !(h in U)) next
            if (U[t] == U[h]) next
            print U[t] "\t" U[h] "\t" h "\t" m
        }' "$_tf" > "$JOINED_FILE" 2>/dev/null

    _tab="$(printf '\t')"
    while IFS="$_tab" read -r _tuid _huid _hidden _mode; do
        [ -n "$_tuid" ] || continue

        # ABK: per-target uid hiding - one private (hidden_uid, target_uid) pair
        emit_pair uid_from "$_huid" "$_tuid" 2>/dev/null

        if [ "$_mode" = "data" ]; then
            _paths="/data/user/0/$_hidden /data/user_de/0/$_hidden /data/data/$_hidden /data_mirror/data_ce/null/$_hidden /data_mirror/data_de/null/$_hidden"
        else
            _paths="/data/user/0/$_hidden /data/user_de/0/$_hidden /data/data/$_hidden /data_mirror/data_ce/null/$_hidden /data_mirror/data_de/null/$_hidden /data/app/*/$_hidden-* /data/app/*/$_hidden"
        fi

        for _p in $_paths
        do
            add_hide_from "$_p" "$_tuid"
        done
    done < "$JOINED_FILE"

    return 0
}

sync_pkg() {
    _pkg="$1"

    [ -z "$_pkg" ] && return 0

    _uid="$(pkg_uid "$_pkg")"
    [ -n "$_uid" ] || _uid="-1"

    add_sus_path "/data/user/0/$_pkg" "$_uid"
    add_sus_path "/data/user_de/0/$_pkg" "$_uid"
    add_sus_path "/data/data/$_pkg" "$_uid"
    add_sus_path "/data_mirror/data_ce/null/$_pkg" "$_uid"
    add_sus_path "/data_mirror/data_de/null/$_pkg" "$_uid"

    for _p in /mnt/asec/"$_pkg"* /mnt/obb/"$_pkg"*; do
        add_sus_path "$_p" "$_uid"
    done

    for _p in /data/app/*/"$_pkg"-* /data/app/*/"$_pkg"; do
        add_sus_path "$_p" "$_uid"
    done

    return 0
}

# ABK EXTRA_PKG_EXPAND_ABK: the "<PKG>" placeholder expands over the real hide
# list (targets.txt column 2 plus pkgs.txt); in per-target mode pkgs.txt is empty.
hidden_pkgs() {
    {
        [ -s "$SUSFS_DIR/targets.txt" ] && cut -f2 "$SUSFS_DIR/targets.txt" 2>/dev/null
        [ -s "$SUSFS_DIR/pkgs.txt" ] && cat "$SUSFS_DIR/pkgs.txt" 2>/dev/null
    } | sed 's/[[:space:]]*$//' | grep -v '^[[:space:]]*$' | grep -v '^#' | sort -u
}

# ABK: uid map restricted to the configured targets (targets.txt column 1).
build_target_uid_map() {
    : > "$TARGET_UID_MAP" 2>/dev/null
    : > "$TARGET_NAMES" 2>/dev/null
    [ -s "$TARGETS_FILE" ] || return 0

    cut -f1 "$TARGETS_FILE" 2>/dev/null | sed 's/[[:space:]]*$//' \
        | grep -v '^[[:space:]]*$' | grep -v '^#' | sort -u > "$TARGET_NAMES"

    awk -F'=' 'NR == FNR { want[$0] = 1; next } ($1 in want) { print $1 "=" $2 }' \
        "$TARGET_NAMES" "$UID_MAP" > "$TARGET_UID_MAP" 2>/dev/null
    return 0
}

apply_extra_path_for_targets() {
    _path="$1"

    [ -n "$_path" ] || return 0
    [ -e "$_path" ] || return 0

    # ABK SELF_VIEW_ABK: never hide a path from its owner - the detector is also
    # a target, so without this guard /data/data/<detector> would be denied for
    # the detector itself.
    _owner_uid="$(stat -c %u "$_path" 2>/dev/null)"

    while IFS='=' read -r _tpkg _tuid; do
        [ -n "$_tuid" ] || continue
        [ "$_tuid" = "$_owner_uid" ] && continue
        emit_pair hide_from "$_path" "$_tuid"
    done < "$TARGET_UID_MAP"

    return 0
}

# ---------------------------------------------------------------- phase 1 ----
build_uid_map
build_target_uid_map

if [ -s "$PKGS_FILE" ]; then
    while IFS= read -r _line; do
        case "$_line" in ""|"#"*) continue ;; esac
        sync_pkg "$_line"
    done < "$PKGS_FILE"
fi

if [ -s "$EXTRA_FILE" ]; then
    _ntargets="$(wc -l < "$TARGET_UID_MAP" 2>/dev/null | tr -d ' ')"
    while IFS= read -r _line; do
        case "$_line" in ""|"#"*) continue ;; esac

        case "$_line" in
            *"<PKG>"*)
                # ABK: read the package list from a file instead of a pipeline,
                # so the expansion runs in this shell (a subshell would lose the
                # buffered DESIRED pairs).
                hidden_pkgs > "$SUSFS_DIR/hidden_pkgs.tmp"
                if [ -s "$SUSFS_DIR/hidden_pkgs.tmp" ]; then
                    while IFS= read -r _pkg; do
                        [ -n "$_pkg" ] || continue
                        _expanded="${_line%%<PKG>*}$_pkg${_line#*<PKG>}"
                        apply_extra_path_for_targets "$_expanded"
                    done < "$SUSFS_DIR/hidden_pkgs.tmp"
                    echo "SUSFS_SYNC_INFO: expanded '$_line' over $(wc -l < "$SUSFS_DIR/hidden_pkgs.tmp" | tr -d ' ') hidden package(s), hidden from $_ntargets target(s)"
                else
                    echo "SUSFS_SYNC_WARN: no hidden package to expand '$_line' with (targets.txt/pkgs.txt empty)"
                fi
                ;;
            *)
                apply_extra_path_for_targets "$_line"
                ;;
        esac
    done < "$EXTRA_FILE"
fi

mkdir -p /data/local/tmp/.hma_hf_probe 2>/dev/null
if "$KSU_SUSFS" add_sus_path_hide_from /data/local/tmp/.hma_hf_probe 0 >/dev/null 2>&1; then
    sync_target_hides "$TARGETS_FILE"
else
    echo "SUSFS_SYNC_ERROR: $KSU_SUSFS does not support add_sus_path_hide_from (kernel too old?); per-target hiding skipped"
fi
rmdir /data/local/tmp/.hma_hf_probe 2>/dev/null

# ---------------------------------------------------------------- phase 2 ----
flush_desired
sort -u "$DESIRED_FILE" > "$DESIRED_FILE.sorted" 2>/dev/null
sort -u "$STATE_FILE" > "$STATE_FILE.sorted" 2>/dev/null

APPLIED=0
FAILED=0
SKIPPED=0

if [ -s "$DESIRED_FILE.sorted" ]; then
    comm -13 "$STATE_FILE.sorted" "$DESIRED_FILE.sorted" > "$DELTA_FILE" 2>/dev/null
    SKIPPED="$(comm -12 "$STATE_FILE.sorted" "$DESIRED_FILE.sorted" 2>/dev/null | wc -l | tr -d ' ')"

    while IFS='|' read -r _mode _uid _path; do
        [ -n "$_mode" ] || continue
        case "$_mode" in
            uid_from)
                [ -n "$_uid" ] && [ -n "$_path" ] || continue
                "$KSU_SUSFS" add_hidden_uid_from "$_uid" "$_path" >/dev/null 2>&1 \
                    && APPLIED=$((APPLIED + 1)) || FAILED=$((FAILED + 1))
                ;;
            hide_from|loop)
                [ -n "$_path" ] || continue
                if [ "$_mode" = "hide_from" ]; then
                    "$KSU_SUSFS" add_sus_path_hide_from "$_path" "$_uid" >/dev/null 2>&1
                else
                    "$KSU_SUSFS" add_sus_path_loop "$_path" "$_uid" >/dev/null 2>&1
                fi
                if [ $? -eq 0 ]; then
                    APPLIED=$((APPLIED + 1))
                else
                    FAILED=$((FAILED + 1))
                fi
                ;;
        esac
    done < "$DELTA_FILE"

    if [ "$APPLIED" -gt 0 ]; then
        cat "$DELTA_FILE" >> "$STATE_FILE" 2>/dev/null
        sort -u "$STATE_FILE" -o "$STATE_FILE" 2>/dev/null
    fi
fi

TOTAL="$(wc -l < "$STATE_FILE" 2>/dev/null | tr -d ' ')"
rm -f "$DESIRED_FILE" "$DESIRED_FILE.sorted" "$STATE_FILE.sorted" "$DELTA_FILE" \
      "$JOINED_FILE" "$TARGET_NAMES" 2>/dev/null

echo "SUSFS_SYNC_OK: applied $APPLIED new, $SKIPPED unchanged, $FAILED failed, $TOTAL in dictionary ($STATE_MODE)"
exit 0
