#!/bin/bash
# Deploy a prebuilt Agent Hub image only after explicit authorization.
set -euo pipefail
TARGET_USER="${DEPLOY_USER:-samgita}"
TARGET_HOST="${DEPLOY_HOST:?Set DEPLOY_HOST}"
TARGET_PATH="${DEPLOY_PATH:-/opt/samgita}"
SAMGITA_IMAGE="${SAMGITA_IMAGE:?Set SAMGITA_IMAGE to an approved immutable image}"

# These values are inserted into remote shell commands. Limit their alphabet.
[[ "$TARGET_USER" =~ ^[a-zA-Z0-9_-]+$ ]]
[[ "$TARGET_HOST" =~ ^[a-zA-Z0-9.-]+$ ]]
[[ "$TARGET_PATH" =~ ^/[a-zA-Z0-9_/-]+$ && "$TARGET_PATH" != "/" ]]
[[ "$SAMGITA_IMAGE" =~ ^[a-zA-Z0-9._/:@-]+$ ]]

# Destination secrets must already be provisioned; never copy sample secrets.
ssh "$TARGET_USER@$TARGET_HOST" "test -f '$TARGET_PATH/.env'"
scp docker-compose.yml "$TARGET_USER@$TARGET_HOST:$TARGET_PATH/docker-compose.yml"
ssh "$TARGET_USER@$TARGET_HOST" "
  set -e
  cd '$TARGET_PATH'
  export SAMGITA_IMAGE='$SAMGITA_IMAGE'
  docker compose pull web
  docker compose up -d --no-build --wait db web
  docker compose exec -T web curl --fail --silent --show-error http://localhost:3110/api/health
"
echo "Compose startup and HTTP health passed; verify real Agent WebSocket behavior separately."
