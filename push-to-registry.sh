#!/bin/bash
# Quick start guide for pushing to registries

set -e

echo "=========================================="
echo "Moustachir PostgreSQL - Registry Push"
echo "=========================================="
echo ""

# Check if Docker is running
if ! docker ps > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

echo "Select your registry:"
echo "1. Docker Hub (dockerhub.com)"
echo "2. GitHub Container Registry (ghcr.io)"
echo ""
read -p "Enter choice (1 or 2): " choice

case $choice in
  1)
    echo ""
    echo "🐳 Docker Hub Setup"
    echo "===================="
    echo "1. Create account at https://hub.docker.com (free)"
    echo "2. Run: docker login"
    read -p "Enter your Docker Hub username: " dockerhub_user
    read -p "Enter your Docker Hub password: " -s dockerhub_pass
    echo ""
    
    echo "Logging in to Docker Hub..."
    echo "$dockerhub_pass" | docker login -u "$dockerhub_user" --password-stdin
    
    echo "Building image..."
    docker build \
      --build-arg PGVECTOR_VERSION=0.8.5 \
      --build-arg POSTGIS_VERSION=3.5.7 \
      -t "$dockerhub_user/moustachir-postgres:18.4.0" \
      -t "$dockerhub_user/moustachir-postgres:18.4" \
      -t "$dockerhub_user/moustachir-postgres:latest" \
      .

    echo "Pushing to Docker Hub..."
    docker push "$dockerhub_user/moustachir-postgres:18.4.0"
    docker push "$dockerhub_user/moustachir-postgres:18.4"
    docker push "$dockerhub_user/moustachir-postgres:latest"

    echo ""
    echo "✅ Success! Image pushed to: https://hub.docker.com/r/$dockerhub_user/moustachir-postgres"
    echo ""
    echo "To pull it later:"
    echo "  docker pull $dockerhub_user/moustachir-postgres:18.4"
    ;;
    
  2)
    echo ""
    echo "🐙 GitHub Container Registry Setup"
    echo "===================================="
    echo "1. Go to https://github.com/settings/tokens"
    echo "2. Create a Personal Access Token (PAT) with 'write:packages' scope"
    echo "3. Use that token below (or just push your code to GitHub first for CI/CD)"
    echo ""
    read -p "Enter your GitHub username: " github_user
    read -p "Enter your GitHub PAT (or press Enter to skip manual push): " github_token
    
    if [ -z "$github_token" ]; then
      echo ""
      echo "ℹ️  Skipping manual push. To automate:"
      echo "1. Push your code to GitHub:"
      echo "   git remote add origin https://github.com/$github_user/moustachir-postgres.git"
      echo "   git branch -M main"
      echo "   git push -u origin main"
      echo ""
      echo "2. GitHub Actions will automatically build and push on every push!"
      echo "   (The workflow file .github/workflows/docker-publish.yml is already configured)"
    else
      echo ""
      echo "Logging in to GitHub Container Registry..."
      echo "$github_token" | docker login ghcr.io -u "$github_user" --password-stdin
      
      echo "Building image..."
      docker build \
        --build-arg PGVECTOR_VERSION=0.8.5 \
        --build-arg POSTGIS_VERSION=3.5.7 \
        -t "ghcr.io/$github_user/moustachir-postgres:18.4.0" \
        -t "ghcr.io/$github_user/moustachir-postgres:18.4" \
        -t "ghcr.io/$github_user/moustachir-postgres:latest" \
        .
      
      echo "Pushing to GitHub Container Registry..."
      docker push "ghcr.io/$github_user/moustachir-postgres:18.4.0"
      docker push "ghcr.io/$github_user/moustachir-postgres:18.4"
      docker push "ghcr.io/$github_user/moustachir-postgres:latest"
      
      echo ""
      echo "✅ Success! Image pushed to: ghcr.io/$github_user/moustachir-postgres"
      echo ""
      echo "To pull it later:"
      echo "  docker pull ghcr.io/$github_user/moustachir-postgres:18.4"
    fi
    ;;
    
  *)
    echo "❌ Invalid choice. Exiting."
    exit 1
    ;;
esac

echo ""
echo "=========================================="
echo "Next steps:"
echo "1. Share your image with others!"
echo "2. Deploy using docker-compose or Kubernetes"
echo "3. Update the image with: docker build -t ... . && docker push ..."
echo "=========================================="
