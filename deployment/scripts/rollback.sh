#!/bin/bash
# Rollback Samgita deployment to previous version

set -e

# Configuration from environment or defaults
TARGET_USER="${DEPLOY_USER:-samgita}"
TARGET_HOST="${DEPLOY_HOST}"
TARGET_PATH="${DEPLOY_PATH:-/opt/samgita}"

echo "========================================"
echo "Rolling Back Samgita Deployment"
echo "========================================"

# Validation
if [ -z "$TARGET_HOST" ]; then
    echo "ERROR: DEPLOY_HOST environment variable is not set"
    exit 1
fi

echo ""
echo "Target: $TARGET_USER@$TARGET_HOST:$TARGET_PATH"
echo ""
echo "WARNING: This will restore from the most recent backup"
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Rollback cancelled"
    exit 1
fi

# Find most recent backup
echo ""
echo "1. Finding most recent backup..."
LATEST_BACKUP=$(ssh "$TARGET_USER@$TARGET_HOST" "
    ls -dt ${TARGET_PATH}.backup.* 2>/dev/null | head -1 || echo ''
")

if [ -z "$LATEST_BACKUP" ]; then
    echo "ERROR: No backup found!"
    echo "Cannot perform rollback without a backup."
    exit 1
fi

echo "   Found backup: $LATEST_BACKUP"

# Check if using Docker or native deployment
echo ""
echo "2. Detecting deployment type..."
DEPLOYMENT_TYPE=$(ssh "$TARGET_USER@$TARGET_HOST" "
    if [ -f $TARGET_PATH/docker-compose.yml ]; then
        echo 'docker'
    elif [ -f $TARGET_PATH/bin/samgita ]; then
        echo 'native'
    else
        echo 'unknown'
    fi
")

if [ "$DEPLOYMENT_TYPE" == "unknown" ]; then
    echo "ERROR: Could not determine deployment type"
    exit 1
fi

echo "   Deployment type: $DEPLOYMENT_TYPE"

# Stop current deployment
echo ""
echo "3. Stopping current deployment..."
if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
    ssh "$TARGET_USER@$TARGET_HOST" "
        cd $TARGET_PATH
        docker-compose down || true
    "
elif [ "$DEPLOYMENT_TYPE" == "native" ]; then
    ssh "$TARGET_USER@$TARGET_HOST" "
        if command -v systemctl &> /dev/null; then
            sudo systemctl stop samgita || true
        else
            $TARGET_PATH/bin/samgita stop || true
        fi
    "
fi

# Create backup of failed deployment for analysis
echo ""
echo "4. Backing up failed deployment..."
ssh "$TARGET_USER@$TARGET_HOST" "
    FAILED_PATH=${TARGET_PATH}.failed.\$(date +%Y%m%d_%H%M%S)
    if [ -d $TARGET_PATH ]; then
        mv $TARGET_PATH \$FAILED_PATH
        echo \"   Failed deployment saved to: \$FAILED_PATH\"
    fi
"

# Restore from backup
echo ""
echo "5. Restoring from backup..."
ssh "$TARGET_USER@$TARGET_HOST" "
    cp -r $LATEST_BACKUP $TARGET_PATH
    echo \"   Restored from: $LATEST_BACKUP\"
"

# Start restored deployment
echo ""
echo "6. Starting restored deployment..."
if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
    ssh "$TARGET_USER@$TARGET_HOST" "
        cd $TARGET_PATH
        docker-compose up -d
    "
elif [ "$DEPLOYMENT_TYPE" == "native" ]; then
    ssh "$TARGET_USER@$TARGET_HOST" "
        if command -v systemctl &> /dev/null; then
            sudo systemctl start samgita
            sleep 3
            sudo systemctl status samgita
        else
            $TARGET_PATH/bin/samgita daemon
        fi
    "
fi

# Wait for service to be ready
echo ""
echo "7. Waiting for service to be ready..."
sleep 10

# Health check
echo ""
echo "8. Running health check..."
HEALTH_CHECK=$(ssh "$TARGET_USER@$TARGET_HOST" "
    curl -f -s -m 10 http://localhost:3110/api/health 2>/dev/null || echo 'FAILED'
")

if [ "$HEALTH_CHECK" == "FAILED" ]; then
    echo ""
    echo "❌ Rollback health check failed!"
    echo "Manual intervention required."
    echo ""
    echo "Check logs:"
    if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
        echo "  ssh $TARGET_USER@$TARGET_HOST 'cd $TARGET_PATH && docker-compose logs web'"
    else
        echo "  ssh $TARGET_USER@$TARGET_HOST 'journalctl -u samgita -n 100'"
    fi
    exit 1
fi

echo ""
echo "========================================"
echo "✓ Rollback successful!"
echo "========================================"
echo ""
echo "Application restored from: $LATEST_BACKUP"
echo "Failed deployment saved for analysis"
echo ""
echo "Next steps:"
echo "  1. Verify application is working correctly"
echo "  2. Investigate failed deployment logs"
echo "  3. Fix issues before attempting redeployment"
echo ""
