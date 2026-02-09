# Moustachir PostgreSQL

A production-ready PostgreSQL 18 Docker image with the most popular extensions pre-installed and auto-enabled for all databases.

## Included Extensions

| Extension | Description |
|---|---|
| **plpgsql** | Procedural language (built-in) |
| **pg_stat_statements** | Query performance monitoring |
| **uuid-ossp** | UUID generation (v1, v4, v5) |
| **pgvector** | Vector similarity search (AI/ML embeddings) |
| **pgcrypto** | Cryptographic functions (hashing, encryption) |
| **pg_trgm** | Trigram-based fuzzy text search |
| **PostGIS** | Geospatial data types and functions |
| **citext** | Case-insensitive text type |
| **unaccent** | Accent/diacritic stripping for text search |
| **hstore** | Key-value store in a single column |

All extensions are installed in `template1`, so **every new database you create automatically has them available**.

---

## Quick Start (Local)

> **Note for PostgreSQL 18+**: If you have old data from a previous PostgreSQL version, you need to clear the volume first:
> ```bash
> docker compose down -v  # Remove old volumes
> docker compose up -d    # Start fresh
> ```

```bash
# Clone the repo
git clone <your-repo-url> moustachir-postgres
cd moustachir-postgres

# Build and run with docker-compose
docker compose up -d

# Verify extensions
docker exec -it moustachir-postgres psql -U postgres -c "SELECT * FROM pg_available_extensions WHERE name IN ('pg_stat_statements','uuid-ossp','vector','pgcrypto','pg_trgm','postgis','citext','unaccent','hstore') ORDER BY name;"
```

### Or with `docker run`:

```bash
# Build the image
docker build -t moustachir/postgres:18 .

# Run the container
docker run -d \
  --name moustachir-postgres \
  -e POSTGRES_PASSWORD=changeme \
  -p 5432:5432 \
  --shm-size=256mb \
  moustachir/postgres:18
```

---

## Verify Extensions Work

```bash
# Connect to postgres
docker exec -it moustachir-postgres psql -U postgres

# Inside psql:
\dx                                    -- list installed extensions
SELECT uuid_generate_v4();             -- test uuid-ossp
SELECT crypt('hello', gen_salt('bf')); -- test pgcrypto
SELECT unaccent('Crème Brûlée');       -- test unaccent
SELECT similarity('hello', 'helo');    -- test pg_trgm
SELECT '[1,2,3]'::vector;             -- test pgvector
SELECT PostGIS_Version();              -- test PostGIS

-- Create a new database and verify it inherits extensions
CREATE DATABASE myapp;
\c myapp
\dx   -- all extensions are already there!
```

---

## Customizing Extension Versions

Override at build time:

```bash
docker build \
  --build-arg PGVECTOR_VERSION=0.8.1 \
  -t moustachir/postgres:18 .
```

---

# Hosting Guide

## Option 1: Docker Hub (Public/Private Registry)

The most common way to share Docker images.

```bash
# 1. Create a Docker Hub account at https://hub.docker.com

# 2. Log in
docker login

# 3. Build with your Docker Hub username
docker build -t YOUR_DOCKERHUB_USERNAME/moustachir-postgres:18 .

# 4. Push to Docker Hub
docker push YOUR_DOCKERHUB_USERNAME/moustachir-postgres:18

# 5. Anyone can now pull and run it
docker pull YOUR_DOCKERHUB_USERNAME/moustachir-postgres:18
```

## Option 2: GitHub Container Registry (ghcr.io)

Free for public repos, integrates with GitHub Actions.

```bash
# 1. Create a GitHub Personal Access Token (PAT) with write:packages scope
#    at https://github.com/settings/tokens

# 2. Log in to ghcr.io
echo YOUR_GITHUB_PAT | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# 3. Build and tag
docker build -t ghcr.io/YOUR_GITHUB_USERNAME/moustachir-postgres:18 .

# 4. Push
docker push ghcr.io/YOUR_GITHUB_USERNAME/moustachir-postgres:18

# 5. Make the package public (optional)
#    Go to: https://github.com/users/YOUR_GITHUB_USERNAME/packages
#    → Package settings → Change visibility → Public
```

### Automate with GitHub Actions

Create `.github/workflows/docker-publish.yml`:

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/moustachir-postgres:18
            ghcr.io/${{ github.repository_owner }}/moustachir-postgres:latest
