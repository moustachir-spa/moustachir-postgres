# Security Audit — `jesuph/moustachir-postgres`

**Scope:** `jesuph/moustachir-postgres:18.1` (currently running) → new image built from this repo's `Dockerfile` (now targeting PostgreSQL 18.4 on Debian Bookworm).

**Scanner:** Trivy v0.72 (`aquasec/trivy:latest`), DB downloaded at scan time.
Filters: `--severity HIGH,CRITICAL --ignore-unfixed` (only CVEs that have a known fix in Debian upstream). All scans run against the local images via the Docker Desktop socket.

**Headline**

| Image | Debian | Distinct CVEs | CRITICAL | HIGH | Size |
|---|---|---|---|---|---|
| `jesuph/moustachir-postgres:18.1` (old) | **trixie** (13.3) | 47 | 9 | 38 | 957 MB |
| `moustachir/postgres:18.4.0` (new)  | **bookworm** (12.15) | 15 | 1 | 14 | 897 MB |
| **Delta** |  | **-32 (-68 %)** | **-8** | **-24** | **-6 %** |

The new image introduces **0 new CVEs** — every remaining vuln is also present in the old image and is inherited from the upstream `postgres:18.4-bookworm` base.

---

## 1. Vulnerabilities in the OLD image (`18.1`)

The base image `postgres:18.1` was actually built on **Debian trixie** (testing/13), which receives security fixes much later than stable. 47 HIGH/CRITICAL CVEs with known Debian fixes were present:

### Critical (9)

| CVE | Package | Installed | Fixed in |
|---|---|---|---|
| CVE-2026-2781  | libnss3              | 2:3.110-1               | 2:3.110-1+deb13u1 |
| CVE-2026-31789 | libssl3t64           | 3.5.4-1~deb13u2         | 3.5.5-1~deb13u2 |
| CVE-2026-32710 | libmariadb3          | 1:11.8.3-0+deb13u1      | 1:11.8.6-0+deb13u1 |
| CVE-2026-33845 | libgnutls30t64       | 3.8.9-3+deb13u1         | 3.8.9-3+deb13u4 |
| CVE-2026-42010 | libgnutls30t64       | 3.8.9-3+deb13u1         | 3.8.9-3+deb13u4 |
| CVE-2025-68121 | Go stdlib (entrypoint) | v1.24.6               | 1.24.13, 1.25.7, 1.26.0-rc.3 |

### High (38, top affected packages)

| # | Package | CVE examples |
|---|---|---|
| 15 | Go stdlib (entrypoint binary) | CVE-2025-61726, CVE-2026-27145, CVE-2026-32280-32283, CVE-2026-33811-33814, CVE-2026-39820/39822/39836, CVE-2026-42499/42504 |
| 6  | libssl3t64 / openssl / openssl-provider-legacy | CVE-2026-28387-28390, CVE-2026-45447 |
| 6  | libgnutls30t64 | CVE-2026-3833, CVE-2026-33846, CVE-2026-42009 |
| 3  | libpng16-16t64 | CVE-2026-22695, CVE-2026-22801, CVE-2026-25646 |
| 3  | libssh2-1t64 | CVE-2026-55199, CVE-2026-55200, CVE-2026-7598 |
| 2  | libcurl3t64-gnutls / libcurl4t64 | CVE-2026-5773, CVE-2026-6276 |
| 2  | libgif7 | CVE-2026-23868, CVE-2026-26740 |
| –  | libtiff6, libpoppler147, libnghttp2-14, libngtcp2-16, liblcms2-2, libgssapi-krb5-2, libcap2 | one each |

**Threat categories:**
- **TLS/crypto stack** (libssl, libgnutls, libssh2): certificate validation bypass, padding-oracle, handshake DoS — directly exploitable by any network client connecting to your DB.
- **Image parsing** (libpng, libtiff, libgif, libpoppler, liblcms): RCE via crafted payload, reachable from any SQL that links GDAL/PROJ (PostGIS raster input).
- **HTTP/mariadb client** (libcurl, libmariadb3): relevant if PostGIS does out-of-DB fetches or federated connections.
- **Go stdlib**: `net/http` issues in the `docker-entrypoint.sh` shell binary — not network-exposed in normal Postgres operation, but still an unnecessary exposure.

