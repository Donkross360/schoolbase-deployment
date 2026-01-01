#!/bin/sh

# Check if backend was built successfully
if [ ! -f /app/backend/dist/main.js ]; then
    echo "ERROR: Backend build failed - /app/backend/dist/main.js not found"
    echo "The backend build stage may have failed during Docker build"
    exit 1
fi

echo "Running database migrations..."
# Use production migration command (uses compiled JS, not TypeScript)
npm run migration:run:prod || {
    echo "Migration failed or no migrations to run - continuing..."
}

echo "Starting application..."
exec npm run start:prod