```

## Option 3: AWS Elastic Container Registry (ECR)

Best if deploying to AWS (ECS, Fargate, EKS).

```bash
# 1. Install AWS CLI and configure credentials
aws configure

# 2. Create an ECR repository
aws ecr create-repository --repository-name moustachir-postgres --region us-east-1

# 3. Log in to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# 4. Tag and push
docker build -t moustachir-postgres:18 .
docker tag moustachir-postgres:18 YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/moustachir-postgres:18
docker push YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/moustachir-postgres:18
```

## Option 4: Google Artifact Registry (GCP)

Best if deploying to GCP (Cloud Run, GKE).

```bash
# 1. Install gcloud CLI and authenticate
gcloud auth login
gcloud auth configure-docker us-central1-docker.pkg.dev

# 2. Create an Artifact Registry repository
gcloud artifacts repositories create moustachir-postgres \
  --repository-format=docker \
  --location=us-central1

# 3. Build, tag, and push
docker build -t moustachir-postgres:18 .
docker tag moustachir-postgres:18 \
  us-central1-docker.pkg.dev/YOUR_PROJECT_ID/moustachir-postgres/moustachir-postgres:18
docker push \
  us-central1-docker.pkg.dev/YOUR_PROJECT_ID/moustachir-postgres/moustachir-postgres:18
```

## Option 5: Azure Container Registry (ACR)

Best if deploying to Azure (ACI, AKS).

```bash
# 1. Install Azure CLI and log in
az login

# 2. Create a resource group and ACR
az group create --name moustachir-rg --location eastus
az acr create --resource-group moustachir-rg --name moustachirregistry --sku Basic

# 3. Log in to ACR
az acr login --name moustachirregistry

# 4. Build, tag, and push
docker build -t moustachir-postgres:18 .
docker tag moustachir-postgres:18 moustachirregistry.azurecr.io/moustachir-postgres:18
docker push moustachirregistry.azurecr.io/moustachir-postgres:18
```

---

# Running in Production

## On a VPS (DigitalOcean, Hetzner, Linode, etc.)

```bash
# 1. SSH into your server
ssh root@your-server-ip

# 2. Install Docker
curl -fsSL https://get.docker.com | sh

# 3. Pull your image (after pushing to a registry)
docker pull YOUR_REGISTRY/moustachir-postgres:18

# 4. Run with production settings
docker run -d \
  --name moustachir-postgres \
  -e POSTGRES_PASSWORD=$(openssl rand -base64 32) \
  -e POSTGRES_USER=admin \
  -e POSTGRES_DB=production \
  -p 5432:5432 \
  --shm-size=512mb \
  -v pgdata:/var/lib/postgresql \
  --restart unless-stopped \
  YOUR_REGISTRY/moustachir-postgres:18
```

## On Kubernetes

```yaml
# postgres-deployment.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: moustachir-postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: YOUR_REGISTRY/moustachir-postgres:18
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/postgresql
          resources:
            requests:
              memory: "512Mi"
              cpu: "500m"
            limits:
              memory: "2Gi"
              cpu: "2000m"
  volumeClaimTemplates:
    - metadata:
        name: pgdata
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
  type: ClusterIP
```

---

## Production Tips

- **Always change `POSTGRES_PASSWORD`** — never use `changeme` in production
- **Use named volumes** (`-v pgdata:/var/lib/postgresql`) to persist data
- **Back up regularly** — use `pg_dump` or `pg_basebackup`
- **Set `shm_size`** to at least 256MB for PostgreSQL
- **Use a reverse proxy** (e.g., PgBouncer) for connection pooling in production
- **Monitor with pg_stat_statements** — it's already enabled in this image
- **Restrict network access** — don't expose port 5432 to the public internet; use VPN or firewall rules

---

## Troubleshooting

### PostgreSQL 18+ Volume Mount Error

If you see this error:
```
Error: in 18+, these Docker images are configured to store database data in a
       format which is compatible with "pg_ctlcluster"...
       Counter to that, there appears to be PostgreSQL data in:
         /var/lib/postgresql/data (unused mount/volume)
```

**Solution**: PostgreSQL 18+ changed the data directory structure. Clear your old volume:

```bash
# Stop and remove containers and volumes
docker compose down -v

# Or manually remove the volume
docker volume rm moustachir-postgres_pgdata

# Start fresh
docker compose up -d
```

**For existing data**: See [PostgreSQL upgrade guide](https://github.com/docker-library/postgres/issues/37) for migration using `pg_upgrade`.

---

## License

MIT
