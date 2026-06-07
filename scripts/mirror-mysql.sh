#!/usr/bin/env bash
# Mirror official MySQL Community tarball into the app's portable layout.
#   bin/mysqld, bin/mysql, bin/mysqladmin (+ lib/, share/ kept for runtime)
#
# Re-hosts the upstream binary as our own release asset (no recompilation).
#
# Usage: mirror-mysql.sh <version>   e.g. mirror-mysql.sh 8.0.40
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

VERSION="${1:?usage: mirror-mysql.sh <full.version>}"   # e.g. 8.0.40
PLATFORM="$(detect_platform)"
ARCH="$(detect_arch)"
MAJ_MIN="${VERSION%.*}"   # 8.0.40 -> 8.0

# Resolve upstream archive name per platform.
case "$PLATFORM-$ARCH" in
  darwin-arm64)  UP="mysql-${VERSION}-macos14-arm64.tar.gz";  EXT="tar.gz" ;;
  darwin-x86_64) UP="mysql-${VERSION}-macos14-x86_64.tar.gz"; EXT="tar.gz" ;;
  linux-x86_64)  UP="mysql-${VERSION}-linux-glibc2.28-x86_64.tar.xz"; EXT="tar.xz" ;;
  linux-arm64)   UP="mysql-${VERSION}-linux-glibc2.28-aarch64.tar.xz"; EXT="tar.xz" ;;
  *) die "unsupported platform: $PLATFORM-$ARCH" ;;
esac

URL="https://dev.mysql.com/get/Downloads/MySQL-${MAJ_MIN}/${UP}"
WORK="$REPO_ROOT/dist/mysql-mirror"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

log "downloading $URL"
curl -fsSL -o "archive.$EXT" "$URL" || die "MySQL download failed: $URL"

log "extracting"
if [ "$EXT" = "tar.xz" ]; then tar -xJf "archive.$EXT"; else tar -xzf "archive.$EXT"; fi
SRC="$(find . -maxdepth 1 -type d -name 'mysql-*' | head -n1)"
[ -n "$SRC" ] || die "extracted MySQL dir not found"

reset_stage
# Keep bin/, lib/, share/ — needed for mysqld runtime + --initialize messages.
cp -R "$SRC/bin/." "$STAGE_DIR/bin/"
[ -d "$SRC/lib" ]   && { mkdir -p "$STAGE_DIR/lib";   cp -R "$SRC/lib/."   "$STAGE_DIR/lib/"; }
[ -d "$SRC/share" ] && { mkdir -p "$STAGE_DIR/share"; cp -R "$SRC/share/." "$STAGE_DIR/share/"; }
chmod +x "$STAGE_DIR/bin/"* 2>/dev/null || true

for b in mysqld mysql mysqladmin; do [ -f "$STAGE_DIR/bin/$b" ] || die "missing bin/$b after mirror"; done
smoke "$STAGE_DIR/bin/mysqld" --version

"$SCRIPT_DIR/package.sh" mysql "$VERSION"
