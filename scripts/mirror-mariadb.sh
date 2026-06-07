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

# Map our platform to the MariaDB REST API `os` field value.
case "$PLATFORM" in
  darwin) OS_MATCH="mac" ;;     # API uses "macOS"
  linux)  OS_MATCH="linux" ;;   # API uses "Linux"
  *) die "unsupported platform: $PLATFORM" ;;
esac

WORK="$REPO_ROOT/dist/mariadb-mirror"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

log "resolving MariaDB $VERSION ($OS_MATCH/$ARCH) via REST API"
curl -fsSL -o api.json "$API" || die "MariaDB REST API failed: $API"

# Schema: { release_data: { "<version>": { files: [ { os, cpu, package_type,
# file_name, file_download_url } ] } } }. Pick the generic .tar.gz binary
# tarball matching os + cpu (arm accepts both arm64/aarch64).
URL="$(node -e '
  const fs=require("fs");
  const d=JSON.parse(fs.readFileSync("api.json","utf8"));
  const osm=process.argv[1].toLowerCase(), arch=process.argv[2];
  const archTokens = arch === "arm64" ? ["arm64","aarch64"] : ["x86_64","amd64"];
  let url="";
  const rd=d.release_data||{};
  for (const rel of Object.values(rd)) {
    for (const f of (rel.files||[])) {
      const os=(f.os||"").toLowerCase();
      const cpu=(f.cpu||"").toLowerCase();
      const name=(f.file_name||"").toLowerCase();
      const pkg=(f.package_type||"").toLowerCase();
      if (os.includes(osm) && archTokens.some(t=>cpu.includes(t)) &&
          pkg.includes("tar") && name.endsWith(".tar.gz")) {
        url=f.file_download_url||""; break;
      }
    }
    if (url) break;
  }
  process.stdout.write(url);
' "$OS_MATCH" "$ARCH")"

if [ -z "$URL" ]; then
  warn "MariaDB $VERSION has no generic tarball for $PLATFORM-$ARCH upstream — skipping"
  exit 0
fi

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
