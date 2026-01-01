#!/bin/sh

# Find main.js file (NestJS build output location can vary)
MAIN_FILE=$(find /app/backend/dist -name "main.js" -type f 2>/dev/null | head -1)

if [ -z "$MAIN_FILE" ]; then
    echo "ERROR: Backend build failed - main.js not found"
    echo "Searched in /app/backend/dist/"
    echo ""
    echo "Contents of /app/backend/dist/:"
    ls -la /app/backend/dist/ || true
    echo ""
    echo "Searching for any .js files in dist:"
    find /app/backend/dist -name "*.js" -type f 2>/dev/null | head -10 || echo "No .js files found"
    echo ""
    echo "The backend build stage may have failed during Docker build"
    exit 1
fi

echo "Found main.js at: $MAIN_FILE"

echo "Running database migrations..."
# Find data-source.js file (may be in dist/ or dist/src/)
DATA_SOURCE=$(find /app/backend/dist -name "data-source.js" -path "*/database/data-source.js" 2>/dev/null | head -1)

if [ -z "$DATA_SOURCE" ]; then
    echo "WARNING: data-source.js not found, skipping migrations"
    echo "This may be normal if migrations are handled differently"
else
    echo "Found data-source.js at: $DATA_SOURCE"
    # Run migrations using the found data-source file
    cd /app/backend && npx typeorm migration:run -d "$DATA_SOURCE" || {
        echo "Migration failed or no migrations to run - continuing..."
    }
fi

echo "Starting application..."
# Use the found main.js file directly
cd /app/backend
exec node "$MAIN_FILE"

