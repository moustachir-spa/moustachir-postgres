##############################################
# Moustachir PostgreSQL Docker Image
# PostgreSQL 18.1 with popular extensions
##############################################
FROM postgres:18.1

LABEL maintainer="moustachir"
LABEL description="PostgreSQL 18.1 with the most popular extensions pre-installed and ready to use"

# Extension versions (override at build time with --build-arg)
ARG PGVECTOR_VERSION=0.8.1

##############################################
# 1. Install dependencies, build extensions,
#    and clean up in a single layer
##############################################
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        # PostGIS runtime dependencies
        postgresql-$PG_MAJOR-postgis-3 \
        postgresql-$PG_MAJOR-postgis-3-scripts \
        # Build tools (will be removed later)
        build-essential \
        git \
        ca-certificates \
        postgresql-server-dev-$PG_MAJOR \
    && rm -rf /var/lib/apt/lists/* \
    \
    # Build pgvector
    && cd /tmp \
    && git clone --depth 1 --branch v${PGVECTOR_VERSION} https://github.com/pgvector/pgvector.git \
    && cd pgvector \
    && make \
    && make install \
    && cd / \
    && rm -rf /tmp/pgvector \
    \
    # Remove build dependencies, keep runtime libs
    && apt-get purge -y --auto-remove \
        build-essential \
        git \
        postgresql-server-dev-$PG_MAJOR \
    && rm -rf /var/lib/apt/lists/*

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
