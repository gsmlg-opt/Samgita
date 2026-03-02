#!/bin/bash
# Build and push Samgita Docker image

set -e

# Configuration
IMAGE_NAME="${DOCKER_IMAGE:-samgita}"
IMAGE_TAG="${DOCKER_TAG:-latest}"
REGISTRY="${DOCKER_REGISTRY:-}"

echo "========================================"
echo "Building Samgita Docker Image"
echo "========================================"
echo ""
echo "Image: $IMAGE_NAME:$IMAGE_TAG"
if [ -n "$REGISTRY" ]; then
    echo "Registry: $REGISTRY"
fi
echo ""

# Build image
echo "1. Building Docker image..."
docker build -t "$IMAGE_NAME:$IMAGE_TAG" .

# Tag for registry if specified
if [ -n "$REGISTRY" ]; then
    echo ""
    echo "2. Tagging for registry..."
    docker tag "$IMAGE_NAME:$IMAGE_TAG" "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"

    # Push to registry
    echo ""
    echo "3. Pushing to registry..."
    docker push "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
fi

echo ""
echo "========================================"
echo "✓ Docker image built successfully!"
echo "========================================"
echo ""
echo "To run locally:"
echo "  docker-compose up -d"
echo ""
if [ -n "$REGISTRY" ]; then
    echo "Image pushed to: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
    echo ""
fi
