#!/usr/bin/env bash
# Build portable PHP (php-fpm + php CLI) via static-php-cli (spc).
#
# Produces a relocatable, (mostly) static build. Output layout:
#   sbin/php-fpm   (app expects php-fpm in sbin/)
#   bin/php        (CLI)
#
# Usage: build-php.sh <version>     e.g. build-php.sh 8.4
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

VERSION="${1:?usage: build-php.sh <version>}"
PLATFORM="$(detect_platform)"
ARCH="$(detect_arch)"

# Extensions commonly required by PHP web apps (WordPress, Laravel, ...).
EXTENSIONS="bcmath,ctype,curl,dom,fileinfo,filter,gd,iconv,intl,mbstring,mysqli,opcache,openssl,pdo,pdo_mysql,phar,session,simplexml,sodium,tokenizer,xml,zip,zlib"

WORK="$REPO_ROOT/dist/php-build"
rm -rf "$WORK"; mkdir -p "$WORK"
cd "$WORK"

# Map our arch key to spc binary naming.
case "$PLATFORM-$ARCH" in
  darwin-arm64)  SPC_BIN="spc-macos-aarch64" ;;
  darwin-x86_64) SPC_BIN="spc-macos-x86_64" ;;
  linux-arm64)   SPC_BIN="spc-linux-aarch64" ;;
  linux-x86_64)  SPC_BIN="spc-linux-x86_64" ;;
  *) die "unsupported platform for php build: $PLATFORM-$ARCH" ;;
esac

log "fetching static-php-cli ($SPC_BIN)"
curl -fsSL -o spc "https://dl.static-php.dev/static-php-cli/spc-bin/nightly/$SPC_BIN"
chmod +x spc

log "doctor + download sources for PHP $VERSION"
./spc doctor --auto-fix || warn "spc doctor reported issues"
./spc download --with-php="$VERSION" --for-extensions="$EXTENSIONS" --prefer-pre-built

log "building cli + fpm (static)"
./spc build --build-cli --build-fpm "$EXTENSIONS"

# Stage into the app's expected layout.
reset_stage
[ -f buildroot/bin/php ]     || die "spc did not produce buildroot/bin/php"
[ -f buildroot/bin/php-fpm ] || die "spc did not produce buildroot/bin/php-fpm"
cp buildroot/bin/php     "$STAGE_DIR/bin/php"
cp buildroot/bin/php-fpm "$STAGE_DIR/sbin/php-fpm"
chmod +x "$STAGE_DIR/bin/php" "$STAGE_DIR/sbin/php-fpm"

smoke "$STAGE_DIR/bin/php" -v
smoke "$STAGE_DIR/sbin/php-fpm" -v

"$SCRIPT_DIR/package.sh" php "$VERSION"
