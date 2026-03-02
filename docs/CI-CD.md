# CI/CD Pipeline Documentation

This document describes the Continuous Integration and Continuous Deployment (CI/CD) pipeline for Samgita.

## Table of Contents

- [Overview](#overview)
- [CI Pipeline](#ci-pipeline)
- [CD Pipeline](#cd-pipeline)
- [Setup Instructions](#setup-instructions)
- [Deployment Environments](#deployment-environments)
- [Rollback Procedures](#rollback-procedures)
- [Monitoring and Alerts](#monitoring-and-alerts)
- [Troubleshooting](#troubleshooting)

## Overview

Samgita uses GitHub Actions for automated testing, building, and deployment. The pipeline consists of two main workflows:

1. **CI Workflow** (`.github/workflows/ci.yml`) - Runs on every push and pull request
2. **CD Workflow** (`.github/workflows/cd.yml`) - Runs on main branch and tags for deployment

### Architecture

```
┌─────────────┐
│   Git Push  │
└──────┬──────┘
       │
       ├─────────────────┐
       │                 │
       ▼                 ▼
┌──────────┐      ┌──────────┐
│    CI    │      │    CD    │
│ Pipeline │      │ Pipeline │
└─────┬────┘      └─────┬────┘
      │                 │
      ├─────┬─────┬─────┼─────┬─────┐
      ▼     ▼     ▼     ▼     ▼     ▼
   Test  Lint  Sec   Build Deploy Monitor
```

## CI Pipeline

The CI pipeline runs automatically on every push and pull request to ensure code quality.

### Jobs

1. **Quality Checks** (runs in parallel)
   - Code formatting (`mix format --check-formatted`)
   - Linting with Credo (`mix credo --strict`)
   - Type checking with Dialyzer (`mix dialyzer`)

2. **Test Suite**
   - Unit tests across all apps
   - Integration tests
   - Test coverage reporting
   - PostgreSQL 14 with pgvector extension

3. **Security Audit**
   - Dependency vulnerability scanning (`mix deps.audit`)
   - Hex package audit (`mix hex.audit`)

4. **Build Verification** (only on push to main/develop)
   - Production build compilation
   - Asset compilation with Bun
   - Release tarball creation

5. **Docker Build Test** (only on push to main/develop)
   - Multi-stage Docker image build
   - Layer caching for performance

### Trigger Conditions

```yaml
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]
```

### Environment Variables

- `MIX_ENV=test`
- `ELIXIR_VERSION=1.17.3`
- `OTP_VERSION=26.2.5`
- `DATABASE_URL=postgres://postgres:postgres@localhost/samgita_test`

### Artifacts

- Test coverage reports (stored for 7 days)
- Release tarballs (stored for 7 days)

## CD Pipeline

The CD pipeline deploys the application to staging or production environments.

### Jobs

1. **Setup** - Determine target environment and version
2. **Build Image** - Build and push Docker image to GHCR
3. **Deploy Staging** - Deploy to staging environment
4. **Deploy Production** - Deploy to production (on tags only)
5. **Cleanup** - Remove old container images

### Trigger Conditions

**Automatic Deployment:**
```yaml
push:
  branches: [main]        # → staging
  tags: ['v*']            # → production
```

**Manual Deployment:**
```yaml
workflow_dispatch:
  environment: [staging|production]
```

### Deployment Strategies

#### Staging Deployment

- Triggered on every push to `main`
- Automated smoke tests
- Auto-rollback on failure
- No approval required

#### Production Deployment

- Triggered on version tags (e.g., `v1.2.3`)
- Requires environment approval
- Creates GitHub release
- Full backup before deployment
- Comprehensive smoke tests
- Manual rollback if needed

### Container Registry

Images are pushed to GitHub Container Registry (GHCR):

```
ghcr.io/your-org/samgita:main
ghcr.io/your-org/samgita:staging
ghcr.io/your-org/samgita:v1.2.3
ghcr.io/your-org/samgita:sha-abc1234
```

## Setup Instructions

### 1. Configure GitHub Secrets

Navigate to **Settings → Secrets and variables → Actions** in your repository.

#### Required Secrets

**Staging Environment:**
```
STAGING_HOST          # staging.example.com
STAGING_USER          # samgita
STAGING_PATH          # /opt/samgita
STAGING_SSH_KEY       # Private SSH key for deployment
STAGING_URL           # https://staging.example.com
```

**Production Environment:**
```
PRODUCTION_HOST       # production.example.com
PRODUCTION_USER       # samgita
PRODUCTION_PATH       # /opt/samgita
PRODUCTION_SSH_KEY    # Private SSH key for deployment
PRODUCTION_URL        # https://samgita.example.com
```

**Optional:**
```
SAMGITA_API_KEY       # For smoke test authentication
SLACK_WEBHOOK_URL     # For deployment notifications
```

### 2. Set Up Deployment Servers

#### Prerequisites

Each deployment server needs:

- Docker and Docker Compose installed
- SSH access configured
- User with Docker permissions
- PostgreSQL 14+ with pgvector (if not using Docker)
- Firewall rules configured

#### Server Setup Script

```bash
# On deployment server
sudo useradd -m -s /bin/bash samgita
sudo usermod -aG docker samgita
sudo mkdir -p /opt/samgita
sudo chown samgita:samgita /opt/samgita

# Set up SSH key
sudo -u samgita mkdir -p /home/samgita/.ssh
sudo -u samgita chmod 700 /home/samgita/.ssh
echo "YOUR_PUBLIC_KEY" | sudo -u samgita tee /home/samgita/.ssh/authorized_keys
sudo -u samgita chmod 600 /home/samgita/.ssh/authorized_keys
```

### 3. Configure Environment Protection Rules

1. Go to **Settings → Environments**
2. Create two environments: `staging` and `production`
3. For production:
   - ✅ Enable "Required reviewers"
   - ✅ Add deployment approvers
   - ✅ Set deployment branch rule to `main` and tags only

### 4. Generate SSH Keys for Deployment

```bash
# Generate deployment key
ssh-keygen -t ed25519 -C "github-actions-deploy" -f deploy_key

# Add public key to server
ssh-copy-id -i deploy_key.pub samgita@staging.example.com

# Add private key to GitHub secrets
cat deploy_key | pbcopy  # Copy to clipboard
# Paste into STAGING_SSH_KEY secret
```

### 5. Test the Pipeline

```bash
# Test CI pipeline
git checkout -b test-ci
git commit --allow-empty -m "test: CI pipeline"
git push origin test-ci

# Open pull request and verify CI passes

# Test staging deployment
git checkout main
git merge test-ci
git push origin main

# Test production deployment
git tag v0.1.0
git push origin v0.1.0
```

## Deployment Environments

### Staging

**Purpose:** Pre-production testing and validation

**Characteristics:**
- Automatic deployment on main branch
- Relaxed resource limits
- Debug logging enabled
- Test data allowed
- No approval required

**URL:** Configured via `STAGING_URL` secret

### Production

**Purpose:** Live production environment

**Characteristics:**
- Manual approval required
- Version-tagged deployments only
- Full backup before deployment
- Resource limits enforced
- Production logging
- Real data only

**URL:** Configured via `PRODUCTION_URL` secret

## Rollback Procedures

### Automatic Rollback

Deployments automatically roll back if:
- Health check fails
- Smoke tests fail
- Deployment script errors

### Manual Rollback

#### Using Rollback Script

```bash
# SSH to deployment server
ssh samgita@production.example.com

# Run rollback script
cd /opt/samgita
./rollback.sh

# Or trigger via GitHub Actions
# Set DEPLOY_HOST, DEPLOY_USER environment variables
./deployment/scripts/rollback.sh
```

#### Using Docker

```bash
# On deployment server
cd /opt/samgita

# Stop current containers
docker-compose down

# Restore previous deployment
BACKUP_DIR=$(ls -dt /opt/samgita.backup.* | head -1)
rm -rf /opt/samgita
cp -r $BACKUP_DIR /opt/samgita

# Restart
cd /opt/samgita
docker-compose up -d
```

#### Using Git Tags

```bash
# Roll back to previous version
git tag v1.2.2  # Previous version
git push origin v1.2.2

# This triggers production deployment with old version
```

## Monitoring and Alerts

### Health Checks

**Endpoints:**
- `/api/health` - Application health status
- `/api/info` - Application version and info

**Monitoring:**
```bash
# Continuous health check
watch -n 10 curl -s https://samgita.example.com/api/health

# Check from GitHub Actions
curl -f https://samgita.example.com/api/health || exit 1
```

### Logs

**Docker Deployment:**
```bash
# View logs
docker-compose logs -f web

# Last 100 lines
docker-compose logs --tail=100 web

# Filter errors
docker-compose logs web | grep ERROR
```

**Native Deployment:**
```bash
# Systemd logs
journalctl -u samgita -f

# Last 100 lines
journalctl -u samgita -n 100

# Errors only
journalctl -u samgita -p err
```

### Metrics

Access Phoenix LiveDashboard (dev/test only):
```
http://localhost:3110/dev/dashboard
```

Production metrics should use external monitoring (Prometheus, Datadog, etc.)

## Troubleshooting

### CI Pipeline Failures

#### Tests Failing

```bash
# Run tests locally with same environment
MIX_ENV=test mix test

# Check database connectivity
psql postgres://postgres:postgres@localhost/samgita_test -c "SELECT 1"

# Run specific failing test
mix test path/to/failing_test.exs:line_number
```

#### Format Check Failing

```bash
# Auto-format code
mix format

# Check what would be formatted
mix format --check-formatted --dry-run
```

#### Dialyzer Failing

```bash
# Clean PLT cache
rm -rf priv/plts

# Rebuild and run
mix dialyzer
```

### CD Pipeline Failures

#### Docker Build Failing

```bash
# Build locally to debug
docker build -t samgita:test .

# Check build args
docker build --build-arg ELIXIR_VERSION=1.17.3 -t samgita:test .

# Build with no cache
docker build --no-cache -t samgita:test .
```

#### Deployment Failing

```bash
# Test SSH connectivity
ssh samgita@staging.example.com "echo Connected"

# Test Docker on remote
ssh samgita@staging.example.com "docker ps"

# Check disk space
ssh samgita@staging.example.com "df -h"

# Check logs
ssh samgita@staging.example.com "cd /opt/samgita && docker-compose logs"
```

#### Health Check Failing

```bash
# Check service status
ssh samgita@staging.example.com "cd /opt/samgita && docker-compose ps"

# Check application logs
ssh samgita@staging.example.com "cd /opt/samgita && docker-compose logs web"

# Check database connectivity
ssh samgita@staging.example.com "cd /opt/samgita && docker-compose exec web bin/samgita rpc 'Samgita.Repo.__adapter__.query(Samgita.Repo, \"SELECT 1\", [])'"
```

### Common Issues

#### Issue: "Permission denied (publickey)"

**Solution:**
```bash
# Verify SSH key is added to GitHub secrets
# Test SSH connection manually
ssh -i deploy_key samgita@staging.example.com

# Ensure key permissions are correct (600)
chmod 600 deploy_key
```

#### Issue: "Database connection failed"

**Solution:**
```bash
# Check DATABASE_URL in .env
# Verify PostgreSQL is running
ssh samgita@staging.example.com "docker-compose ps db"

# Check database logs
ssh samgita@staging.example.com "docker-compose logs db"
```

#### Issue: "Port 3110 already in use"

**Solution:**
```bash
# Find process using port
ssh samgita@staging.example.com "lsof -i :3110"

# Stop conflicting service
ssh samgita@staging.example.com "docker-compose down"
```

## Best Practices

### Branch Strategy

```
main       ───●───●───●────●────●── (auto-deploy to staging)
            │   │   │    │    │
            │   │   │    │    └─ v1.2.0 tag → production
            │   │   │    └────── PR merge
            │   │   └─────────── PR merge
            └───┴──────────────── feature branches
```

### Versioning

Use Semantic Versioning (SemVer):

```
v1.0.0     # Major.Minor.Patch
 │ │ │
 │ │ └─── Bug fixes (backward compatible)
 │ └───── New features (backward compatible)
 └─────── Breaking changes
```

### Commit Messages

Follow Conventional Commits:

```
feat: add user authentication
fix: resolve database connection pool exhaustion
docs: update deployment guide
chore: upgrade dependencies
test: add integration tests for orchestrator
```

### Deployment Checklist

Before deploying to production:

- [ ] All CI checks pass
- [ ] Staging deployment successful
- [ ] Smoke tests pass
- [ ] Database migrations reviewed
- [ ] Environment variables updated
- [ ] Backup strategy confirmed
- [ ] Rollback plan documented
- [ ] Stakeholders notified
- [ ] Monitoring configured
- [ ] Documentation updated

## Security Considerations

### Secrets Management

- Never commit secrets to repository
- Rotate deployment keys quarterly
- Use environment-specific API keys
- Enable branch protection rules
- Require signed commits

### Access Control

- Limit who can approve production deployments
- Use separate SSH keys per environment
- Implement least-privilege access
- Audit deployment logs regularly

### Network Security

- Deploy behind reverse proxy (nginx)
- Enable SSL/TLS certificates
- Configure firewall rules
- Use VPN for admin access
- Rate limit API endpoints

## Performance Optimization

### Build Optimization

```yaml
# Cache dependencies
- uses: actions/cache@v3
  with:
    path: deps
    key: ${{ hashFiles('**/mix.lock') }}

# Parallel job execution
jobs:
  test:
    strategy:
      matrix:
        app: [samgita, samgita_web, samgita_memory]
```

### Deployment Optimization

- Use Docker layer caching
- Pre-pull base images
- Minimize image size
- Keep warm standby containers
- Use blue-green deployments

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Documentation](https://docs.docker.com/)
- [Phoenix Deployment Guides](https://hexdocs.pm/phoenix/deployment.html)
- [Elixir Release Documentation](https://hexdocs.pm/mix/Mix.Tasks.Release.html)

## Support

For issues with the CI/CD pipeline:

1. Check this documentation
2. Review GitHub Actions logs
3. Consult deployment logs
4. Open an issue on GitHub
5. Contact DevOps team

---

**Last Updated:** 2026-03-03
**Maintained By:** DevOps Team
