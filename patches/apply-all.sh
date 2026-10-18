#!/usr/bin/env bash
# Full patch chain for per-target UID hiding.
#
#   ./patches/apply-all.sh <susfs_dir> [kernel_root]
#
# <kernel_root> is required for a KERNEL build: it patches kernel/sys.c and the
# KernelSU supercall dispatch.  Omit it for a CLI-only build (ABK_CLI_ONLY).
#
# Order matters:
#   1. 60_add_per_uid_sus_path.patch    prerequisite: adds allowed_uid to the
#                                       sus_path structs + per-UID CLI arg
#   2. patch_susfs_hide_from_uid.py     0x55554 per-target sus_path
#   3. patch_susfs_hidden_uid.py        0x55555 global hidden uid
#   4. patch_susfs_hidden_uid_oracle.py getpriority/setpriority hook + dispatch
#   5. patch_susfs_hidden_uid_from.py   0x55556 per-target hidden uid
#
# NOTE (Windows): git apply / git checkout rewrite files with CRLF, and every
# patcher anchors on "\n".  This script normalizes line endings first; if you
# run the patchers by hand, run the same sed over the tree before them.
set -euo pipefail

SUSFS=${1:?usage: apply-all.sh <susfs_dir> [kernel_root]}
KERNEL=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)

normalize_tree() {
  find "$1" -type f \( -name '*.c' -o -name '*.h' -o -name '*.patch' -o -name '*.mk' \) \
    -exec sed -i 's/\r$//' {} + 2>/dev/null || true
}

normalize_tree "$SUSFS"
if [ -n "$KERNEL" ]; then
  normalize_tree "$KERNEL/common/kernel" 2>/dev/null || true
  find "$KERNEL" -path '*supercall/dispatch.c' -exec sed -i 's/\r$//' {} + 2>/dev/null || true
fi

echo "[1/5] per-UID sus_path ABI (60_add_per_uid_sus_path.patch)"
git -C "$SUSFS" init -q 2>/dev/null || true
git -C "$SUSFS" apply "$HERE/60_add_per_uid_sus_path.patch"

echo "[2/5] hide_from (0x55554)"
python3 "$HERE/patch_susfs_hide_from_uid.py" "$SUSFS"

echo "[3/5] global hidden uid (0x55555)"
python3 "$HERE/patch_susfs_hidden_uid.py" "$SUSFS"

if [ -n "$KERNEL" ]; then
  echo "[4/5] uid oracle hook + dispatch (0x55555)"
  python3 "$HERE/patch_susfs_hidden_uid_oracle.py" "$KERNEL"
  echo "[5/5] per-target hidden uid (0x55556)"
  python3 "$HERE/patch_susfs_hidden_uid_from.py" "$SUSFS" "$KERNEL"
else
  echo "[4/5] uid oracle: skipped (CLI-only build)"
  echo "[5/5] per-target hidden uid (0x55556, CLI only)"
  ABK_CLI_ONLY=1 python3 "$HERE/patch_susfs_hidden_uid_from.py" "$SUSFS" "$SUSFS"
fi

echo "patch chain done"
