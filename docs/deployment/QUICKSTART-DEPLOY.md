# Samgita Deployment Quickstart

Get Samgita running in production in under 5 minutes.

## Choose Your Deployment Method

### Option 1: Docker (Fastest) ⚡

**Prerequisites:** Docker and Docker Compose installed

```bash
# 1. Clone repository
git clone https://github.com/yourusername/samgita.git
cd samgita

# 2. Configure environment
cp .env.example .env
# Edit .env and set required variables:
# - DB_PASSWORD
# - SECRET_KEY_BASE (generate with: mix phx.gen.secret)
# - ANTHROPIC_API_KEY

# 3. Start services
docker-compose up -d

# 4. Run migrations
docker-compose exec web mix ecto.migrate

# 5. Access application
open http://localhost:3110
```

**Done!** 🎉

---

### Option 2: Manual Release Build

**Prerequisites:** Elixir 1.17+, PostgreSQL 14+, Bun

```bash
# 1. Clone and setup
git clone https://github.com/yourusername/samgita.git
cd samgita
mix deps.get

# 2. Configure database
createdb samgita_prod
psql samgita_prod -c "CREATE EXTENSION IF NOT EXISTS vector;"

# 3. Set environment variables
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export DATABASE_URL="postgresql://user:pass@localhost/samgita_prod"
export ANTHROPIC_API_KEY="your-key"

# 4. Build and run
./deployment/scripts/build-release.sh
_build/prod/rel/samgita/bin/samgita start

# 5. Access application
open http://localhost:3110
```

---

### Option 3: Linux Server with Systemd

**Prerequisites:** Linux server with systemd, PostgreSQL 14+

```bash
# 1. On your local machine, build release
export SECRET_KEY_BASE=$(mix phx.gen.secret)
./deployment/scripts/build-release.sh

# 2. Deploy to server
DEPLOY_HOST=your-server.com ./deployment/scripts/deploy.sh

# 3. On the server, install systemd service
sudo cp deployment/systemd/samgita.service /etc/systemd/system/
sudo systemctl enable samgita
sudo systemctl start samgita

# 4. Verify
./deployment/scripts/health-check.sh your-server.com
```

---

## Required Environment Variables

| Variable | How to Get It | Example |
|----------|---------------|---------|
| `SECRET_KEY_BASE` | `mix phx.gen.secret` | `VeryLongRandomString...` |
| `DATABASE_URL` | PostgreSQL connection | `postgresql://user:pass@host/db` |
| `ANTHROPIC_API_KEY` | [Anthropic Console](https://console.anthropic.com) | `sk-ant-api03-...` |

## Optional Configuration

```bash
# API Keys (comma-separated)
export SAMGITA_API_KEYS="key1,key2,key3"

# Custom port
export PORT=4000

# Database pool sizes
export POOL_SIZE=20
export MEMORY_POOL_SIZE=10
```

## Post-Deployment Checklist

- [ ] Application accessible at http://localhost:3110
- [ ] Health check passes: `curl http://localhost:3110/api/health`
- [ ] Database migrations ran successfully
- [ ] Claude CLI is available (run `claude --version`)
- [ ] API authentication configured (if exposing publicly)
- [ ] SSL/TLS configured (if exposing publicly)
- [ ] Backups scheduled

## Troubleshooting

### "Database connection error"

Check PostgreSQL is running and credentials are correct:

```bash
psql $DATABASE_URL -c "SELECT version();"
```

### "Claude command not found"

Install Claude CLI:

```bash
# Follow instructions at https://claude.ai/
```

Or configure custom path:

```bash
export CLAUDE_COMMAND=/path/to/claude
```

### "Port 3110 already in use"

Change the port:

```bash
export PORT=4000
```

### Health check fails

Check logs:

```bash
# Docker
docker-compose logs -f web

# Release
tail -f _build/prod/rel/samgita/log/erlang.log.*

# Systemd
sudo journalctl -u samgita -f
```

## Next Steps

- Read the [full deployment guide](docs/DEPLOYMENT.md)
- Configure [reverse proxy](docs/DEPLOYMENT.md#behind-reverse-proxy)
- Set up [monitoring](docs/DEPLOYMENT.md#monitoring--operations)
- Review [security checklist](docs/DEPLOYMENT.md#security-checklist)

## Getting Help

- Documentation: [docs/](docs/)
- Issues: [GitHub Issues](https://github.com/yourusername/samgita/issues)
- Security: See [SECURITY.md](SECURITY.md)

---

**Ready to go!** Start building with your agent swarm. 🚀
