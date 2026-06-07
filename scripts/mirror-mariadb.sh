#!/usr/bin/env bash
# Mirror official MariaDB tarball into the app's portable layout.
#   bin/mariadbd (+ mysqld symlink), bin/mysql, bin/mysqladmin (+ lib/, share/, scripts/)
#
# Resolves the download URL via the MariaDB REST API so we don't hardcode
# fragile mirror paths. Re-hosts upstream as our own release asset.
#
# Usage: mirror-mariadb.sh <version>   e.g. mirror-mariadb.sh 11.4.4
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

VERSION="${1:?usage: mirror-mariadb.sh <full.version>}"
PLATFORM="$(detect_platform)"
ARCH="$(detect_arch)"

# MariaDB REST API exposes per-release file lists with os/cpu metadata.
API="https://downloads.mariadb.org/rest-api/mariadb/${VERSION}/"

# Map our keys to MariaDB's os/cpu naming used in file_name.
case "$PLATFORM" in
  darwin) OS_MATCH="macos" ;;
  linux)  OS_MATCH="linux-systemd" ;;
  *) die "unsupported platform: $PLATFORM" ;;
esac
case "$ARCH" in
  arm64)  CPU_MATCH="$([ "$PLATFORM" = darwin ] && echo arm64 || echo aarch64)" ;;
  x86_64) CPU_MATCH="x86_64" ;;
esac

WORK="$REPO_ROOT/dist/mariadb-mirror"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

log "resolving MariaDB $VERSION ($OS_MATCH/$CPU_MATCH) via REST API"
curl -fsSL -o api.json "$API" || die "MariaDB REST API failed: $API"

# Pick the .tar.gz bintar matching os+cpu. Falls back gracefully if absent.
URL="$(node -e '
  const fs=require("fs");
  const d=JSON.parse(fs.readFileSync("api.json","utf8"));
  const os=process.argv[1], cpu=process.argv[2];
  let url="";
  for (const rel of (d.releases?Object.values(d.releases):[])) {
    for (const f of (rel.files||[])) {
      const n=(f.file_name||"").toLowerCase();
      if (n.includes("bintar") && n.endsWith(".tar.gz") && n.includes(os) && n.includes(cpu)) {
        url=f.file_download_url||""; break;
      }
    }
    if (url) break;
  }
  process.stdout.write(url);
' "$OS_MATCH" "$CPU_MATCH")"

[ -n "$URL" ] || die "no MariaDB tarball for $PLATFORM-$ARCH at $VERSION (may require source build on macOS)"

log "downloading $URL"
curl -fsSL -o archive.tar.gz "$URL"
tar -xzf archive.tar.gz
SRC="$(find . -maxdepth 1 -type d -name 'mariadb-*' | head -n1)"
[ -n "$SRC" ] || die "extracted MariaDB dir not found"

reset_stage
cp -R "$SRC/bin/." "$STAGE_DIR/bin/"
for d in lib share scripts; do
  [ -d "$SRC/$d" ] && { mkdir -p "$STAGE_DIR/$d"; cp -R "$SRC/$d/." "$STAGE_DIR/$d/"; }
done
chmod +x "$STAGE_DIR/bin/"* 2>/dev/null || true

[ -f "$STAGE_DIR/bin/mariadbd" ] || [ -f "$STAGE_DIR/bin/mysqld" ] || die "missing mariadbd/mysqld after mirror"
smoke "$STAGE_DIR/bin/mariadbd" --version 2>/dev/null || smoke "$STAGE_DIR/bin/mysqld" --version

"$SCRIPT_DIR/package.sh" mariadb "$VERSION"