---

## 2. What the rebuild changes

### 2.1 Base image

- `FROM postgres:18.1` → `FROM postgres:18.4-bookworm`
- Old `18.1` was on **Debian trixie** (testing). New `18.4-bookworm` is on **Debian 12 stable**, which receives security fixes through `bookworm-security` promptly.
- Bugs fixed in PG 18.1 → 18.4 itself (PostgreSQL release notes for 18.2, 18.3, 18.4) come for free.

### 2.2 Extensions now pinned to specific release tags, built from source

| Extension | Old | New | Source |
|---|---|---|---|
| pgvector | 0.8.1 (from source already) | **0.8.5** | `https://github.com/pgvector/pgvector/releases/tag/v0.8.5` |
| PostGIS  | apt-resolved `postgresql-18-postgis-3` (unpinned, ~3.4.x) | **3.5.7** (pinned tag) | `https://github.com/postgis/postgis/archive/refs/tags/3.5.7.tar.gz` |

PostGIS 3.5.7 (2026/06/10) covers many CVEs and crash fixes that the apt-flow would have lagged on:
- `#5998` tiger_geocoder **CVE-2022-2625** owned-by-extension hardening
- `#6028` crash indexing malformed empty polygon
- `#5917` ST_Relate unresponsive
- `#5947` ST_ModEdgeHeal crash on corrupted topology
- `#5905` crash on deeply nested geometries
- `#5921` crash freeing uninitialized pointer
- `#5989` CurvePolygon distance error
- See [`NEWS`](https://github.com/postgis/postgis/blob/stable-3.5/NEWS) for 3.5.0 through 3.5.7 for the full list.

Optional PostGIS components the init script doesn't enable are now **disabled at `./configure` time** — closing the CVE surface of binaries that ship in the image but nobody uses:
- `--without-sfcgal` (CG_StraightSkeleton, CG_Visibility, etc.)
- `--without-address-standardizer`
- `--without-tiger-geocoder`

### 2.3 Multi-stage build — runtime image only contains runtime libs

```
FROM postgres:18.4-bookworm AS builder   # apt-get install all the -dev HEADERS + build tools
FROM postgres:18.4-bookworm               # only runtime libs (no gcc, no pkg-config, no -dev)
COPY --from=builder /usr/lib/postgresql/  /usr/lib/postgresql/
COPY --from=builder /usr/share/postgresql/ /usr/share/postgresql/
COPY --from=builder /usr/local/bin/raster2pgsql /usr/local/bin/shp2pgsql /usr/local/bin/
```

The shipped image has **no** `build-essential`, `git`, `wget`, `autoconf`, `automake`, `libtool`, `pkg-config`, `xsltproc`, `docbook-xsl`, `postgresql-server-dev-18`, or any `*-dev` header package. Anything an attacker could have tipped a compiler bug through is gone.

Runtime libs kept (with their own ongoing Debian security support, all in main):
`libgeos-c1v5`, `libproj25`, `libgdal32`, `libxml2`, `libjson-c5`, `libprotobuf-c1`, `libsqlite3-0`, `libcurl4`.

### 2.4 Supply chain

- Pinned `--branch v${PGVECTOR_VERSION}` / `refs/tags/${POSTGIS_VERSION}.tar.gz`.
- `LABEL org.opencontainers.image.source` points to the source repo.
- All build args (`PGVECTOR_VERSION`, `POSTGIS_VERSION`) are exposed so a future `--build-arg` bump is the **only** change required to upgrade.

---

## 3. Vulnerabilities remaining in the NEW image (`18.4.0`)

All 15 remaining HIGH/CRITICAL CVEs are in the **Go stdlib** of the upstream `postgres` Docker entrypoint binary (compiled by the postgres-docker maintainers with Go 1.24.6):

| CVE | Severity | Go stdlib fix |
|---|---|---|
| CVE-2025-68121 | CRITICAL | 1.24.13 / 1.25.7 / 1.26.0-rc.3 |
| CVE-2025-61726 | HIGH | 1.24.12 / 1.25.6 |
| CVE-2025-61729 | HIGH | 1.24.11 / 1.25.5 |
| CVE-2026-25679 | HIGH | 1.25.8 / 1.26.1 |
| CVE-2026-27145 | HIGH | 1.25.11 / 1.26.4 |
| CVE-2026-32280 | HIGH | 1.25.9 / 1.26.2 |
| CVE-2026-32281 | HIGH | 1.25.9 / 1.26.2 |
| CVE-2026-32283 | HIGH | 1.25.9 / 1.26.2 |
| CVE-2026-33811 | HIGH | 1.25.10 / 1.26.3 |
| CVE-2026-33814 | HIGH | 1.25.10 / 1.26.3 |
| CVE-2026-39820 | HIGH | 1.25.10 / 1.26.3 |
| CVE-2026-39822 | HIGH | 1.25.12 / 1.26.5 / 1.27.0-rc.2 |
| CVE-2026-39836 | HIGH | 1.25.10 / 1.26.3 |
| CVE-2026-42499 | HIGH | 1.25.10 / 1.26.3 |
| CVE-2026-42504 | HIGH | 1.25.11 / 1.26.4 |

**These cannot be patched by us.** They will be fixed when the upstream [`docker-library/postgres`](https://github.com/docker-library/postgres) team recompiles the entrypoint with Go ≥ 1.24.13 and publishes a new `18.4-bookworm` image. At that point, just `docker build` this Dockerfile again — the new upstream entrypoint will be picked up automatically.

### Why these are low-risk for a Postgres DB container
- The Go entrypoint binary only handles local startup orchestration. It is not exposed on the network.
- CVE-2025-68121 (the most severe) is a `net/http` issue reachable only if the container initiates outbound HTTP — which the entrypoint does not.

---

## 4. How to reproduce the scan

```bash
# Build the new image
docker build -t moustachir/postgres:18.4.0 \
  --build-arg PGVECTOR_VERSION=0.8.5 \
  --build-arg POSTGIS_VERSION=3.5.7 .

# Scan both (note: on Docker Desktop, mount the desktop socket)
SOCK=/home/$USER/.docker/desktop/docker.sock
docker run --rm \
  -v "$SOCK:/var/run/docker.sock" \
  -v "$PWD/.trivycache:/root/.cache/trivy" \
  aquasec/trivy:latest image \
  --severity HIGH,CRITICAL --ignore-unfixed \
  --format table --exit-code 0 \
  jesuph/moustachir-postgres:18.1

docker run --rm \
  -v "$SOCK:/var/run/docker.sock" \
  -v "$PWD/.trivycache:/root/.cache/trivy" \
  aquasec/trivy:latest image \
  --severity HIGH,CRITICAL --ignore-unfixed \
  --format table --exit-code 0 \
  moustachir/postgres:18.4.0
```

`.trivycache/` is a workspace-local directory; it's git-ignored. (Already added to `.gitignore`.)

---

## 5. What was changed in this commit

- `Dockerfile` — multi-stage build on `postgres:18.4-bookworm`, pinned pgvector 0.8.5 / PostGIS 3.5.7 from source, optional PostGIS components disabled, runtime-only apt install in final stage.
- `docker-compose.yml` — image tag `18.4.0`, args `PGVECTOR_VERSION=0.8.5`, `POSTGIS_VERSION=3.5.7`.
- `.github/workflows/docker-publish.yml` — fixed stray `\n`, added `POSTGIS_VERSION`, bumped `build-push-action` v5 → v6.
- `push-to-registry.sh` / `push-to-registry.ps1` — emit three tags (`:18.4.0`, `:18.4`, `:latest`) with the new build args.
- `README.md` — version table updated, Dokploy rollback/volume-check guidance added, examples retagged.
- `.gitignore` — added `.trivycache/`.
- `SECURITY.md` (this file).
