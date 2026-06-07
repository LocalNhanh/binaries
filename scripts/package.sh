#!/usr/bin/env bash
# Package STAGE_DIR into OUT_DIR/{service}-{version}-{platform}-{arch}.tar.gz
# plus a .sha256 sidecar. The archive contains bin/ and sbin/ at its root
# (no top-level wrapper dir) so the app extracts straight into
# packages/{service}/{version}/.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVICE="${1:?usage: package.sh <service> <version>}"
VERSION="${2:?usage: package.sh <service> <version>}"
KEY="$(platform_key)"
NAME="${SERVICE}-${VERSION}-${KEY}.tar.gz"

[ -d "$STAGE_DIR" ] || die "stage dir missing: $STAGE_DIR"
mkdir -p "$OUT_DIR"

log "packaging $SERVICE $VERSION ($KEY)"
# COPYFILE_DISABLE avoids macOS ._ AppleDouble entries in the tarball.
COPYFILE_DISABLE=1 tar -czf "$OUT_DIR/$NAME" -C "$STAGE_DIR" .
sha256_file "$OUT_DIR/$NAME" > "$OUT_DIR/$NAME.sha256"

log "-> $OUT_DIR/$NAME"
log "   sha256 $(cat "$OUT_DIR/$NAME.sha256")"
log "   size   $(wc -c < "$OUT_DIR/$NAME") bytes"
