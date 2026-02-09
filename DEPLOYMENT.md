# Deployment Guide

## Quick Start: Push to Registry

### Windows Users (PowerShell)
```powershell
.\push-to-registry.ps1
```

### Mac/Linux Users (Bash)
```bash
chmod +x push-to-registry.sh
./push-to-registry.sh
```

---

## Manual Push to Docker Hub

### 1. Create Docker Hub Account
- Go to [https://hub.docker.com](https://hub.docker.com)
- Sign up (free)

### 2. Create Access Token
- Go to Account Settings → Security → New Access Token
- Name it `moustachir-postgres`
- Copy the token

### 3. Build & Push
```bash
# Log in
docker login

# Build
docker build -t YOUR_DOCKERHUB_USERNAME/moustachir-postgres:18.1 .

# Push
docker push YOUR_DOCKERHUB_USERNAME/moustachir-postgres:18.1

# Verify
docker pull YOUR_DOCKERHUB_USERNAME/moustachir-postgres:18.1
```

### 4. Share
- Image URL: `docker.io/YOUR_DOCKERHUB_USERNAME/moustachir-postgres:18`
- Public link: `https://hub.docker.com/r/YOUR_DOCKERHUB_USERNAME/moustachir-postgres`

---

## Automated Push to GitHub Container Registry (ghcr.io)

### 1. Set Up GitHub Repository
```bash
git init
git add .
git commit -m "PostgreSQL 18 with extensions"
git remote add origin https://github.com/YOUR_USERNAME/moustachir-postgres.git
git branch -M main
git push -u origin main
```

### 2. GitHub Actions Automatically Builds & Pushes
- The `.github/workflows/docker-publish.yml` workflow is pre-configured
- It will:
  - Build on every push to `main`
  - Build on every tag push (`v*`)
  - Push to `ghcr.io/YOUR_USERNAME/moustachir-postgres`
  - Tag with `latest`, commit SHA, and version tags

### 3. Use the Image
```bash
# Pull from GitHub Container Registry
docker pull ghcr.io/YOUR_USERNAME/moustachir-postgres:18.1
docker pull ghcr.io/YOUR_USERNAME/moustachir-postgres:latest

# Run it
docker run -d \
  -e POSTGRES_PASSWORD=mypassword \
  -p 5432:5432 \
  ghcr.io/YOUR_USERNAME/moustachir-postgres:18.1
```

### 4. Make Image Public (Optional)
1. Go to [https://github.com/users/YOUR_USERNAME/packages](https://github.com/users/YOUR_USERNAME/packages)
2. Click on `moustachir-postgres` package
3. Click "Package settings"
4. Change visibility to "Public"

---

## Tagging Releases

```bash
# Create a version tag
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions automatically builds and tags:
# - ghcr.io/YOUR_USERNAME/moustachir-postgres:v1.0.0
# - ghcr.io/YOUR_USERNAME/moustachir-postgres:1.0
# - ghcr.io/YOUR_USERNAME/moustachir-postgres:latest
```

---

## Rebuild After Changes

### Changes to Extension Versions
Edit `Dockerfile`:
```dockerfile
ARG PGVECTOR_VERSION=0.8.2
```

Then rebuild and push:
```bash
docker build -t YOUR_REGISTRY/moustachir-postgres:18.1 .
docker push YOUR_REGISTRY/moustachir-postgres:18.1
```

**For GitHub**: Just push to GitHub and CI/CD handles it automatically!
```bash
git add Dockerfile
git commit -m "Update pgvector to 0.8.2"
git push
```

---

## Comparison

| Feature | Docker Hub | GitHub (ghcr.io) |
|---------|-----------|------------------|
| **Free** | ✅ Yes | ✅ Yes |
| **Setup** | Simple | Needs GitHub |
| **CI/CD** | Requires setup | ✅ Built-in |
| **Manual Push** | ✅ Easy | Possible |
| **Auto Build** | Pro plan | ✅ Free |
| **Public/Private** | ✅ Both | ✅ Both |

---

## Deploying the Image

Once pushed, use it anywhere:

### Docker Compose
```yaml
services:
  postgres:
    image: ghcr.io/YOUR_USERNAME/moustachir-postgres:18.1
    environment:
      POSTGRES_PASSWORD: mypassword
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql

volumes:
  pgdata:
```

### Single Server
```bash
docker run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=mypassword \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql \
  ghcr.io/YOUR_USERNAME/moustachir-postgres:18.1
```

### Kubernetes
```yaml
image: ghcr.io/YOUR_USERNAME/moustachir-postgres:18.1
```

---

## Troubleshooting

### "Error: Docker daemon is not running"
- Start Docker Desktop or Docker service

### "Error: denied: permission denied"
Make sure you're logged in:
```bash
docker login               # Docker Hub
# or
docker login ghcr.io       # GitHub
```

### "Error: tag already exists"
Tag with a new version:
```bash
docker build -t YOUR_USERNAME/moustachir-postgres:18.1 .
docker push YOUR_USERNAME/moustachir-postgres:18.1
```

### Build fails
Clear build cache:
```bash
docker build --no-cache -t YOUR_USERNAME/moustachir-postgres:18.1 .
```
