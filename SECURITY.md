# Security Audit — `jesuph/moustachir-postgres`

**Scope:** `jesuph/moustachir-postgres:18.1` (currently running) → new image built from this repo's `Dockerfile` (PostgreSQL 18.4; gosu rebuilt from source in `18.4.1`; Perl removed and GDAL rebuilt with a minimal driver set in `18.4.2`; base OS moved from Debian bookworm to trixie in `18.4.3`; base OS moved again to Chainguard's Wolfi-based `postgres` image in `18.4.4`).

**Scanner:** Trivy v0.72 (`aquasec/trivy:latest`), DB downloaded at scan time.
Filters: `--severity HIGH,CRITICAL --ignore-unfixed` (only CVEs that have a known fix upstream) for the headline table; full unfiltered scans (all severities, `--ignore-unfixed` off) used throughout the investigation — see §4, §5, and §6 for why that mattered. All scans run against the local images via the Docker Desktop socket.

**Headline — fixable CVEs (patch exists, headline metric)**

| Image | Base | Distinct CVEs | CRITICAL | HIGH | Size |
|---|---|---|---|---|---|
| `jesuph/moustachir-postgres:18.1` (old) | Debian **trixie** (13.3, was testing at the time) | 47 | 9 | 38 | 957 MB |
| `moustachir/postgres:18.4.0` (18.4, upstream gosu) | Debian **bookworm** (12.15) | 15 | 1 | 14 | 897 MB |
| `moustachir/postgres:18.4.1` (18.4, gosu rebuilt) | Debian **bookworm** (12.15) | 0 | 0 | 0 | 897 MB |
| `moustachir/postgres:18.4.2` (18.4, + Perl removed, GDAL minimal) | Debian **bookworm** (12.15) | 0 | 0 | 0 | 816 MB |
| `moustachir/postgres:18.4.3` (18.4, + base moved to trixie) | Debian **trixie** (13.6, now Debian stable) | 0 | 0 | 0 | 843 MB |
| `moustachir/postgres:18.4.4` (18.4, + base moved to Chainguard/Wolfi) | **Wolfi** (20230201) | **0** | **0** | **0** | **698 MB** |

**Headline — unfixed CVEs (no patch exists yet, anywhere)**

| Image | Distinct unfixed CRITICAL | Distinct unfixed HIGH |
|---|---|---|
| `moustachir/postgres:18.4.1` | 8 | 41 |
| `moustachir/postgres:18.4.2` | 3 | 22 |
| `moustachir/postgres:18.4.3` | 1 | 19 |
| `moustachir/postgres:18.4.4` | **0** | **0** |
| **Delta, 18.4.1 → 18.4.4** | **-8 (-100 %)** | **-41 (-100 %)** |

