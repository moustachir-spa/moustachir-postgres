##############################################
# Moustachir PostgreSQL Docker Image
# PostgreSQL 18.4 with popular extensions
#
# All external extensions are pinned to
# specific release tags and built from
# source for reproducibility & auditability.
##############################################
FROM postgres:18.4-bookworm AS builder

ARG PGVECTOR_VERSION=0.8.5
ARG POSTGIS_VERSION=3.5.7

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # PostGIS build deps (dev headers only needed at build time)
        libgeos-dev \
        libproj-dev \
        libgdal-dev \
        libxml2-dev \
        libjson-c-dev \
        libprotobuf-c-dev \
        protobuf-c-compiler \
        libsqlite3-dev \
        libcurl4-openssl-dev \
        # Build tools
        build-essential \
        git \
        wget \
        ca-certificates \
        autoconf \
        automake \
        libtool \
        pkg-config \
        xsltproc \
        docbook-xsl \
        postgresql-server-dev-$PG_MAJOR \
    ; \
    rm -rf /var/lib/apt/lists/*

##############################################
# Build pgvector (pinned tag)
##############################################
RUN set -eux; \
    cd /tmp; \
    git clone --depth 1 --branch v${PGVECTOR_VERSION} https://github.com/pgvector/pgvector.git; \
    cd pgvector; \
    make; \
    make install; \
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
        --with-pgconfig=/usr/lib/postgresql/$PG_MAJOR/bin/pg_config \
        --without-sfcgal \
        --without-address-standardizer \
        --without-tiger-geocoder \
    ; \
    make -j"$(nproc)"; \
    make install; \
    rm -rf /tmp/postgis

##############################################
# Final image
##############################################
FROM postgres:18.4-bookworm

LABEL maintainer="moustachir"
LABEL description="PostgreSQL 18.4 (bookworm) with the most popular extensions pre-installed and ready to use"
LABEL org.opencontainers.image.source="https://github.com/jesuph/moustachir-postgres"

ENV DEBIAN_FRONTEND=noninteractive

# Runtime only: no -dev headers, no compilers, no pkg-config.
# This is the only apt install that ends up in the shipped image.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # PostGIS runtime libs only
        libgeos-c1v5 \
        libproj25 \
        libgdal32 \
        libxml2 \
        libjson-c5 \
        libprotobuf-c1 \
        libsqlite3-0 \
        libcurl4 \
    ; \
    rm -rf /var/lib/apt/lists/*

# Copy compiled extension files from the builder stage.
# This brings in /usr/lib/postgresql/$PG_MAJOR/lib/*.so,
# /usr/share/postgresql/$PG_MAJOR/extension/{*.control,*.sql},
# and the raster2pgsql/shp2pgsql binaries.
COPY --from=builder /usr/lib/postgresql/ /usr/lib/postgresql/
COPY --from=builder /usr/share/postgresql/ /usr/share/postgresql/
COPY --from=builder /usr/local/bin/raster2pgsql /usr/local/bin/shp2pgsql /usr/local/bin/

##############################################
# 2. Copy initialization scripts
#    These run on first container start to
#    create extensions in template1 + default db
##############################################
COPY initdb/ /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/*.sh

EXPOSE 5432

##############################################
# 3. Start PostgreSQL with shared libraries
#    pg_stat_statements needs to be loaded
#    via shared_preload_libraries
##############################################
CMD ["postgres", "-c", "shared_preload_libraries=pg_stat_statements"]
