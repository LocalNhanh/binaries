#!/usr/bin/env node
/**
 * Generate registry.json from the repo's GitHub Releases.
 *
 * Contract with the LocalNhanh app (crates/localnhanh-core/src/services/downloader.rs):
 *   {
 *     "schema_version": 1,
 *     "updated_at": "<RFC3339>",
 *     "runtimes": {
 *       "<service>": { "versions": [
 *         { "version": "<v>", "platforms": {
 *             "<platform>-<arch>": { "url", "sha256", "size_bytes" } } } ] }
 *     }
 *   }
 *
 * Asset naming: {service}-{version}-{platform}-{arch}.tar.gz
 * Each asset has a sibling {asset}.sha256 file (raw hex digest).
 *
 * Usage: REPO=localnhanh/binaries node scripts/gen-registry.mjs > registry.json
 * Requires: gh CLI authenticated (uses `gh api`).
 */
import { execSync } from "node:child_process";

const REPO = process.env.REPO || "localnhanh/binaries";
const ASSET_RE = /^([a-z0-9]+)-(.+)-(darwin|linux|windows)-(arm64|x86_64)\.tar\.gz$/;

function gh(path) {
  const out = execSync(`gh api --paginate ${path}`, {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  });
  // --paginate may concatenate multiple JSON arrays; normalize to one array.
  const chunks = out.trim().split(/\n(?=\[)/).map((c) => JSON.parse(c));
  return chunks.flat();
}

function main() {
  const releases = gh(`repos/${REPO}/releases`);
  const runtimes = {};

  // Build a quick lookup of sha256 sidecars per release.
  for (const rel of releases) {
    const assets = rel.assets || [];
    const shaByName = {};
    for (const a of assets) {
      if (a.name.endsWith(".sha256")) {
        try {
          const txt = execSync(
            `curl -fsSL "${a.browser_download_url}"`,
            { encoding: "utf8" }
          ).trim();
          shaByName[a.name.replace(/\.sha256$/, "")] = txt.split(/\s+/)[0];
        } catch {
          /* ignore unreadable sidecar */
        }
      }
    }

    for (const a of assets) {
      const m = ASSET_RE.exec(a.name);
      if (!m) continue;
      const [, service, version, platform, arch] = m;
      const key = `${platform}-${arch}`;

      runtimes[service] ??= { versions: [] };
      let entry = runtimes[service].versions.find((v) => v.version === version);
      if (!entry) {
        entry = { version, platforms: {} };
        runtimes[service].versions.push(entry);
      }
      entry.platforms[key] = {
        url: a.browser_download_url,
        sha256: shaByName[a.name] ?? null,
        size_bytes: a.size ?? null,
      };
    }
  }

  // Sort versions descending (newest first) for nicer UI ordering.
  for (const svc of Object.values(runtimes)) {
    svc.versions.sort((a, b) =>
      b.version.localeCompare(a.version, undefined, { numeric: true })
    );
  }

  const registry = {
    schema_version: 1,
    updated_at: new Date().toISOString(),
    runtimes,
  };
  process.stdout.write(JSON.stringify(registry, null, 2) + "\n");
}

main();
