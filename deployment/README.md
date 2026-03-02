# Samgita Deployment Resources

This directory contains all resources needed to deploy Samgita in various environments.

## Directory Structure

```
deployment/
├── docker/              # Docker-specific files
│   └── entrypoint.sh   # Container entrypoint script
├── nginx/              # Nginx reverse proxy configuration
│   └── nginx.conf      # Production nginx config with SSL
├── postgres/           # PostgreSQL initialization
│   └── init.sql        # Database setup SQL
├── scripts/            # Deployment automation scripts
│   ├── build-release.sh   # Build production release
│   ├── deploy.sh          # Deploy to remote server
│   ├── docker-build.sh    # Build Docker image
│   ├── health-check.sh    # Health check utility
│   └── README.md          # Scripts documentation
└── systemd/            # Linux systemd service files
    ├── samgita.service    # Systemd unit file
    └── README.md          # Systemd setup guide
```

## Quick Links

- **Getting Started**: See [QUICKSTART-DEPLOY.md](../QUICKSTART-DEPLOY.md) in root
- **Full Guide**: See [docs/DEPLOYMENT.md](../docs/DEPLOYMENT.md)
- **Scripts**: See [scripts/README.md](scripts/README.md)
- **Systemd**: See [systemd/README.md](systemd/README.md)

## Deployment Methods

### 1. Docker Compose (Recommended for Development)

**Files needed:**
- `../docker-compose.yml`
- `docker/entrypoint.sh`
- `postgres/init.sql`
- `../.env` (from `.env.example`)

**Command:**
```bash
docker-compose up -d
```

### 2. Manual Release Build

**Files needed:**
- `scripts/build-release.sh`

**Command:**
```bash
./deployment/scripts/build-release.sh
```

### 3. Server Deployment with SSH

**Files needed:**
- `scripts/build-release.sh`
- `scripts/deploy.sh`

**Command:**
```bash
DEPLOY_HOST=server.com ./deployment/scripts/deploy.sh
```

### 4. Systemd Service (Linux Servers)

**Files needed:**
- `systemd/samgita.service`
- Built release

**Setup:**
```bash
sudo cp deployment/systemd/samgita.service /etc/systemd/system/
sudo systemctl enable samgita
sudo systemctl start samgita
```

### 5. Docker with Nginx Reverse Proxy

**Files needed:**
- `../docker-compose.yml` (with nginx profile)
- `nginx/nginx.conf`
- SSL certificates

**Command:**
```bash
docker-compose --profile with-nginx up -d
```

## Environment Variables

All deployment methods require these environment variables:

### Required
- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY_BASE` - Phoenix secret (generate with `mix phx.gen.secret`)
- `ANTHROPIC_API_KEY` - Anthropic API key for embeddings

### Optional
- `PORT` - HTTP port (default: 3110)
- `SAMGITA_API_KEYS` - API authentication keys
- `POOL_SIZE` - Database pool size (default: 10)
- `MEMORY_POOL_SIZE` - Memory DB pool size (default: 5)
- `PHX_HOST` - Public hostname
- `CLAUDE_COMMAND` - Path to Claude CLI (default: claude)

## Pre-Deployment Checklist

- [ ] PostgreSQL 14+ with pgvector extension installed
- [ ] Elixir 1.17+ with Erlang/OTP 26+ (for building)
- [ ] Bun installed (for asset compilation)
- [ ] Claude CLI installed and configured
- [ ] Environment variables configured
- [ ] Database created and migrated
- [ ] Firewall rules configured
- [ ] SSL/TLS certificates (for production)
- [ ] Backup strategy in place

## Post-Deployment Verification

```bash
# 1. Health check
curl http://localhost:3110/api/health

# 2. Application info
curl http://localhost:3110/api/info

# 3. Check logs
# Docker:
docker-compose logs -f web

# Systemd:
sudo journalctl -u samgita -f

# Release:
tail -f _build/prod/rel/samgita/log/erlang.log.*
```

## Common Issues

### PostgreSQL Connection Failed

```bash
# Check database
psql $DATABASE_URL -c "SELECT version();"

# Check pgvector extension
psql $DATABASE_URL -c "SELECT * FROM pg_extension WHERE extname = 'vector';"
```

### Port Already in Use

```bash
# Find process
lsof -i :3110

# Change port
export PORT=4000
```

### Asset Build Failed

```bash
# Reinstall dependencies
cd apps/samgita_web
rm -rf node_modules .bun-cache
bun install
cd ../..
```

## Security Considerations

### For Production Deployments

1. **Never expose without authentication**
   - Set `SAMGITA_API_KEYS` if exposing API
   - Use firewall/VPN for admin access
   - Run behind reverse proxy with SSL

2. **Database Security**
   - Use strong passwords
   - Restrict network access
   - Enable SSL connections
   - Regular backups

3. **System Hardening**
   - Run as non-root user
   - Limit file system access
   - Set resource limits
   - Keep dependencies updated

4. **Secrets Management**
   - Never commit `.env` files
   - Use environment variables
   - Rotate keys regularly
   - Use secret management tools

## Monitoring

### Health Endpoint

```bash
GET /api/health
```

Returns `200 OK` if application is healthy.

### Application Info

```bash
GET /api/info
```

Returns application version and configuration info.

### Metrics

- Phoenix LiveDashboard: `/dev/dashboard` (dev/test only)
- System metrics via `:observer` in IEx
- Custom Telemetry events

## Scaling

### Horizontal Scaling

Samgita uses Horde for distributed supervision. To scale horizontally:

1. Configure `libcluster` for node discovery
2. Set `DNS_CLUSTER_QUERY` environment variable
3. Start multiple nodes with unique names
4. Nodes automatically form cluster

### Vertical Scaling

- Increase `POOL_SIZE` and `MEMORY_POOL_SIZE`
- Adjust Oban queue concurrency
- Allocate more CPU/RAM to container/VM

## Backup and Recovery

### Database Backup

```bash
# Backup
pg_dump -Fc $DATABASE_URL > backup.dump

# Restore
pg_restore -d $DATABASE_URL backup.dump
```

### Application State

Samgita stores all state in PostgreSQL. Backup the database to backup application state.

## Updating

### Docker

```bash
docker-compose pull
docker-compose up -d
```

### Release

```bash
# Build new release
./deployment/scripts/build-release.sh

# Deploy
DEPLOY_HOST=server.com ./deployment/scripts/deploy.sh
```

### In-Place Update

```bash
# Stop service
sudo systemctl stop samgita

# Backup
cp -r /opt/samgita /opt/samgita.backup

# Update files
cp -r _build/prod/rel/samgita/* /opt/samgita/

# Migrate
/opt/samgita/bin/samgita eval "Samgita.Release.migrate()"

# Start
sudo systemctl start samgita
```

## Support

- **Documentation**: [../docs/](../docs/)
- **Issues**: GitHub Issues
- **Security**: See [../SECURITY.md](../SECURITY.md)

## License

See [../LICENSE](../LICENSE)