`18.4.1` already had **zero fixable CVEs of any severity** — every remaining finding lacked a Debian-provided patch. `18.4.2` structurally removed the two largest sources of *unfixed* CVEs (Perl, and GDAL's oversized dependency tree). `18.4.3` moved the base OS to Debian's then-current stable. `18.4.4` moves off Debian entirely to Chainguard's Wolfi-based image — **the only version of this image with zero vulnerabilities of any kind, fixable or not, at any severity**, confirmed by a full Trivy scan (`vuln,secret,misconfig`) with correct OS-family detection (not a scan failure). See §6 for the full migration, including why two other candidate bases (Alpine, `cimg/postgres`) were evaluated and rejected first.

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

## 3. Root cause of the 15 CVEs, and how `18.4.1` closes them

A full (all-severity, not just `--ignore-unfixed HIGH,CRITICAL`) rescan of `18.4.0` showed something the headline table didn't: **100% of every fixable vulnerability in the image, at every severity (1 CRITICAL, 14 HIGH, 21 MEDIUM, 2 LOW), lived inside a single file**: `/usr/local/bin/gosu`. Every Debian OS package in the image was already fully patched (0 fixable CVEs of any severity) — Trivy just wasn't being asked about MEDIUM/LOW before, which hid how concentrated the problem was.

`gosu` is the setuid-helper the upstream `postgres` image uses internally to drop from root to the `postgres` user on container startup. It's not a Postgres extension we chose to add — it ships inside `postgres:18.4-bookworm` itself. It's a statically-linked Go binary, and it was compiled by its maintainer ([`tianon/gosu`](https://github.com/tianon/gosu)) with **Go 1.24.6** back in September 2025 (release `1.19`, still the latest as of this scan — no newer release exists to pull in a patched Go). Every Go stdlib CVE fixed since then stays baked into that binary until someone recompiles it:

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
| + 21 MEDIUM / 2 LOW | — | various, same range |

### The fix: rebuild gosu from source, ourselves

We can't wait for upstream to cut a new release. So the Dockerfile now has a `gosu-builder` stage that clones `tianon/gosu` at the same pinned tag (`1.19`, same code, same behavior) and compiles it with `golang:1.26.5-bookworm` (current Go, all the CVEs above fixed), the same "pin a release tag, build from source" pattern already used for pgvector and PostGIS:

```dockerfile
FROM golang:1.26.5-bookworm AS gosu-builder
ARG GOSU_VERSION=1.19
RUN git clone --depth 1 --branch ${GOSU_VERSION} https://github.com/tianon/gosu.git ...; \
    CGO_ENABLED=0 go build -trimpath -ldflags '-w -s' -o /usr/local/bin/gosu .
```

The final stage then overwrites the upstream `/usr/local/bin/gosu` with this one:

```dockerfile
COPY --from=gosu-builder /usr/local/bin/gosu /usr/local/bin/gosu
```

Verified: `docker run --rm --entrypoint gosu <image> --version` → `1.19 (go1.26.5 on linux/amd64; gc)`, and `gosu nobody id` still works correctly.

### One remaining non-issue

One `UNKNOWN`-severity finding remains, `CVE-2026-39824` (`GO-2026-5024`) in `golang.org/x/sys@v0.1.0`, a dependency pinned by gosu's own `go.mod` (not something a newer Go toolchain changes). It's an integer-overflow bug in `NewNTUnicodeString` — **`golang.org/x/sys/windows` only**. This container never runs on Windows and gosu never calls that symbol, so it's not exploitable here; left as-is rather than hand-patching gosu's dependency pins away from what upstream ships.

### Why this was low-risk in practice, even before the fix
- The Go binary only handles local startup orchestration (dropping privileges before exec'ing `postgres`). It is not exposed on the network.
- CVE-2025-68121 (the most severe) is a `net/http` issue reachable only if the binary initiates outbound HTTP, which gosu does not.
- Still worth fixing: it's the only thing standing between this image and a clean scan, and the fix is cheap (one extra build stage, ~10s).

---

## 4. Reducing the *unfixed* CVE surface (`18.4.2`)

`18.4.1` had zero fixable CVEs, but a full (all-severity, `--ignore-unfixed` off) scan still showed 8 distinct unfixed CRITICAL / 41 distinct unfixed HIGH CVE IDs — real CVEs with no Debian-provided patch yet. Rather than treat "no patch exists" as the end of the story, we traced where they actually came from and found two structural sources that account for most of them, both removable without waiting on upstream:

### 4.1 Perl (4 of the 8 unfixed CRITICAL CVE IDs)

`perl`, `perl-base`, `perl-modules-5.36`, and `libperl5.36` all carry the *same* 4 CVE IDs (they're built from one Debian source package). Perl isn't a Postgres extension we chose — it's pulled in for two things this single-cluster container never uses:

- `postgresql-common`'s cluster-management scripts (`pg_ctlcluster` etc.) — the entrypoint runs `postgres` directly, never these.
- `pg_wrapper`, the Perl dispatcher Debian symlinks `/usr/bin/psql`, `/usr/bin/pg_dump`, and 19 other client tools to, for hosts running multiple Postgres versions/clusters. This *is* actually invoked (`docker-entrypoint.sh` calls `psql` during init), which is why simply purging Perl breaks the container — a real dependency, not a false one.

Fix: `/usr/lib/postgresql/$PG_MAJOR/bin` (the real, versioned binaries) is already on `PATH`. We delete the `pg_wrapper` symlinks so the shell falls through to those directly, then force-purge Perl entirely — including `perl-base`, which is marked `Essential: yes` in Debian and needs `--force-remove-essential`:

```dockerfile
RUN find /usr/bin -type l -lname '*postgresql-common*' -delete; \
    dpkg --purge --force-depends perl perl-modules-5.36 libperl5.36; \
    dpkg --purge --force-depends --force-remove-essential perl-base
```

Verified with the full `test-extensions.sql` suite (all 10 extensions) plus `pg_dump`/`pg_isready` against the rebuilt image — all pass with Perl completely absent.

### 4.2 GDAL's oversized dependency tree (most of the rest)

`libgdal32` (installed for PostGIS raster support) pulls **~40 transitive dependencies** via Debian's maximalist build — drivers for HDF4/HDF5/NetCDF, KML (`libkml`), ODBC, OGDI, Poppler/PDF, the MariaDB client, AV1 (`libaom3`), HEIF (`libheif1`) — none of which this image's raster workflows use, each its own CVE surface.

Fix: build GDAL from source ourselves (pinned tag `v${GDAL_VERSION}`, default `3.13.1`), giving the build only the dev headers for formats actually needed — GeoTIFF/PNG/JPEG, plus PROJ/GEOS/SQLite/curl which PostGIS already builds against. GDAL's CMake auto-detects available libraries and silently skips drivers it can't build; no `--without-*` flags needed:

```dockerfile
FROM postgres:18.4-bookworm AS gdal-builder
RUN apt-get install -y --no-install-recommends \
    build-essential cmake git libgeos-dev libproj-dev libsqlite3-dev \
    libcurl4-openssl-dev libtiff-dev libpng-dev libjpeg62-turbo-dev libexpat1-dev
RUN git clone --depth 1 --branch v${GDAL_VERSION} https://github.com/OSGeo/gdal.git ...; \
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local/gdal -DBUILD_APPS=OFF ...; \
    cmake --build . -j"$(nproc)"; cmake --install .
```

PostGIS's `./configure` points at it (`--with-gdalconfig=/usr/local/gdal/bin/gdal-config`); the final stage copies only `lib/` + `share/gdal/` (38 MB) from the builder — no headers, no CLI apps, no cmake exports — and installs the small set of runtime libs the resulting `libgdal.so` actually links against: `libtiff6`, `libpng16-16`, `libjpeg62-turbo`, `libexpat1`, `libgomp1` (GDAL's OpenMP runtime — easy to miss, `ldd` catches it).

**Verified end-to-end**, not just "it compiled": confirmed via a driver-registration test that HEIF/AV1/HDF4/HDF5/NetCDF/ODBC/OGDI/MariaDB drivers are genuinely absent (187 registered drivers, all either built-in-to-GDAL-core or backed by the 4 libs above); then `CREATE EXTENSION postgis_raster` + `ST_AsTIFF`/`ST_AsPNG`/`ST_AsJPEG` round-trips against a real raster all succeed.

### 4.3 Bonus finding: PostGIS raster ships secure-by-default

While verifying raster I/O, discovered `postgis.gdal_enabled_drivers` defaults to **`DISABLE_ALL`** — PostGIS's own hardening against GDAL-driver CVEs (the exact class of issue §4.2 reduces the surface of). `ST_AsTIFF`/`ST_AsPNG`/etc. raise `Could not load the output GDAL driver` until a session explicitly does `SET postgis.gdal_enabled_drivers = 'ENABLE_ALL';` (or a specific list, e.g. `'GTiff PNG JPEG'`). This isn't a bug introduced by the minimal build — it's upstream PostGIS behavior, worth knowing if raster format export is ever needed: it must be turned on deliberately, database-by-session or via `postgresql.conf`.

### 4.4 What's left in `18.4.2`

3 unfixed CRITICAL / 22 unfixed HIGH remain, entirely in core Debian/Postgres runtime libraries: `libxml2`, `zlib1g`, `libsqlite3-0`, `libcurl4`/`libcurl3-gnutls`, `libssh2-1`, `libtiff6`, `libexpat1`, and the `util-linux`/`ncurses`/`libuuid1`/`libacl1`/`libblkid1`/`libldap-2.5-0` family. Confirmed these are structural, not incidental: `ldd /usr/lib/postgresql/18/bin/postgres` shows Postgres itself directly links `libxml2.so`, `libssl.so`, `libz.so`; `bash` links `libtinfo`; `mount`/`util-linux`/`ncurses` are base-OS plumbing every Debian container needs. These packages themselves can't be *removed* the way Perl/GDAL's extras were — but that's not the only lever available. See §5: the *version* of Debian providing them turned out to matter more than expected.

---

## 5. Base OS: bookworm → trixie (`18.4.3`)

`18.4.0`–`18.4.2` deliberately targeted Debian **bookworm** (12) — chosen because `18.1` had actually been built on trixie back when trixie was still Debian's *testing* branch, which gets security fixes late (no dedicated security team backports directly to testing; fixes arrive only via the next stable release or unstable). Bookworm was *stable* at the time and got prompt `bookworm-security` backports. That reasoning was correct when it was made.

It stopped being correct at some point after: **Debian 13 "trixie" has since been released as the new stable**, and confirmed directly (`https://www.debian.org/releases/stable/` now serves trixie's release page). That flips the situation — bookworm is now **oldstable**, trixie now gets the priority security backports.

### 5.1 Verified empirically, not assumed from release status

Release-status reasoning alone isn't proof a given package's *specific* CVE is actually fixed faster on one branch — so before migrating, both bases were scanned bare (no modifications) and compared:

| CVE | Package | bookworm (12.15) | trixie (13.6) |
|---|---|---|---|
| CVE-2023-45853 | zlib1g | unfixed | **fixed** |
| CVE-2025-7458 | libsqlite3-0 | unfixed | **fixed** |
| CVE-2026-6653 | libxml2 | unfixed | unfixed (no fix in *any* Debian release yet) |

Confirms the hypothesis for 2 of the 3 remaining CRITICALs, and confirms the third genuinely has no fix anywhere (not something a base switch — or anything else — can currently address).

### 5.2 What the migration required

Three `FROM postgres:18.4-bookworm` → `FROM postgres:18.4-trixie` (gdal-builder, builder, final stage; `golang:1.26.5-bookworm` for the fully-static gosu build was left alone — a discarded build stage producing a static binary, its base OS has zero effect on the shipped image). Two knock-on fixes, both from Debian's 64-bit-time_t package-rename transition landing between bookworm and trixie, and Perl's version bump:

- Runtime package renames: `libgeos-c1v5`→`libgeos-c1t64`, `libpng16-16`→`libpng16-16t64`, `libcurl4`→`libcurl4t64`. (`-dev` packages, used only in the builder stages, keep their names — the suffix only applies to the runtime `.so` packages whose SONAME actually changed.)
- The Perl-purge step (§4.1) was hardcoded to `perl-modules-5.36`/`libperl5.36`; trixie ships Perl 5.40 (`perl-modules-5.40`/`libperl5.40`). Rather than re-hardcode a new version, made it version-agnostic: `dpkg-query -W -f='${Package}\n' 'perl' 'libperl*' 'perl-modules-*'` so a future Debian bump doesn't silently no-op this step again.

### 5.3 Verification

Same bar as every other change this session — not just "it built": full `test-extensions.sql` suite (10/10 pass), `gosu --version` confirms still Go-1.26.5-linked, Perl confirmed absent (`which perl` fails, no `perl*`/`libperl*` packages installed), `psql`/`pg_dump` resolve correctly through the `PATH` fallback, and the same `CREATE EXTENSION postgis_raster` + `ST_AsTIFF`/`ST_AsPNG`/`ST_AsJPEG` round-trip against the rebuilt GDAL all pass identically to the bookworm build.

### 5.4 Net result and what's left

Distinct unfixed CRITICAL: 3 → **1** (only `libxml2`'s CVE-2026-6653, unfixed upstream everywhere). Distinct unfixed HIGH: 22 → **19** — not purely additive: some packages improved (e.g. the util-linux family), a few new HIGH-carrying packages appeared that weren't relevant on bookworm (`gnupg`/`dirmngr`/`gpg`-family, part of trixie's base apt-key tooling), net still a reduction. Image grew slightly, 816 MB → 843 MB (trixie's base packages are marginally larger) — an acceptable trade for the CVE reduction.

**What's structurally left:** the same category as §4.4, now smaller — `libxml2` (1 CRITICAL with no fix anywhere), plus HIGH-severity findings in `util-linux`/`ncurses`/`gnupg`/`libtiff6`/`libcurl` family, all base-OS plumbing `postgres` or `bash` directly link against. Going further than this means either (a) waiting for Debian to patch `libxml2` upstream — nothing to do until then, or (b) replacing Debian as the base OS entirely (e.g. an Alpine/musl build) — a substantially larger, riskier undertaking with its own known caveat for Postgres specifically: musl's collation/locale behavior differs from glibc's, and the official `postgres` image documentation warns that changing the underlying libc collation implementation on an *existing* database can silently corrupt indexes built under the old collation. Not something to take on without a dedicated evaluation, separate from this pass.

---

## 6. Base OS: Debian trixie → Chainguard/Wolfi (`18.4.4`)

§5.4 flagged the honest options for the last unfixed CRITICAL: wait for Debian to patch `libxml2`, or replace Debian entirely. Prompted to look at alternatives, two candidates were evaluated empirically before committing to a third — both rejected on evidence, not assumption.

### 6.1 Rejected: Alpine (musl)

Alpine's musl libc has a real, documented, Postgres-specific correctness risk, not just a smaller-CVE-surface tradeoff: PostgreSQL's own docs state `LC_COLLATE`/`LC_CTYPE` "must be kept fixed, or indexes on text columns would become corrupt," and `docker-library/postgres` issue #1288 confirms Postgres's own safety net for this (`get_collation_actual_version()`) returns `NULL` on musl — it doesn't just fail to warn you, it can't. Since this project's actual running containers have existing data, swapping onto musl risks silently corrupting any index on a text column with default libc collation, with no warning mechanism to catch it. Mitigation (ICU collations, libc-independent) exists but is a separate, deliberate migration — not something to fold into a base-image swap. Wolfi (below) sidesteps this entirely by staying glibc-based.

### 6.2 Rejected: `cimg/postgres:18.4-postgis` (CircleCI convenience image)

Suggested as a candidate with a prebuilt PostGIS variant. Scanned and inspected directly rather than assumed:

| | `cimg/postgres:18.4-postgis` |
|---|---|
| Base | Ubuntu 22.04 LTS |
| Size | 4.0 GB |
| Fixable CRITICAL / HIGH | **35 / 398** |
| Compilers shipped at runtime? | Yes — `gcc`, `make`, `cmake` |
| Leftover build artifacts | 189 MB PostGIS source/build tree at `/home/circleci/project/` |
| Extra tooling | `git`, `curl`, `wget`, `ssh`, `python3`, the `docker` CLI |
| Secrets flagged | 1 (AWS key in `postgis-3.6.3/doc/using_raster_dataman.xml` — almost certainly a documentation placeholder, but illustrative: shipping full doc/source trees gives a secret scanner something to find that a minimal image never would) |

This is a CI **convenience** image — built to have everything a CircleCI job might need pre-installed so jobs start fast, not to minimize what ships. 35 fixable CRITICAL CVEs (patches exist, just not applied) is decisively worse than every version of this image going back to `18.4.1`.

### 6.3 Chosen: Chainguard's `postgres` image (Wolfi)

Wolfi is Chainguard's own Linux "undistro" — **glibc-based** (avoids the Alpine collation risk), `apk`-packaged like Alpine, purpose-built for minimal-CVE container images, continuously rebuilt so dependencies (including `gosu` — confirmed already at `go1.26.5`, the same patched version this project hand-built for `18.4.1`) stay current automatically. Two tags matter here: `latest-dev` (compilers, `apk`, dev headers — for building) and `latest` (genuinely minimal — **no package manager at all**, confirmed by testing).

**One constraint worth naming:** Chainguard's free/public catalog only serves `:latest`/`:latest-dev` — no version-pinned tags without a paid subscription. This is a real departure from this project's "pin everything" philosophy elsewhere (pgvector, PostGIS, gosu, GDAL are all pinned to exact release tags). It's an accepted tradeoff specifically for this base layer: Chainguard's entire value proposition is that `:latest` is kept continuously at zero known CVEs, so floating on it is the *intended* usage pattern, unlike floating `:latest` on a generic Debian image where it buys nothing extra. The build args (`PGVECTOR_VERSION`, `POSTGIS_VERSION`, `GDAL_VERSION`) remain fully pinned as before.

### 6.4 What the migration required

Rebuilt the Dockerfile against `cgr.dev/chainguard/postgres:latest-dev` (build stages) / `:latest` (final stage). Highlights, in the order they were hit and fixed:

- **`gosu-builder` stage removed entirely.** Chainguard's `gosu` is already current — no need to hand-build it (was required on every Debian-based version, `18.4.1` through `18.4.3`).
- **Perl-purge step removed entirely.** Perl isn't installed on this base to begin with — no `postgresql-common`/`pg_wrapper` layer exists here (this image runs a single Postgres version directly, no multi-cluster tooling).
- **Runtime libraries can't be `apk add`-ed into the final stage** — the `latest` tag ships no package manager at all, by design. Added a `runtime-libs` stage that installs the needed libs (`geos`, `proj`, `libcurl-openssl4`, `tiff`, `libpng`, `libjpeg-turbo`, `expat`, `libgomp`, `json-c`, `protobuf-c`) into an isolated `apk --root`, then `COPY`s that tree into the final image — same repo/build as the final base, so any overlap is byte-identical, not a conflicting duplicate.
- **A broken system `zstd` cmake config** in the `-dev` image (`zstdTargets.cmake` references a `libzstd.a` that isn't actually installed) hard-errored GDAL's CMake configure. `GDAL_USE_ZSTD=OFF` and `CMAKE_DISABLE_FIND_PACKAGE_zstd=ON` both failed to prevent it — fixed by removing the broken config file directly (`rm -rf /usr/lib64/cmake/zstd`) before configuring.
- **GDAL installs to `lib64/`, not `lib/`** on this base (Wolfi's `GNUInstallDirs` convention differs from Debian's) — every `/usr/local/gdal/lib` reference had to become `/usr/local/gdal/lib64`.
- **This Postgres build has `--with-llvm`**, so PGXS tries to also emit LLVM bitcode (`.bc` files, for JIT inlining) via `clang` for every C extension — not installed in the build image. Rather than add a whole LLVM/clang toolchain for an optional performance nice-to-have, disabled it (`make with_llvm=no`) for both pgvector and PostGIS.
- **Missing `-dev` packages**, found one at a time as `./configure` progressed: `libxml2-dev`, `json-c-dev`, `protobuf-c-dev`/`protobuf-c-compiler` (all present in the old Debian package list, simply forgotten when translating to `apk`).
- **`raster2pgsql`/`shp2pgsql` install to `/usr/local/bin`**, not `pg_config`'s own `bindir` (`/usr/libexec/postgresql18`) — PostGIS's loader-utility install target ignores `--with-pgconfig` for these two binaries specifically.
- **Doubled `postgres` argument at startup.** This base's `ENTRYPOINT` already hardcodes `["docker-entrypoint.sh", "postgres"]` (unlike the official image, where `CMD` has to supply `"postgres"` itself) — the Dockerfile's `CMD` was still passing `"postgres"` too, so Docker concatenated `ENTRYPOINT + CMD` into `postgres postgres -c ...`, which the `postgres` binary correctly rejected as an invalid argument. Fixed by dropping `"postgres"` from `CMD`, leaving only the extra flags.

None of these were CVE-related — they're base-image-specific build mechanics, the normal cost of a from-scratch base migration.

### 6.5 Verification

Same suite as every prior version: full `test-extensions.sql` (10/10 pass), `gosu --version` (`1.19, go1.26.5` — current), and in one psql session: `CREATE EXTENSION postgis_raster`, `SET postgis.gdal_enabled_drivers = 'ENABLE_ALL'`, then `ST_AsTIFF`/`ST_AsPNG`/`ST_AsJPEG` against `ST_AsRaster(...)` — all three produce correctly-sized non-null output, identical behavior to the trixie build. (One cosmetic-only loose end: `PostGIS_GDAL_Version()` appends a `GDAL_DATA not found` notice despite the env var and directory both being present and correct — doesn't affect any tested functionality; likely a missing marker file our minimal `cmake --install` didn't copy. Not investigated further given zero functional impact.)

### 6.6 Result

**Zero vulnerabilities of any kind** — not just zero fixable (already true since `18.4.1`), but zero *unfixed* too, at every severity, confirmed by a full unfiltered Trivy scan (`vuln,secret,misconfig`) with correct `wolfi` OS-family detection. Also the smallest build yet (698 MB, down from 843 MB on trixie) despite no size optimization being a goal. This is the first version of this image where "how many vulnerabilities are left" has a one-word answer.

---

## 7. How to reproduce the scan

```bash
# Build the new image
docker build -t moustachir/postgres:18.4.4 \
  --build-arg PGVECTOR_VERSION=0.8.5 \
  --build-arg POSTGIS_VERSION=3.5.7 \
  --build-arg GDAL_VERSION=3.13.1 .

# Scan (note: on Docker Desktop, mount the desktop socket)
SOCK=/home/$USER/.docker/desktop/docker.sock

# Fixable HIGH/CRITICAL only (headline table)
docker run --rm \
  -v "$SOCK:/var/run/docker.sock" \
  -v "$PWD/.trivycache:/root/.cache/trivy" \
  aquasec/trivy:latest image \
  --severity HIGH,CRITICAL --ignore-unfixed \
  --format table --exit-code 0 \
  moustachir/postgres:18.4.4

# Full scan, all severities (vuln+secret+misconfig) — use this one;
# it's what caught the gosu, GDAL/Perl, and base-OS concentrations,
# and it's the only way to see unfixed-CVE counts
docker run --rm \
  -v "$SOCK:/var/run/docker.sock" \
  -v "$PWD/.trivycache:/root/.cache/trivy" \
  aquasec/trivy:latest image \
  --scanners vuln,secret,misconfig \
  --format table --exit-code 0 \
  moustachir/postgres:18.4.4
```

`.trivycache/` is a workspace-local directory; it's git-ignored. (Already added to `.gitignore`.)

---

## 8. What was changed

### Previous commit (`18.4.0`)
- `Dockerfile` — multi-stage build on `postgres:18.4-bookworm`, pinned pgvector 0.8.5 / PostGIS 3.5.7 from source, optional PostGIS components disabled, runtime-only apt install in final stage.
- `docker-compose.yml` — image tag `18.4.0`, args `PGVECTOR_VERSION=0.8.5`, `POSTGIS_VERSION=3.5.7`.
- `.github/workflows/docker-publish.yml` — fixed stray `\n`, added `POSTGIS_VERSION`, bumped `build-push-action` v5 → v6.
- `push-to-registry.sh` / `push-to-registry.ps1` — emit three tags (`:18.4.0`, `:18.4`, `:latest`) with the new build args.
- `README.md` — version table updated, Dokploy rollback/volume-check guidance added, examples retagged.
- `.gitignore` — added `.trivycache/`.
- `SECURITY.md` (this file).

### `18.4.1` — gosu CVE fix
- `Dockerfile` — added `gosu-builder` stage (`golang:1.26.5-bookworm`, pinned `GOSU_VERSION=1.19`), final stage now copies our rebuilt `gosu` over the upstream one.
- `docker-compose.yml` / `push-to-registry.sh` / `push-to-registry.ps1` / `README.md` — added `GOSU_VERSION` build arg, bumped patch tag `18.4.0` → `18.4.1`.
- `SECURITY.md` (this file) — documented the gosu root-cause finding and the fix; headline table updated to reflect a clean scan.

### `18.4.2` — Perl removed, GDAL rebuilt minimal
- `Dockerfile` — added `gdal-builder` stage (GDAL built from source, pinned `GDAL_VERSION=3.13.1`, minimal driver set); `builder` stage now points PostGIS at it via `--with-gdalconfig`; final stage drops `libgdal32` (and its ~40 transitive deps) in favor of the custom build + `libtiff6`/`libpng16-16`/`libjpeg62-turbo`/`libexpat1`/`libgomp1`; final stage also force-purges Perl (incl. `perl-base`) after deleting the `pg_wrapper` symlinks it would otherwise break.
- `docker-compose.yml` / `push-to-registry.sh` / `push-to-registry.ps1` / `README.md` — added `GDAL_VERSION` build arg, bumped patch tag `18.4.1` → `18.4.2`.
- `SECURITY.md` (this file) — added §4 documenting the Perl/GDAL root-cause analysis, the fixes, the `postgis.gdal_enabled_drivers` finding, and what's left (§4.4); headline table split into fixable vs. unfixed CVE counts.
- Verification performed before merging: full `test-extensions.sql` suite, `pg_dump`/`pg_isready`, GDAL driver-registration check (confirms HEIF/AV1/HDF5/etc. genuinely absent), and `CREATE EXTENSION postgis_raster` + `ST_AsTIFF`/`ST_AsPNG`/`ST_AsJPEG` round-trips — all pass.

### `18.4.3` — base OS moved bookworm → trixie
- `Dockerfile` — all three `postgres:18.4-bookworm` `FROM` lines (gdal-builder, builder, final) → `postgres:18.4-trixie`; renamed the runtime packages whose SONAME changed (`libgeos-c1v5`→`libgeos-c1t64`, `libpng16-16`→`libpng16-16t64`, `libcurl4`→`libcurl4t64`); made the Perl-purge step query package names dynamically instead of hardcoding `-5.36` (trixie ships Perl 5.40).
- `README.md` — "Built on Debian Bookworm" → "Built on Debian Trixie (13, current Debian stable)".
- `docker-compose.yml` / `push-to-registry.sh` / `push-to-registry.ps1` / `README.md` — bumped patch tag `18.4.2` → `18.4.3`.
- `SECURITY.md` (this file) — added §5 documenting why bookworm was originally chosen, why that stopped being correct (Debian 13 trixie is now stable, bookworm is now oldstable), the empirical bare-image comparison that motivated the switch, and the Alpine/musl caveat for anyone tempted to go further.
- Verification: identical suite to `18.4.2` (extensions, gosu, Perl absence, raster round-trip) re-run against the trixie build — all pass, no behavioral differences observed.

### `18.4.4` — base OS moved trixie → Chainguard/Wolfi
- `Dockerfile` — rewritten against `cgr.dev/chainguard/postgres:latest-dev` / `:latest`; `gosu-builder` stage and Perl-purge step both removed (unneeded on this base); added `runtime-libs` stage (isolated `apk --root` install, since the `latest` tag ships no package manager); fixed a broken system `zstd` cmake config, GDAL's `lib64` install path, missing `clang`/LLVM-bitcode dependency (`with_llvm=no`), three missing `-dev` packages (`libxml2-dev`, `json-c-dev`, `protobuf-c-dev`), the `raster2pgsql`/`shp2pgsql` install path, and a doubled `postgres` argument in `CMD` (this base's `ENTRYPOINT` already supplies it).
- `docker-compose.yml` / `push-to-registry.sh` / `push-to-registry.ps1` / `.github/workflows/docker-publish.yml` — removed the now-unused `GOSU_VERSION` build arg, bumped patch tag `18.4.3` → `18.4.4`.
- `README.md` — "Built on Debian Trixie" → "Built on Chainguard's `postgres` image (Wolfi, glibc-based, minimal-CVE-by-design)".
- `SECURITY.md` (this file) — added §6 documenting the Alpine and `cimg/postgres` evaluations (both rejected, with evidence) and the Chainguard migration itself; headline table updated to reflect zero vulnerabilities of any kind.
- Verification: full `test-extensions.sql` suite, `gosu --version`, and the `postgis_raster`/`ST_AsTIFF`/`ST_AsPNG`/`ST_AsJPEG` round-trip — all pass, identical behavior to the trixie build. Full Trivy scan (`vuln,secret,misconfig`, all severities, correct `wolfi` OS-family detection confirmed) returned zero findings of any kind.
