# localnhanh/binaries

Portable, relocatable runtime binaries for the **LocalNhanh** desktop/VPS app.
The app downloads these into `~/.localnhanh/packages/{service}/{version}/` and
runs them directly — no system installation.

## Contract with the app

The LocalNhanh app (`crates/localnhanh-core/src/services/downloader.rs`) expects:

- **Registry**: `https://raw.githubusercontent.com/localnhanh/binaries/main/registry.json`
- **Asset URL**: `https://github.com/localnhanh/binaries/releases/download/{service}-{version}/{service}-{version}-{platform}-{arch}.tar.gz`
- **platform**: `darwin` | `linux` | `windows` · **arch**: `arm64` | `x86_64`
- **Archive layout** (extracted straight into the version dir):

  | Service | Required binaries | Dir |
  |---|---|---|
  | php | `php-fpm` | `sbin/` |
  | php | `php` | `bin/` |
  | mysql / mariadb | `mysqld`/`mariadbd`, `mysql`, `mysqladmin` | `bin/` |
  | nginx | `nginx` | `sbin/` |

- **registry.json schema**: `{ schema_version, updated_at, runtimes.{svc}.versions[].platforms.{platform-arch}.{url,sha256,size_bytes} }`

## Build strategy

| Service | Strategy | Notes |
|---|---|---|
| PHP | **build** via [static-php-cli](https://github.com/crazywhalecc/static-php-cli) | static, relocatable; fpm + cli |
| nginx | **build** from source | bundles pcre2 + zlib; run with `-p` to relocate |
| MySQL | **mirror** official tarball | re-host upstream, keep `bin/`+`lib/`+`share/` |
| MariaDB | **mirror** official tarball | URL resolved via MariaDB REST API |

### Platform coverage

v1 targets **darwin-arm64** (verify end-to-end on Apple Silicon first).
The workflow matrices have the other platforms commented out — uncomment to expand.

> [!NOTE]
> **Linux portability** (when enabled): build inside an old-glibc container
> (e.g. `debian:10`) and `patchelf` the binaries to bundle `.so` deps with an
> `$ORIGIN` rpath. This mirrors the approach used by `marixdev/lstack-binaries`.
> On macOS a fully static binary isn't possible (libSystem), so static-php-cli's
> "mostly static" output is the right call.

## Layout

```
scripts/        build/mirror/package/publish/registry generation
manifests/      versions.json — versions to build per service
.github/workflows/  build-php, build-nginx, mirror, update-registry
registry.json   generated from releases (committed to main)
```

## Usage (CI)

Trigger workflows from the Actions tab (`workflow_dispatch`), or:

```bash
gh workflow run build-php.yml   -f versions="8.4"
gh workflow run build-nginx.yml -f versions="1.30.2"
gh workflow run mirror.yml      -f mysql_versions="8.0.40" -f mariadb_versions="11.4.4"
gh workflow run update-registry.yml
```

## Local testing

```bash
./scripts/build-php.sh 8.4         # produces dist/out/php-8.4-<platform>-<arch>.tar.gz
./scripts/build-nginx.sh 1.30.2
./scripts/mirror-mysql.sh 8.0.40
```
