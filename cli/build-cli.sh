#!/usr/bin/env bash
# Build ksu_susfs with the full per-target patch chain.
#
# usage: ./cli/build-cli.sh <susfs_src_dir> [out_dir]
#
# The chain itself lives in patches/apply-all.sh so that CI, the kernel build
# and manual builds all use the same order (60.patch -> hide_from -> hidden_uid
# -> hidden_uid_from).  Requires: python3, Android NDK.
set -euo pipefail

SUSFS_DIR=${1:?usage: build-cli.sh <susfs_src_dir> [out_dir]}
OUT_DIR=${2:-$PWD/out}
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

NDK=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
if [ -z "$NDK" ] || [ ! -x "$NDK/ndk-build" ]; then
  echo "::error::Android NDK not found (set ANDROID_NDK_HOME)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "[1/2] apply patch chain (CLI mode)"
bash "$REPO_ROOT/patches/apply-all.sh" "$SUSFS_DIR"

echo "[2/2] ndk-build"
"$NDK/ndk-build" -C "$SUSFS_DIR/ksu_susfs" -j"$(nproc 2>/dev/null || echo 4)"

BIN="$SUSFS_DIR/ksu_susfs/libs/arm64-v8a/ksu_susfs"
[ -f "$BIN" ] || { echo "::error::ksu_susfs binary not produced" >&2; exit 1; }
cp -f "$BIN" "$OUT_DIR/ksu_susfs"

for cmd in add_sus_path_hide_from add_hidden_uid add_hidden_uid_from; do
  grep -q "$cmd" "$OUT_DIR/ksu_susfs" || { echo "::error::missing command $cmd" >&2; exit 1; }
done
echo "built: $OUT_DIR/ksu_susfs ($(wc -c < "$OUT_DIR/ksu_susfs") bytes), all three commands present"
