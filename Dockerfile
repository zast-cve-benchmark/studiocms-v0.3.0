FROM node:22-slim

# Install build dependencies (python for node-gyp/canvas, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 build-essential curl sqlite3 && \
    rm -rf /var/lib/apt/lists/*

# Install pnpm
RUN corepack enable && corepack prepare pnpm@10.17.0 --activate

WORKDIR /app

# Copy ALL root config files (tsconfig.base.json is critical)
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml .prototools ./
COPY tsconfig.base.json tsconfig.json tsconfig.tspc.json ./
COPY packages/ packages/
COPY playground/ playground/

# Create .env BEFORE install/build (CMS_ENCRYPTION_KEY required at build time)
ARG CMS_ENCRYPTION_KEY=default_build_key_XYz12AbC
RUN echo "CMS_ENCRYPTION_KEY=${CMS_ENCRYPTION_KEY}" > playground/.env && \
    echo "CMS_LIBSQL_URL=file:local.db" >> playground/.env

# Install dependencies
RUN pnpm install 2>&1

# Build all workspace packages
RUN pnpm build:packages 2>&1

# Build the playground (Astro SSR app)
RUN pnpm playground:build 2>&1

# Fix pg catalog dependency issue - manually create symlink after build
# pnpm 9.x hoisting may not create the expected symlink for pg
RUN ln -sf /app/node_modules/.pnpm/pg@8.16.3/node_modules /app/node_modules/pg

# Regenerate encryption key for runtime (unique per container)
RUN ENCRYPTION_KEY=$(node -e "console.log(require('crypto').randomBytes(16).toString('base64'))") && \
    echo "CMS_ENCRYPTION_KEY=${ENCRYPTION_KEY}" > playground/.env && \
    echo "CMS_LIBSQL_URL=file:local.db" >> playground/.env

# Expose the Astro server port
EXPOSE 4321

# Create startup script with migration + role setup
RUN cat > /app/start.sh << 'STARTEOF'
#!/bin/bash
set -e
echo "[*] Running database migrations..."
cd /app
pnpm --filter node-playground studiocms migrate --latest 2>&1 || echo "[!] Migration warning"

echo "[*] Starting StudioCMS server on port 4321..."
cd /app/playground
node dist/server/entry.mjs &
SERVER_PID=$!

# Wait for server to start
echo "[*] Waiting for server to start..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:4321/ > /dev/null 2>&1; then
        echo "[+] Server is up"
        break
    fi
    sleep 1
done

echo "[*] Creating test users..."
# Register users (ignore errors if already exist)
curl -s -X POST http://localhost:4321/studiocms_api/auth/register \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=studiocms_owner&email=owner@studiocms.local&displayname=Owner&password=OwnerPass123!&confirm-password=OwnerPass123!" > /dev/null 2>&1 || true

curl -s -X POST http://localhost:4321/studiocms_api/auth/register \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=scms_admin&email=admin@test.local&displayname=Admin&password=Zx9kQ2mW7nR4pL3&confirm-password=Zx9kQ2mW7nR4pL3" > /dev/null 2>&1 || true

curl -s -X POST http://localhost:4321/studiocms_api/auth/register \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=test_editor&email=editor@test.local&displayname=Editor&password=EditorPass123!&confirm-password=EditorPass123!" > /dev/null 2>&1 || true

curl -s -X POST http://localhost:4321/studiocms_api/auth/register \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=test_visitor&email=visitor@test.local&displayname=Visitor&password=VisitorPass123!&confirm-password=VisitorPass123!" > /dev/null 2>&1 || true

echo "[*] Setting user roles in database..."
sleep 2
# Set roles in DB using sqlite3
for user_info in "studiocms_owner:owner" "scms_admin:admin" "test_editor:editor" "test_visitor:visitor"; do
    USERNAME=$(echo $user_info | cut -d: -f1)
    RANK=$(echo $user_info | cut -d: -f2)
    USER_ID=$(sqlite3 /app/playground/local.db "SELECT id FROM StudioCMSUsersTable WHERE username='$USERNAME';")
    if [ -n "$USER_ID" ]; then
        sqlite3 /app/playground/local.db "UPDATE StudioCMSPermissions SET rank='$RANK' WHERE user='$USER_ID';"
        echo "  Set $USERNAME -> $RANK"
    fi
done

echo "[+] User setup complete"
kill $SERVER_PID 2>/dev/null || true
sleep 2

echo "[*] Starting StudioCMS server..."
exec node dist/server/entry.mjs
STARTEOF
RUN chmod +x /app/start.sh

CMD ["/app/start.sh"]
