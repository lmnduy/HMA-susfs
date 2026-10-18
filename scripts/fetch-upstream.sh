#!/usr/bin/env bash
# Clone the pinned upstream sources into <workdir>.
#
#   ./scripts/fetch-upstream.sh <workdir>
#
# Produces:
#   <workdir>/hma-oss   at $HMA_COMMIT  (+ refs/remotes/origin/master)
#   <workdir>/susfs     at $SUSFS_COMMIT
set -euo pipefail

WORK=${1:?usage: fetch-upstream.sh <workdir>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/upstream/hma-oss.env"
# shellcheck disable=SC1091
. "$ROOT/upstream/susfs.env"

mkdir -p "$WORK"

clone_at() {
  local repo=$1 ref=$2 commit=$3 dest=$4
  rm -rf "$dest"
  git init -q "$dest"
  git -C "$dest" remote add origin "$repo"
  if ! git -C "$dest" fetch -q --depth 1 origin "$commit"; then
    git -C "$dest" fetch -q --depth 1 origin "$ref"
    git -C "$dest" fetch -q --depth 1 origin "$commit" || true
  fi
  git -C "$dest" checkout -q "$commit"
  echo "[$dest] $(git -C "$dest" rev-parse HEAD) $(git -C "$dest" log -1 --format=%s)"
}

clone_at "$HMA_REPO"   "$HMA_REF"   "$HMA_COMMIT"   "$WORK/hma-oss"
clone_at "$SUSFS_REPO" "$SUSFS_REF" "$SUSFS_COMMIT" "$WORK/susfs"

# HMA's build.gradle.kts derives versionCode/versionName from
# 'git rev-list refs/remotes/origin/master', which a shallow commit checkout
# does not create.  Point that ref at the pinned commit.
git -C "$WORK/hma-oss" update-ref refs/remotes/origin/master "$HMA_COMMIT"
echo "origin/master -> $(git -C "$WORK/hma-oss" rev-parse --short refs/remotes/origin/master)"
