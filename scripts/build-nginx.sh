#!/usr/bin/env bash
# Build portable nginx from source. Bundles zlib + pcre2 + openssl statically
# so the binary is relocatable. Output layout:
#   sbin/nginx     (app expects nginx in sbin/)
#
# nginx bakes a compile-time prefix; the app must run it with `-p <prefix>`
# and `-c <conf>` to relocate conf/logs/temp at runtime.
#
# Usage: build-nginx.sh <nginx_version>   e.g. build-nginx.sh 1.27.4
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

NGINX_VER="${1:?usage: build-nginx.sh <version>}"
PCRE2_VER="${PCRE2_VER:-10.44}"
ZLIB_VER="${ZLIB_VER:-1.3.1}"
PLATFORM="$(detect_platform)"

WORK="$REPO_ROOT/dist/nginx-build"
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

log "downloading sources (nginx $NGINX_VER, pcre2 $PCRE2_VER, zlib $ZLIB_VER)"
curl -fsSL -o nginx.tar.gz "https://nginx.org/download/nginx-${NGINX_VER}.tar.gz"
curl -fsSL -o pcre2.tar.gz "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VER}/pcre2-${PCRE2_VER}.tar.gz"
curl -fsSL -o zlib.tar.gz  "https://zlib.net/zlib-${ZLIB_VER}.tar.gz"
for f in nginx pcre2 zlib; do tar -xzf "$f.tar.gz"; done

# OpenSSL: use system/Homebrew headers on macOS (cannot fully static libSystem);
# on Linux statically link a fetched openssl source for portability.
CONFIGURE_OPENSSL=""
if [ "$PLATFORM" = "darwin" ]; then
  OPENSSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || echo /opt/homebrew/opt/openssl@3)"
  CC_OPT="-I${OPENSSL_PREFIX}/include"
  LD_OPT="-L${OPENSSL_PREFIX}/lib"
else
  OPENSSL_VER="${OPENSSL_VER:-3.0.15}"
  curl -fsSL -o openssl.tar.gz "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/openssl-${OPENSSL_VER}.tar.gz"
  tar -xzf openssl.tar.gz
  CONFIGURE_OPENSSL="--with-openssl=$WORK/openssl-${OPENSSL_VER}"
  CC_OPT=""
  LD_OPT=""
fi

cd "nginx-${NGINX_VER}"
log "configuring nginx"
# shellcheck disable=SC2086
./configure \
  --prefix=/tmp/ln-nginx \
  --sbin-path=sbin/nginx \
  --conf-path=conf/nginx.conf \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_realip_module \
  --with-http_gzip_static_module \
  --with-http_stub_status_module \
  --with-pcre="$WORK/pcre2-${PCRE2_VER}" \
  --with-zlib="$WORK/zlib-${ZLIB_VER}" \
  $CONFIGURE_OPENSSL \
  ${CC_OPT:+--with-cc-opt="$CC_OPT"} \
  ${LD_OPT:+--with-ld-opt="$LD_OPT"}

log "compiling nginx"
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

reset_stage
[ -f objs/nginx ] || die "nginx build did not produce objs/nginx"
cp objs/nginx "$STAGE_DIR/sbin/nginx"
chmod +x "$STAGE_DIR/sbin/nginx"

smoke "$STAGE_DIR/sbin/nginx" -v

"$SCRIPT_DIR/package.sh" nginx "$NGINX_VER"
