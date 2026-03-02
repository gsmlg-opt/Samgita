#!/bin/bash
# Deploy Samgita using Docker to remote server

set -e

# Configuration from environment or defaults
TARGET_USER="${DEPLOY_USER:-samgita}"
TARGET_HOST="${DEPLOY_HOST}"
TARGET_PATH="${DEPLOY_PATH:-/opt/samgita}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-samgita}"

echo "========================================"
echo "Deploying Samgita with Docker"
echo "========================================"

# Validation
if [ -z "$TARGET_HOST" ]; then
    echo "ERROR: DEPLOY_HOST environment variable is not set"
    exit 1
fi

echo ""
echo "Target: $TARGET_USER@$TARGET_HOST:$TARGET_PATH"
echo "Image: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo ""

# Create deployment directory
echo "1. Setting up deployment directory..."
ssh "$TARGET_USER@$TARGET_HOST" "mkdir -p $TARGET_PATH"

# Copy docker-compose and configuration
echo ""
echo "2. Uploading configuration files..."
scp docker-compose.yml "$TARGET_USER@$TARGET_HOST:$TARGET_PATH/"
scp .env.example "$TARGET_USER@$TARGET_HOST:$TARGET_PATH/.env.example"

# Update docker-compose to use specific image tag
echo ""
echo "3. Updating docker-compose configuration..."
ssh "$TARGET_USER@$TARGET_HOST" "
    cd $TARGET_PATH

    # Create/update .env if it doesn't exist
    if [ ! -f .env ]; then
        cp .env.example .env
        echo 'WARNING: Using .env.example - please update with production values!'
    fi

    # Update docker-compose to use specific image
    sed -i.bak 's|build:|image: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG\\n      # build:|' docker-compose.yml
"

# Pull latest image
echo ""
echo "4. Pulling Docker image..."
ssh "$TARGET_USER@$TARGET_HOST" "
    cd $TARGET_PATH
    docker pull $REGISTRY/$IMAGE_NAME:$IMAGE_TAG
"

# Stop existing containers
echo ""
echo "5. Stopping existing containers..."
ssh "$TARGET_USER@$TARGET_HOST" "
    cd $TARGET_PATH
    docker-compose down || true
"

# Start new containers
echo ""
echo "6. Starting new containers..."
ssh "$TARGET_USER@$TARGET_HOST" "
    cd $TARGET_PATH
    docker-compose up -d
"

# Wait for service to be ready
echo ""
echo "7. Waiting for service to be ready..."
sleep 10

# Run database migrations
echo ""
echo "8. Running database migrations..."
ssh "$TARGET_USER@$TARGET_HOST" "
    cd $TARGET_PATH
    docker-compose exec -T web bin/samgita eval 'Samgita.Release.migrate()'
"

# Check container health
echo ""
echo "9. Checking container health..."
HEALTH_STATUS=$(ssh "$TARGET_USER@$TARGET_HOST" "
    cd $TARGET_PATH
    docker-compose ps web | grep 'healthy' || echo 'FAILED'
")

if [[ "$HEALTH_STATUS" == "FAILED" ]]; then
    echo "WARNING: Container health check inconclusive"
    echo "Checking service logs..."
    ssh "$TARGET_USER@$TARGET_HOST" "
        cd $TARGET_PATH
        docker-compose logs --tail=50 web
    "
fi

echo ""
echo "========================================"
echo "✓ Docker deployment completed!"
echo "========================================"
echo ""
echo "View logs: ssh $TARGET_USER@$TARGET_HOST 'cd $TARGET_PATH && docker-compose logs -f web'"
echo "Check status: ssh $TARGET_USER@$TARGET_HOST 'cd $TARGET_PATH && docker-compose ps'"
echo ""
