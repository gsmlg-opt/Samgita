#!/bin/bash
# Build Samgita production release

set -e

echo "========================================"
echo "Building Samgita Production Release"
echo "========================================"

# Check required environment variables
if [ -z "$SECRET_KEY_BASE" ]; then
    echo "ERROR: SECRET_KEY_BASE is not set"
    echo "Generate one with: mix phx.gen.secret"
    exit 1
fi

# Set production environment
export MIX_ENV=prod

echo ""
echo "1. Fetching dependencies..."
mix deps.get --only prod

echo ""
echo "2. Compiling dependencies..."
mix deps.compile

echo ""
echo "3. Compiling application..."
mix compile

echo ""
echo "4. Building assets..."
mix assets.deploy

echo ""
echo "5. Creating release..."
mix release

echo ""
echo "========================================"
echo "✓ Release built successfully!"
echo "========================================"
echo ""
echo "Release location: _build/prod/rel/samgita"
echo ""
echo "To start the release:"
echo "  _build/prod/rel/samgita/bin/samgita start"
echo ""
echo "To run in foreground:"
echo "  _build/prod/rel/samgita/bin/samgita start_iex"
echo ""
