# Quick start guide for pushing to registries (Windows PowerShell)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Moustachir PostgreSQL - Registry Push" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is running
try {
    docker ps > $null 2>&1
} catch {
    Write-Host "❌ Docker is not running. Please start Docker and try again." -ForegroundColor Red
    exit 1
}

Write-Host "Select your registry:" -ForegroundColor Yellow
Write-Host "1. Docker Hub (hub.docker.com)" -ForegroundColor White
Write-Host "2. GitHub Container Registry (ghcr.io)" -ForegroundColor White
Write-Host ""
$choice = Read-Host "Enter choice (1 or 2)"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "🐳 Docker Hub Setup" -ForegroundColor Blue
        Write-Host "====================" -ForegroundColor Blue
        Write-Host "1. Create account at https://hub.docker.com (free)" -ForegroundColor White
        Write-Host "2. Run: docker login" -ForegroundColor White
        $dockerhub_user = Read-Host "Enter your Docker Hub username"
        
        Write-Host "Logging in to Docker Hub..." -ForegroundColor Yellow
        docker login -u "$dockerhub_user"
        
        Write-Host "Building image..." -ForegroundColor Yellow
        docker build `
            --build-arg PGVECTOR_VERSION=0.8.5 `
            --build-arg POSTGIS_VERSION=3.5.7 `
            -t "$dockerhub_user/moustachir-postgres:18.4.0" `
            -t "$dockerhub_user/moustachir-postgres:18.4" `
            -t "$dockerhub_user/moustachir-postgres:latest" `
            .
        
        Write-Host "Pushing to Docker Hub..." -ForegroundColor Yellow
        docker push "$dockerhub_user/moustachir-postgres:18.4.0"
        docker push "$dockerhub_user/moustachir-postgres:18.4"
        docker push "$dockerhub_user/moustachir-postgres:latest"
        
        Write-Host ""
        Write-Host "✅ Success! Image pushed to: https://hub.docker.com/r/$dockerhub_user/moustachir-postgres" -ForegroundColor Green
        Write-Host ""
        Write-Host "To pull it later:" -ForegroundColor Yellow
        Write-Host "  docker pull $dockerhub_user/moustachir-postgres:18.4" -ForegroundColor White
    }
    
    "2" {
        Write-Host ""
        Write-Host "🐙 GitHub Container Registry Setup" -ForegroundColor Blue
        Write-Host "====================================" -ForegroundColor Blue
        Write-Host "1. Go to https://github.com/settings/tokens" -ForegroundColor White
        Write-Host "2. Create a Personal Access Token (PAT) with 'write:packages' scope" -ForegroundColor White
        Write-Host "3. Use that token below" -ForegroundColor White
        Write-Host ""
        $github_user = Read-Host "Enter your GitHub username"
        $github_token = Read-Host "Enter your GitHub PAT (leave empty to skip manual push)"
        
        if ([string]::IsNullOrEmpty($github_token)) {
            Write-Host ""
            Write-Host "ℹ️  Skipping manual push. To automate:" -ForegroundColor Yellow
            Write-Host "1. Push your code to GitHub:" -ForegroundColor White
            Write-Host "   git remote add origin https://github.com/$github_user/moustachir-postgres.git" -ForegroundColor Gray
            Write-Host "   git branch -M main" -ForegroundColor Gray
            Write-Host "   git push -u origin main" -ForegroundColor Gray
            Write-Host ""
            Write-Host "2. GitHub Actions will automatically build and push on every push!" -ForegroundColor White
            Write-Host "   (The workflow file .github/workflows/docker-publish.yml is already configured)" -ForegroundColor White
        } else {
            Write-Host ""
            Write-Host "Logging in to GitHub Container Registry..." -ForegroundColor Yellow
            $github_token | docker login ghcr.io -u "$github_user" --password-stdin
            
            Write-Host "Building image..." -ForegroundColor Yellow
            docker build `
                --build-arg PGVECTOR_VERSION=0.8.5 `
                --build-arg POSTGIS_VERSION=3.5.7 `
                -t "ghcr.io/$github_user/moustachir-postgres:18.4.0" `
                -t "ghcr.io/$github_user/moustachir-postgres:18.4" `
                -t "ghcr.io/$github_user/moustachir-postgres:latest" `
                .
            
            Write-Host "Pushing to GitHub Container Registry..." -ForegroundColor Yellow
            docker push "ghcr.io/$github_user/moustachir-postgres:18.4.0"
            docker push "ghcr.io/$github_user/moustachir-postgres:18.4"
            docker push "ghcr.io/$github_user/moustachir-postgres:latest"
            
            Write-Host ""
            Write-Host "✅ Success! Image pushed to: ghcr.io/$github_user/moustachir-postgres" -ForegroundColor Green
            Write-Host ""
            Write-Host "To pull it later:" -ForegroundColor Yellow
            Write-Host "  docker pull ghcr.io/$github_user/moustachir-postgres:18.4" -ForegroundColor White
        }
    }
    
    default {
        Write-Host "❌ Invalid choice. Exiting." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Share your image with others!" -ForegroundColor White
Write-Host "2. Deploy using docker-compose or Kubernetes" -ForegroundColor White
Write-Host "3. Update the image with: docker build -t ... . && docker push ..." -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Cyan
