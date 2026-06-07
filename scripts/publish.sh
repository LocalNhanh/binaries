#!/usr/bin/env bash
# Create/refresh a GitHub Release per (service, version) and upload the built
# tarball(s) + sha256 sidecars from OUT_DIR. Tag = {service}-{version}.
#
# Usage: publish.sh <service> <version> [<version> ...]
# Requires: gh CLI authenticated, GH_TOKEN in env.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

SERVICE="${1:?usage: publish.sh <service> <version>...}"; shift

for VERSION in "$@"; do
  TAG="${SERVICE}-${VERSION}"
  if ! gh release view "$TAG" >/dev/null 2>&1; then
    log "creating release $TAG"
    gh release create "$TAG" --title "$TAG" \
      --notes "Automated portable build of ${SERVICE} ${VERSION} for LocalNhanh."
  fi

  shopt -s nullglob
  local_assets=("$OUT_DIR/${SERVICE}-${VERSION}-"*.tar.gz "$OUT_DIR/${SERVICE}-${VERSION}-"*.tar.gz.sha256)
  shopt -u nullglob
  [ ${#local_assets[@]} -gt 0 ] || die "no assets in $OUT_DIR for ${SERVICE}-${VERSION}"

  for f in "${local_assets[@]}"; do
    log "uploading $(basename "$f") -> $TAG"
    gh release upload "$TAG" "$f" --clobber
  done
done
