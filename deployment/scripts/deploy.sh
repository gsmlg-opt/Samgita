#!/bin/bash
# Deploy Samgita to production server

set -e

# Configuration
TARGET_USER="${DEPLOY_USER:-samgita}"
TARGET_HOST="${DEPLOY_HOST}"
TARGET_PATH="${DEPLOY_PATH:-/opt/samgita}"
RELEASE_PATH="_build/prod/rel/samgita"

echo "========================================"
echo "Deploying Samgita"
echo "========================================"

# Check if target host is set
if [ -z "$TARGET_HOST" ]; then
    echo "ERROR: DEPLOY_HOST environment variable is not set"
    echo "Usage: DEPLOY_HOST=your-server.com ./deploy.sh"
    exit 1
fi

# Check if release exists
if [ ! -d "$RELEASE_PATH" ]; then
    echo "ERROR: Release not found at $RELEASE_PATH"
    echo "Run build-release.sh first"
    exit 1
fi

echo ""
echo "Deploying to: $TARGET_USER@$TARGET_HOST:$TARGET_PATH"
echo ""

# Create backup on target
echo "1. Creating backup on target server..."
ssh "$TARGET_USER@$TARGET_HOST" "
    if [ -d $TARGET_PATH ]; then
        BACKUP_PATH=${TARGET_PATH}.backup.\$(date +%Y%m%d_%H%M%S)
        echo \"   Creating backup at \$BACKUP_PATH\"
        cp -r $TARGET_PATH \$BACKUP_PATH
    fi
"

# Stop service
echo ""
echo "2. Stopping service..."
ssh "$TARGET_USER@$TARGET_HOST" "
    if command -v systemctl &> /dev/null; then
        sudo systemctl stop samgita || true
    else
        $TARGET_PATH/bin/samgita stop || true
    fi
"

# Upload release
echo ""
echo "3. Uploading release..."
rsync -avz --delete \
    --exclude='*.log' \
    --exclude='tmp/*' \
    --exclude='var/*' \
    "$RELEASE_PATH/" \
    "$TARGET_USER@$TARGET_HOST:$TARGET_PATH/"

# Run migrations
echo ""
echo "4. Running migrations..."
ssh "$TARGET_USER@$TARGET_HOST" "
    cd $TARGET_PATH
    bin/samgita eval 'Samgita.Release.migrate()'
"

# Start service
echo ""
echo "5. Starting service..."
ssh "$TARGET_USER@$TARGET_HOST" "
    if command -v systemctl &> /dev/null; then
        sudo systemctl start samgita
        sleep 3
        sudo systemctl status samgita
    else
        $TARGET_PATH/bin/samgita daemon
    fi
"

# Health check
echo ""
echo "6. Running health check..."
sleep 5
HEALTH_CHECK=$(ssh "$TARGET_USER@$TARGET_HOST" "curl -f http://localhost:3110/api/health 2>/dev/null" || echo "FAILED")

if [ "$HEALTH_CHECK" == "FAILED" ]; then
    echo ""
    echo "❌ Health check failed!"
    echo "Check logs with: ssh $TARGET_USER@$TARGET_HOST 'journalctl -u samgita -n 50'"
    exit 1
fi

echo ""
echo "========================================"
echo "✓ Deployment successful!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  - Check logs: ssh $TARGET_USER@$TARGET_HOST 'journalctl -u samgita -f'"
echo "  - Health check: curl http://$TARGET_HOST:3110/api/health"
echo ""
