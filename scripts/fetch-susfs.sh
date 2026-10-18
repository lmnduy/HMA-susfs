#!/usr/bin/env bash
# Clone the pinned SUSFS source (kernel patches + ksu_susfs CLI).
#
#   ./scripts/fetch-susfs.sh <dest>
#
# HMA-OSS itself is vendored in this repository under hma-oss/, so it is not
# fetched here: the commit of this repository IS its version lock.
set -euo pipefail

DEST=${1:?usage: fetch-susfs.sh <dest>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/upstream/susfs.env"

rm -rf "$DEST"
git init -q "$DEST"
git -C "$DEST" remote add origin "$SUSFS_REPO"
if ! git -C "$DEST" fetch -q --depth 1 origin "$SUSFS_COMMIT"; then
  git -C "$DEST" fetch -q --depth 1 origin "$SUSFS_REF"
  git -C "$DEST" fetch -q --depth 1 origin "$SUSFS_COMMIT" || true
fi
git -C "$DEST" checkout -q "$SUSFS_COMMIT"
echo "[susfs] $(git -C "$DEST" rev-parse HEAD) $(git -C "$DEST" log -1 --format=%s)"
