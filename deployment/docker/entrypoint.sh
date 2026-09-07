#!/bin/bash
set -euo pipefail
# Compose waits for database health. Release config resolves DATABASE_URL.
echo "Migrating the configured Agent Hub database..."
bin/samgita eval 'Samgita.Release.migrate()'
exec "$@"
