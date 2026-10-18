#!/usr/bin/env bash
# Overlay our device-side assets and the freshly built ksu_susfs onto a
# HMA-OSS checkout, so the produced module matches this repository.
#
#   ./scripts/overlay-device.sh <hma-oss-dir> <ksu_susfs-binary>
set -euo pipefail

HMA=${1:?usage: overlay-device.sh <hma-oss-dir> <ksu_susfs-binary>}
KSU=${2:?usage: overlay-device.sh <hma-oss-dir> <ksu_susfs-binary>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

[ -d "$HMA/zygote/src/main/assets" ] || { echo "::error::not a HMA-OSS checkout: $HMA" >&2; exit 1; }
[ -f "$KSU" ] || { echo "::error::ksu_susfs binary not found: $KSU" >&2; exit 1; }

install -m 0644 "$ROOT/device/hmaoss.sh"    "$HMA/zygote/src/main/assets/hmaoss.sh"
install -m 0644 "$ROOT/device/susfs_sync.sh" "$HMA/app/src/main/assets/susfs_sync.sh"
mkdir -p "$HMA/zygote/src/main/assets/susfs"
install -m 0755 "$KSU" "$HMA/zygote/src/main/assets/susfs/ksu_susfs"

# sanity: the module must ship per-target support
grep -q add_hidden_uid_from "$HMA/zygote/src/main/assets/hmaoss.sh" \
  || { echo "::error::hmaoss.sh missing add_hidden_uid_from" >&2; exit 1; }
grep -q add_hidden_uid_from "$HMA/zygote/src/main/assets/susfs/ksu_susfs" \
  || { echo "::error::ksu_susfs missing add_hidden_uid_from" >&2; exit 1; }
echo "overlay ok: $HMA"
