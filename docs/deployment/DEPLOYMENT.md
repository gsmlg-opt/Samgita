# Samgita Deployment Guide

This guide covers multiple deployment strategies for Samgita, from local development to production environments.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start (Docker)](#quick-start-docker)
3. [Manual Deployment](#manual-deployment)
4. [Production Deployment](#production-deployment)
5. [Environment Variables](#environment-variables)
6. [Deployment Strategies](#deployment-strategies)
7. [Monitoring & Operations](#monitoring--operations)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

- **Elixir**: 1.17+ with Erlang/OTP 26+
- **PostgreSQL**: 14+ (with pgvector extension)
- **Bun**: Latest version (for asset bundling)
- **Claude CLI**: Installed and configured (`claude` command available)
- **Git**: For project cloning and version management

### Optional but Recommended

- **Docker & Docker Compose**: For containerized deployment
- **Nginx/Caddy**: As reverse proxy for production
- **Systemd**: For service management on Linux

---

## Quick Start (Docker)

The fastest way to get Samgita running:

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/samgita.git
cd samgita

# 2. Create environment file
cp .env.example .env
# Edit .env and set required variables (see Environment Variables section)

# 3. Start with Docker Compose
docker-compose up -d

# 4. Run migrations
docker-compose exec web mix ecto.migrate

# 5. Access the application
open http://localhost:3110
```

---

## Manual Deployment

### Step 1: Install Dependencies

```bash
# Install Elixir dependencies
mix deps.get

# Install JavaScript dependencies
cd apps/samgita_web && bun install && cd ../..

# Install assets (tailwind, bun)
mix assets.setup
```

### Step 2: Configure Database

```bash
# Create PostgreSQL database
createdb samgita_prod

# Install pgvector extension
psql samgita_prod -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Run migrations
MIX_ENV=prod mix ecto.migrate
```

### Step 3: Configure Environment

Create `config/prod.secret.exs` or set environment variables:

```bash
export DATABASE_URL="postgresql://user:pass@localhost/samgita_prod"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export PHX_HOST="samgita.example.com"
export ANTHROPIC_API_KEY="your-anthropic-api-key"
export SAMGITA_API_KEYS="key1,key2,key3"
```

### Step 4: Build Assets

```bash
MIX_ENV=prod mix assets.deploy
```

### Step 5: Build Release

```bash
MIX_ENV=prod mix release
```

### Step 6: Start the Release

```bash
_build/prod/rel/samgita/bin/samgita start
```

---

## Production Deployment

### Using Elixir Releases (Recommended)

#### 1. Build Production Release

```bash
# Set production environment
export MIX_ENV=prod

# Fetch dependencies
mix deps.get --only prod

# Compile dependencies
mix deps.compile

# Build assets
mix assets.deploy

# Create release
mix release samgita
```

#### 2. Deploy to Target Server

```bash
# Copy release to target
scp -r _build/prod/rel/samgita user@server:/opt/samgita

# On the target server:
cd /opt/samgita
bin/samgita start
```

### Using Docker

See [Docker Deployment](#docker-deployment) section below.

### Using Systemd (Linux)

1. Copy release to `/opt/samgita`
2. Install systemd service file (see `deployment/systemd/samgita.service`)
3. Enable and start service:

```bash
sudo systemctl enable samgita
sudo systemctl start samgita
sudo systemctl status samgita
```

---

## Environment Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection URL | `postgresql://user:pass@localhost/samgita_prod` |
| `SECRET_KEY_BASE` | Phoenix secret key | Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Public hostname | `samgita.example.com` |
| `ANTHROPIC_API_KEY` | Anthropic API key for embeddings | `sk-ant-api03-...` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP port | `3110` |
| `POOL_SIZE` | Database connection pool size | `10` |
| `MEMORY_POOL_SIZE` | Memory database pool size | `5` |
| `SAMGITA_API_KEYS` | Comma-separated API keys for REST API | `""` (no auth) |
| `ECTO_IPV6` | Enable IPv6 | `false` |
| `DNS_CLUSTER_QUERY` | DNS query for clustering | `nil` |
| `CLAUDE_COMMAND` | Path to Claude CLI | `claude` |

### Security Configuration

```bash
# Generate secret key base
SECRET_KEY_BASE=$(mix phx.gen.secret)

# Set API keys (comma-separated)
export SAMGITA_API_KEYS="key1,key2,key3"

# ⚠️ IMPORTANT: If SAMGITA_API_KEYS is empty, API has no authentication!
# This is fine for localhost/development, but dangerous for public deployment.
```

---

## Deployment Strategies

### 1. Docker Deployment

**Pros:**
- Consistent environment
- Easy to scale
- Portable across platforms

**Files:**
- `Dockerfile` - Multi-stage build for production
- `docker-compose.yml` - Full stack with PostgreSQL
- `.dockerignore` - Exclude unnecessary files

```bash
# Build image
docker build -t samgita:latest .

# Run with Docker Compose
docker-compose up -d

# View logs
docker-compose logs -f web

# Run migrations
docker-compose exec web mix ecto.migrate

# Stop
docker-compose down
```

### 2. Systemd Service (Linux)

**Pros:**
- Native Linux service management
- Automatic restart on failure
- Boot persistence

**Setup:**

```bash
# 1. Copy service file
sudo cp deployment/systemd/samgita.service /etc/systemd/system/

# 2. Edit service file with your paths and environment
sudo nano /etc/systemd/system/samgita.service

# 3. Reload systemd
sudo systemctl daemon-reload

# 4. Enable service
sudo systemctl enable samgita

# 5. Start service
sudo systemctl start samgita

# 6. Check status
sudo systemctl status samgita

# View logs
sudo journalctl -u samgita -f
```

### 3. Cloud Platforms

#### Fly.io

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Launch app
fly launch

# Deploy
fly deploy

# Set secrets
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly secrets set ANTHROPIC_API_KEY=your-key
```

#### Render

1. Create new Web Service
2. Connect GitHub repository
3. Set environment variables
4. Deploy

#### Railway

1. Create new project
2. Add PostgreSQL plugin
3. Connect GitHub repository
4. Set environment variables
5. Deploy

### 4. Behind Reverse Proxy

#### Nginx

```nginx
upstream samgita {
    server localhost:3110;
}

server {
    listen 80;
    server_name samgita.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name samgita.example.com;

    ssl_certificate /etc/letsencrypt/live/samgita.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/samgita.example.com/privkey.pem;

    location / {
        proxy_pass http://samgita;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### Caddy

```caddyfile
samgita.example.com {
    reverse_proxy localhost:3110
}
```

---

## Monitoring & Operations

### Health Checks

```bash
# Check application health
curl http://localhost:3110/api/health

# Check application info
curl http://localhost:3110/api/info
```

### Database Migrations

```bash
# Run migrations in production
bin/samgita eval "Samgita.Release.migrate()"

# Or with Mix
MIX_ENV=prod mix ecto.migrate
```

### Rollbacks

```bash
# Rollback one migration
MIX_ENV=prod mix ecto.rollback

# Rollback to specific version
MIX_ENV=prod mix ecto.rollback --to 20240101000000
```

### Backups

```bash
# Backup database
pg_dump -Fc samgita_prod > backup_$(date +%Y%m%d_%H%M%S).dump

# Restore database
pg_restore -d samgita_prod backup_20240101_120000.dump
```

### Log Management

```bash
# View logs (release)
tail -f /opt/samgita/log/erlang.log.*

# View logs (systemd)
sudo journalctl -u samgita -f

# View logs (Docker)
docker-compose logs -f web
```

---

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 3110
lsof -i :3110

# Kill process
kill -9 <PID>

# Or change port
export PORT=4000
```

### Database Connection Issues

```bash
# Test PostgreSQL connection
psql $DATABASE_URL -c "SELECT version();"

# Check pgvector extension
psql $DATABASE_URL -c "SELECT * FROM pg_extension WHERE extname = 'vector';"

# Install pgvector if missing
psql $DATABASE_URL -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### Asset Build Failures

```bash
# Clear build artifacts
rm -rf _build deps apps/samgita_web/assets/node_modules

# Reinstall dependencies
mix deps.get
cd apps/samgita_web && bun install && cd ../..

# Rebuild assets
mix assets.build
```

### Release Crashes

```bash
# Check Erlang crash dumps
ls -la erl_crash.dump

# View logs
cat _build/prod/rel/samgita/log/erlang.log.*

# Run in foreground for debugging
bin/samgita start_iex
```

### Memory Issues

```bash
# Monitor Erlang VM
bin/samgita remote

# Inside IEx:
:observer.start()

# Or use system tools
htop
ps aux | grep beam
```

### Claude CLI Not Found

```bash
# Check Claude CLI installation
which claude

# Set custom path
export CLAUDE_COMMAND=/path/to/claude

# Or configure in runtime.exs
config :samgita, :claude_command, "/path/to/claude"
```

---

## Security Checklist

- [ ] Change `SECRET_KEY_BASE` (never use default)
- [ ] Set `SAMGITA_API_KEYS` for API authentication
- [ ] Use HTTPS in production (via reverse proxy)
- [ ] Restrict database access (firewall rules)
- [ ] Run as non-root user
- [ ] Enable firewall (only expose necessary ports)
- [ ] Set up regular database backups
- [ ] Monitor logs for suspicious activity
- [ ] Keep dependencies updated
- [ ] Use VPN or IP whitelist for admin access

---

## Scaling

### Horizontal Scaling (Multiple Nodes)

Samgita uses Horde for distributed supervision. To run multiple nodes:

```bash
# Node 1
iex --name samgita1@10.0.0.1 --cookie samgita_cluster -S mix phx.server

# Node 2
iex --name samgita2@10.0.0.2 --cookie samgita_cluster -S mix phx.server
```

Configure `libcluster` in `config/prod.exs` for automatic clustering.

### Vertical Scaling

Increase resources:

```bash
# Increase database pool size
export POOL_SIZE=20
export MEMORY_POOL_SIZE=10

# Increase Oban concurrency (config/prod.exs)
config :samgita, Oban, queues: [agent_tasks: 200, orchestration: 20]
```

---

## Next Steps

- Review [Security Model](./CONSTITUTION.md)
- Configure [MCP Tools](./mcp-integration.md)
- Set up [Monitoring](./monitoring.md)
- Read [Operations Guide](./operations.md)

---

**Need help?** Open an issue on GitHub or check the [FAQ](./FAQ.md).
