#!/bin/bash
set -e

# Samgita Docker Entrypoint Script
# This script prepares the environment and starts the application

echo "Starting Samgita..."

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL..."
until pg_isready -h db -U samgita 2>/dev/null; do
  echo "PostgreSQL is unavailable - sleeping"
  sleep 1
done

echo "PostgreSQL is up!"

# Run database migrations
echo "Running database migrations..."
bin/samgita eval "Samgita.Release.migrate()"

# Execute the main command
echo "Starting application..."
exec "$@"
