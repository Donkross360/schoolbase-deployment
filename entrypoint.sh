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

echo "Note: Migrations are handled automatically by the backend on startup"
echo "The backend has migrationsRun enabled in TypeORM configuration"
echo "Migrations will run in timestamp order automatically"

echo "Starting application..."
# Use the found main.js file directly
cd /app/backend
exec node "$MAIN_FILE"

