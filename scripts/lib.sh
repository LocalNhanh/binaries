#!/usr/bin/env bash
# Common helpers for localnhanh/binaries build & mirror scripts.
#
# Contract with the LocalNhanh app (do not change without updating the app):
#   - Asset name:  {service}-{version}-{platform}-{arch}.tar.gz
#   - platform:    darwin | linux | windows
#   - arch:        arm64 | x86_64
#   - Layout after extraction (binaries live in bin/ or sbin/):
#       php   -> sbin/php-fpm, bin/php
#       nginx -> sbin/nginx
#       mysql/mariadb -> bin/mysqld|mariadbd, bin/mysql, bin/mysqladmin
set -euo pipefail

log()  { printf '\033[1;34m[ln]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[ln:warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ln:err]\033[0m %s\n' "$*" >&2; exit 1; }

detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux)  echo "linux" ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64" ;;
    x86_64|amd64)  echo "x86_64" ;;
    *) die "unsupported arch: $(uname -m)" ;;
  esac
}

platform_key() { echo "$(detect_platform)-$(detect_arch)"; }

sha256_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    shasum -a 256 "$f" | awk '{print $1}'
  fi
}

# Repo-root-relative dist dirs (overridable via env)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_DIR="${STAGE_DIR:-$REPO_ROOT/dist/stage}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/dist/out}"

# Reset the staging dir to a clean bin/ + sbin/ skeleton.
reset_stage() {
  rm -rf "$STAGE_DIR"
  mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/sbin"
}

# Smoke-test a binary by running it with a version-style flag (non-fatal echo).
smoke() {
  local bin="$1"; shift
  [ -x "$bin" ] || die "missing or non-executable: $bin"
  log "smoke: $bin $*"
  "$bin" "$@" >/dev/null 2>&1 || warn "smoke run returned non-zero for $bin (may be expected)"
}
