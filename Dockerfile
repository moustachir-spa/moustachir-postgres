##############################################
# Moustachir PostgreSQL Docker Image
# PostgreSQL 18.4 with popular extensions
#
# Built on Chainguard's postgres image (Wolfi
# glibc-based, minimal-CVE-by-design, no shell/
# package-manager cruft in the runtime image,
# continuously rebuilt so gosu/openssl/etc. stay
# current automatically). All external extensions
# are pinned to specific release tags and built
# from source for reproducibility & auditability.
#
# Note: Chainguard's free/public catalog only
# serves the `latest` / `latest-dev` tags (no
# version pinning) — see SECURITY.md §6 for why
# that's the intended, still-reproducible-in-
# practice usage pattern for this base.
##############################################

##############################################
# Build GDAL from source with a minimal driver
# set (pinned tag)
#
# Wolfi's own prebuilt `gdal` apk package has
# grown to pull in HDF5/Arrow/Parquet/OpenEXR —
# smaller than Debian's ~40-dependency build but
# still more than this image's raster workflows
# need. Building ourselves and only giving GDAL
# dev headers for GeoTIFF/PNG/JPEG (plus PROJ/
# GEOS/SQLite/curl, already needed for PostGIS)
# makes GDAL's CMake auto-detection skip the
# rest — no explicit --without-* flags needed.
##############################################
FROM cgr.dev/chainguard/postgres:latest-dev AS gdal-builder

ARG GDAL_VERSION=3.13.1

RUN apk update && apk add --no-cache \
        build-base \
        cmake \
        git \
        ca-certificates \
        pkgconf \
        geos-3.13-dev \
        proj-dev \
        sqlite-dev \
        curl-dev \
        tiff-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        expat-dev

# The base image's zstd cmake config (/usr/lib64/cmake/zstd/) is
# broken — zstdTargets.cmake references a static lib (libzstd.a) that
# isn't actually installed, so any find_package(zstd) hard-errors
# instead of gracefully reporting "not found". We don't need zstd for
# GDAL's GeoTIFF/PNG/JPEG-only build, so just remove the broken config
# rather than fight CMake's find_package/DISABLE_FIND_PACKAGE flags
# (tried both, config gets pulled in regardless — this is the one fix
# guaranteed to work since it removes the file actually erroring).
RUN rm -rf /usr/lib64/cmake/zstd

RUN set -eux; \
    git clone --depth 1 --branch v${GDAL_VERSION} https://github.com/OSGeo/gdal.git /tmp/gdal; \
    cd /tmp/gdal; \
    mkdir build; \
    cd build; \
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local/gdal \
        -DBUILD_APPS=OFF \
        -DBUILD_TESTING=OFF \
        -DBUILD_PYTHON_BINDINGS=OFF \
        -DBUILD_JAVA_BINDINGS=OFF \
        -DBUILD_CSHARP_BINDINGS=OFF \
    ; \
    cmake --build . -j"$(nproc)"; \
    cmake --install .; \
    rm -rf /tmp/gdal

##############################################
# Runtime libs for the final image
#
# The `latest` runtime tag has no apk/package
# manager at all (genuinely minimal, by design)
# so runtime .so files can't be `apk add`-ed
# directly into the final stage. Instead: install
# them into an isolated root here (same Wolfi
# repo/build as the final base image, so any
# overlap — libc, libstdc++, etc. — is byte-
# identical, not a conflicting duplicate) and
# copy that whole tree over in the final stage.
##############################################
FROM cgr.dev/chainguard/postgres:latest-dev AS runtime-libs

RUN set -eux; \
    apk update; \
    mkdir -p /rt; \
    apk add --no-cache --root /rt --initdb \
        --repository https://apk.cgr.dev/chainguard \
        --keys-dir /etc/apk/keys \
        geos-3.13 proj libcurl-openssl4 tiff libpng libjpeg-turbo expat libgomp \
        json-c protobuf-c

##############################################
# Build pgvector + PostGIS
##############################################
FROM cgr.dev/chainguard/postgres:latest-dev AS builder

ARG PGVECTOR_VERSION=0.8.5
ARG POSTGIS_VERSION=3.5.7

COPY --from=gdal-builder /usr/local/gdal /usr/local/gdal
RUN echo "/usr/local/gdal/lib64" > /etc/ld.so.conf.d/gdal.conf

RUN apk update && apk add --no-cache \
        # PostGIS build deps (dev headers only needed at build time)
        geos-3.13-dev \
        proj-dev \
        tiff-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        expat-dev \
        sqlite-dev \
        curl-dev \
        libxml2-dev \
        json-c-dev \
        protobuf-c-dev \
        protobuf-c-compiler \
        postgresql-18-dev \
        # Build tools
        build-base \
        git \
        wget \
        ca-certificates \
        autoconf \
        automake \
        libtool \
        pkgconf \
        libxslt \
        docbook-xml \
    && ldconfig

