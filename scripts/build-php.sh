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

# Per-version download overrides (e.g. pin a dependency to an older release).
DOWNLOAD_OVERRIDES=()

case "$VERSION" in
  7.*)
    # PHP 7.4 is EOL; building it on a modern (2026) toolchain needs three
    # workarounds, all verified on macOS arm64 + Linux x86_64:
    #   - opcache can't be statically compiled for PHP < 8.0 (spc limitation).
    #   - libxml2 >= 2.12 made xmlStructuredErrorFunc take a `const` xmlError*,
    #     which EOL 7.4 was never patched for -> pin libxml2 to the last 2.9.x.
    #   - ICU >= 75 requires C++17 (u16string_view / enable_if_t) in its headers,
    #     but 7.4's ext/intl builds against an older C++ std -> pin ICU to 74.2.
    EXTENSIONS="${EXTENSIONS//,opcache/}"
    DOWNLOAD_OVERRIDES+=(--custom-url "libxml2:https://download.gnome.org/sources/libxml2/2.9/libxml2-2.9.14.tar.xz")
    DOWNLOAD_OVERRIDES+=(--custom-url "icu:https://github.com/unicode-org/icu/releases/download/release-74-2/icu4c-74_2-src.tgz")
    # GD's bundled configure run-test ("char foobar(){}", undefined behaviour) is
    # miscompiled to an illegal instruction only by modern arm64 clang at -Os, so
    # configure aborts on macOS. Linux gcc builds gd fine, so drop it on mac only.
    if [ "$PLATFORM" = "darwin" ]; then
      EXTENSIONS="${EXTENSIONS//,gd/}"
    fi
    ;;
esac

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
./spc download --with-php="$VERSION" --for-extensions="$EXTENSIONS" --prefer-pre-built "${DOWNLOAD_OVERRIDES[@]}"

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
