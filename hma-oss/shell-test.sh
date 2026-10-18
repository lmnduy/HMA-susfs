#!/bin/bash
set -u
SRC="$1"
W="$2"

rm -rf "$W"
mkdir -p "$W/data/adb/hma_susfs" "$W/data/adb/ksu/bin" "$W/data/user/0/com.example.app" \
  "$W/data/user_de/0/com.example.app" "$W/data/data/com.example.app" \
  "$W/data_mirror/data_ce/null/com.example.app" "$W/data_mirror/data_de/null/com.example.app" \
  "$W/data/app/~~abc/com.example.app-xyz" "$W/mnt/asec/com.example.app-1" "$W/mnt/obb" \
  "$W/data/local/tmp" "$W/data/media/0/com.example.app"; touch "$W/data/local/tmp/foo"

printf '%s\n' "com.example.app" > "$W/data/adb/hma_susfs/pkgs.txt"
{
  printf '%s\n' "$W/data/media/0/<PKG>"
  printf '%s\n' "$W/data/local/tmp/foo"
  printf '%s\n' "/data/nonexistent/<PKG>"
} > "$W/data/adb/hma_susfs/extra_paths.txt"
printf '1\n' > "$W/data/adb/hma_susfs/enabled"

cat > "$W/data/adb/ksu/bin/ksu_susfs" <<'STUB'
#!/bin/sh
echo "$@" >> "$KSU_CALLS"
STUB
chmod +x "$W/data/adb/ksu/bin/ksu_susfs"

sed -e "s#/data_mirror/#$W/data_mirror/#g" -e "s#/data/#$W/data/#g" -e "s#/mnt/#$W/mnt/#g" "$SRC" > "$W/sync.sh"

export KSU_CALLS="$W/calls.log"
: > "$KSU_CALLS"

PATH="/usr/bin:/bin" bash "$W/sync.sh"
echo "--- exit: $?"
echo "--- calls:"
sort "$KSU_CALLS" | sed "s#$W#\$W#g"