##############################################
# Build pgvector (pinned tag)
##############################################
# with_llvm=no: this image's postgres was built --with-llvm, so PGXS
# also tries to emit LLVM bitcode (.bc) via clang for JIT inlining —
# a nice-to-have, not required for functionality. Skip it rather than
# add a whole clang/LLVM toolchain just to produce it.
RUN set -eux; \
    cd /tmp; \
    git clone --depth 1 --branch v${PGVECTOR_VERSION} https://github.com/pgvector/pgvector.git; \
    cd pgvector; \
    make with_llvm=no; \
    make install with_llvm=no; \
    rm -rf /tmp/pgvector

##############################################
# Build PostGIS (pinned tag, supports PG 12-18)
# Requires GEOS 3.8+, PROJ 6.1+, GDAL 2.4+
# Disabled optional components we don't init:
#   - sfcgal, address_standardizer, tiger_geocoder
# This shrinks the binary and the CVE surface.
##############################################
RUN set -eux; \
    cd /tmp; \
    wget -q -O postgis.tar.gz "https://github.com/postgis/postgis/archive/refs/tags/${POSTGIS_VERSION}.tar.gz"; \
    mkdir -p postgis; \
    tar -xzf postgis.tar.gz -C postgis --strip-components=1; \
    rm postgis.tar.gz; \
    cd postgis; \
    ./autogen.sh; \
    ./configure \
        --with-pgconfig=/usr/bin/pg_config \
        --with-gdalconfig=/usr/local/gdal/bin/gdal-config \
        --without-sfcgal \
        --without-address-standardizer \
        --without-tiger-geocoder \
    ; \
    make -j"$(nproc)" with_llvm=no; \
    make install with_llvm=no; \
    rm -rf /tmp/postgis

##############################################
# Final image
##############################################
FROM cgr.dev/chainguard/postgres:latest

LABEL maintainer="moustachir"
LABEL description="PostgreSQL 18.4 (Chainguard/Wolfi) with the most popular extensions pre-installed and ready to use"
LABEL org.opencontainers.image.source="https://github.com/moustachir-spa/moustachir-postgres"

# Runtime-only libs. The `latest` tag ships no package manager at all
# (genuinely minimal, by design), so these come from the `runtime-libs`
# stage's isolated install instead of `apk add` here. We deliberately
# do NOT use Wolfi's prebuilt `gdal` package — we ship our own
# minimal-driver GDAL build instead (see gdal-builder stage) to avoid
# its HDF5/Arrow/Parquet/OpenEXR dependencies; geos/proj/curl/tiff/
# libpng/libjpeg-turbo/expat/libgomp here are what that build and
# PostGIS actually link against.
COPY --from=runtime-libs /rt/usr/lib/ /usr/lib/
RUN ldconfig

# Our minimal-driver GDAL build (see gdal-builder stage) — library +
# data files only, no headers/CLI apps/cmake exports needed at runtime.
COPY --from=gdal-builder /usr/local/gdal/lib64/ /usr/local/gdal/lib64/
COPY --from=gdal-builder /usr/local/gdal/share/gdal/ /usr/local/gdal/share/gdal/
RUN echo "/usr/local/gdal/lib64" > /etc/ld.so.conf.d/gdal.conf && ldconfig
ENV GDAL_DATA=/usr/local/gdal/share/gdal

# Copy compiled extension files from the builder stage — pgvector +
# PostGIS shared libs, control/sql files, and the raster2pgsql/
# shp2pgsql loader binaries (PostGIS installs these to /usr/local/bin
# regardless of --with-pgconfig's own bindir).
COPY --from=builder /usr/lib/postgresql18/ /usr/lib/postgresql18/
COPY --from=builder /usr/share/postgresql18/ /usr/share/postgresql18/
COPY --from=builder /usr/local/bin/raster2pgsql /usr/local/bin/shp2pgsql /usr/local/bin/

##############################################
# 2. Copy initialization scripts
#    These run on first container start to
#    create extensions in template1 + default db.
#    Note: this base's entrypoint scans
#    /var/lib/postgres/initdb/, not the Debian
#    convention /docker-entrypoint-initdb.d/.
##############################################
COPY initdb/ /var/lib/postgres/initdb/
RUN chmod +x /var/lib/postgres/initdb/*.sh

EXPOSE 5432

##############################################
# 3. Start PostgreSQL with shared libraries
#    pg_stat_statements needs to be loaded
#    via shared_preload_libraries
##############################################
# Base image's ENTRYPOINT already bakes in "postgres" as the fixed
# first arg (unlike the official docker-library image, where CMD has
# to supply it) — CMD here only needs the extra flags.
CMD ["-c", "shared_preload_libraries=pg_stat_statements"]
