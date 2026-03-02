# Deployment Scripts

This directory contains helper scripts for building, deploying, and managing Samgita.

## Scripts Overview

### build-release.sh

Builds a production release of Samgita.

**Usage:**

```bash
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export DATABASE_URL="postgresql://user:pass@localhost/samgita_prod"
./deployment/scripts/build-release.sh
```

**Output:** `_build/prod/rel/samgita/`

### deploy.sh

Deploys Samgita to a remote server via SSH.

**Requirements:**
- SSH access to target server
- Pre-built release (run `build-release.sh` first)

**Usage:**

```bash
DEPLOY_HOST=your-server.com \
DEPLOY_USER=samgita \
DEPLOY_PATH=/opt/samgita \
./deployment/scripts/deploy.sh
```

**What it does:**
1. Creates backup on target server
2. Stops the service
3. Uploads new release
4. Runs database migrations
5. Starts the service
6. Performs health check

### docker-build.sh

Builds and optionally pushes Docker image to registry.

**Usage:**

```bash
# Build locally
./deployment/scripts/docker-build.sh

# Build and push to registry
DOCKER_REGISTRY=ghcr.io/yourusername \
DOCKER_IMAGE=samgita \
DOCKER_TAG=v0.1.0 \
./deployment/scripts/docker-build.sh
```

### health-check.sh

Checks if Samgita is running and healthy.

**Usage:**

```bash
# Check localhost
./deployment/scripts/health-check.sh

# Check remote server
./deployment/scripts/health-check.sh your-server.com 3110
```

**Exit codes:**
- 0: Healthy
- 1: Unhealthy or unreachable

## Common Workflows

### Initial Deployment

```bash
# 1. Set up environment variables
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export DATABASE_URL="postgresql://user:pass@host/samgita_prod"
export ANTHROPIC_API_KEY="your-key"

# 2. Build release
./deployment/scripts/build-release.sh

# 3. Deploy to server
DEPLOY_HOST=your-server.com ./deployment/scripts/deploy.sh

# 4. Verify deployment
./deployment/scripts/health-check.sh your-server.com
```

### Docker Deployment

```bash
# 1. Create .env file
cp .env.example .env
# Edit .env with your configuration

# 2. Start services
docker-compose up -d

# 3. Run migrations
docker-compose exec web mix ecto.migrate

# 4. Check health
./deployment/scripts/health-check.sh localhost 3110
```

### Updating Production

```bash
# 1. Build new release
./deployment/scripts/build-release.sh

# 2. Deploy (automatically creates backup)
DEPLOY_HOST=your-server.com ./deployment/scripts/deploy.sh

# 3. Monitor logs
ssh samgita@your-server.com 'journalctl -u samgita -f'
```

### Rollback

If deployment fails, you can rollback to the previous version:

```bash
# SSH into server
ssh samgita@your-server.com

# List backups
ls -la /opt/samgita.backup.*

# Stop service
sudo systemctl stop samgita

# Restore backup
BACKUP_PATH=/opt/samgita.backup.20240101_120000
sudo rm -rf /opt/samgita
sudo cp -r $BACKUP_PATH /opt/samgita

# Start service
sudo systemctl start samgita
```

## Environment Variables

All scripts respect standard environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `SECRET_KEY_BASE` | Phoenix secret key | Required |
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `ANTHROPIC_API_KEY` | Anthropic API key | Required |
| `DEPLOY_HOST` | Target server hostname | None |
| `DEPLOY_USER` | SSH user | `samgita` |
| `DEPLOY_PATH` | Target path on server | `/opt/samgita` |
| `DOCKER_REGISTRY` | Docker registry URL | None |
| `DOCKER_IMAGE` | Docker image name | `samgita` |
| `DOCKER_TAG` | Docker image tag | `latest` |

## Troubleshooting

### Release build fails

Check that all required environment variables are set:

```bash
echo $SECRET_KEY_BASE
echo $DATABASE_URL
```

### Deployment fails

Check SSH access:

```bash
ssh samgita@your-server.com
```

Check target path permissions:

```bash
ssh samgita@your-server.com 'ls -la /opt/samgita'
```

### Health check fails

Check if service is running:

```bash
ssh samgita@your-server.com 'systemctl status samgita'
```

Check logs:

```bash
ssh samgita@your-server.com 'journalctl -u samgita -n 50'
```

## Security Notes

- Never commit `.env` files
- Rotate `SECRET_KEY_BASE` periodically
- Use strong database passwords
- Limit SSH access to deployment key
- Run services as non-root user
- Keep backups of production data

## Next Steps

- Set up monitoring and alerting
- Configure log aggregation
- Implement blue-green deployment
- Set up CI/CD pipeline
- Configure auto-scaling
