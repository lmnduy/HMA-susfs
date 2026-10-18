#!/bin/bash
set -u
SRC="$1"
W="$2"

rm -rf "$W"
mkdir -p "$W/data/adb/hma_susfs" "$W/data/adb/ksu/bin" "$W/data/user/0/com.example.app" \
  "$W/data/user_de/0/com.example.app" "$W/data/data/com.example.app" \
  "$W/data_mirror/data_ce/null/com.example.app" "$W/data/app/~~abc/com.example.app-xyz" \
  "$W/mnt/asec/com.example.app-1" "$W/data/local/tmp"

printf '%s\n' "com.example.app" > "$W/data/adb/hma_susfs/pkgs.txt"
printf '%s\n' "$W/data/media/0/<PKG>" "$W/data/local/tmp/foo" > "$W/data/adb/hma_susfs/extra_paths.txt"
printf '1\n' > "$W/data/adb/hma_susfs/enabled"
touch "$W/data/local/tmp/foo"

cat > "$W/data/adb/ksu/bin/ksu_susfs" <<'STUB'
#!/bin/sh
echo "$@" >> "$KSU_CALLS"
STUB
chmod +x "$W/data/adb/ksu/bin/ksu_susfs"

{
  echo '#!/bin/bash'
  sed -n '/^# INFO: SUSFS package path hiding sync$/,/^) &$/p' "$SRC" | grep -v '^#' | sed '1d;$d'
} > "$W/block.sh"

sed -i -e "s#/data_mirror/#$W/data_mirror/#g" -e "s#/data/#$W/data/#g" -e "s#/mnt/#$W/mnt/#g" "$W/block.sh"

export KSU_CALLS="$W/calls.log"
: > "$KSU_CALLS"

PATH="/usr/bin:/bin" bash "$W/block.sh"
echo "--- exit: $?"
echo "--- calls:"
sort "$KSU_CALLS" | sed "s#$W#\$W#g"
