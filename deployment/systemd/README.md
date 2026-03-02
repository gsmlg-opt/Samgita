# Systemd Service Configuration

This directory contains systemd service files for running Samgita as a system service on Linux.

## Installation

### 1. Create Service User

```bash
sudo useradd --system --create-home --home /opt/samgita samgita
```

### 2. Deploy Application

```bash
# Build release
MIX_ENV=prod mix release

# Copy to target location
sudo mkdir -p /opt/samgita
sudo cp -r _build/prod/rel/samgita/* /opt/samgita/
sudo chown -R samgita:samgita /opt/samgita
```

### 3. Create Environment File

```bash
sudo mkdir -p /opt/samgita/etc
sudo nano /opt/samgita/etc/samgita.env
```

Add the following variables:

```bash
DATABASE_URL=postgresql://user:pass@localhost/samgita_prod
SECRET_KEY_BASE=your_secret_key_here
PHX_HOST=samgita.example.com
ANTHROPIC_API_KEY=your_api_key_here
SAMGITA_API_KEYS=key1,key2,key3
POOL_SIZE=10
MEMORY_POOL_SIZE=5
```

Secure the file:

```bash
sudo chmod 600 /opt/samgita/etc/samgita.env
sudo chown samgita:samgita /opt/samgita/etc/samgita.env
```

### 4. Install Service File

```bash
# Copy service file
sudo cp samgita.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable samgita

# Start service
sudo systemctl start samgita

# Check status
sudo systemctl status samgita
```

## Managing the Service

### Start, Stop, Restart

```bash
sudo systemctl start samgita
sudo systemctl stop samgita
sudo systemctl restart samgita
```

### View Status

```bash
sudo systemctl status samgita
```

### View Logs

```bash
# Follow logs
sudo journalctl -u samgita -f

# Last 100 lines
sudo journalctl -u samgita -n 100

# Logs from today
sudo journalctl -u samgita --since today
```

### Enable/Disable Auto-start

```bash
sudo systemctl enable samgita   # Auto-start on boot
sudo systemctl disable samgita  # Don't auto-start
```

## Database Migrations

To run migrations:

```bash
sudo -u samgita /opt/samgita/bin/samgita eval "Samgita.Release.migrate()"
```

## Troubleshooting

### Service Won't Start

Check logs:

```bash
sudo journalctl -u samgita -n 50
```

Common issues:
- Missing environment variables
- Database connection failure
- Port already in use
- Permission issues

### Permission Denied Errors

Ensure proper ownership:

```bash
sudo chown -R samgita:samgita /opt/samgita
sudo chmod +x /opt/samgita/bin/samgita
```

### Port Already in Use

Change the PORT in environment file or find conflicting process:

```bash
sudo lsof -i :3110
```

## Updating the Application

1. Build new release
2. Stop service
3. Backup current release
4. Deploy new release
5. Run migrations
6. Start service

```bash
# Stop service
sudo systemctl stop samgita

# Backup
sudo cp -r /opt/samgita /opt/samgita.backup.$(date +%Y%m%d)

# Deploy new version
sudo cp -r _build/prod/rel/samgita/* /opt/samgita/
sudo chown -R samgita:samgita /opt/samgita

# Run migrations
sudo -u samgita /opt/samgita/bin/samgita eval "Samgita.Release.migrate()"

# Start service
sudo systemctl start samgita

# Check status
sudo systemctl status samgita
```

## Uninstallation

```bash
# Stop and disable service
sudo systemctl stop samgita
sudo systemctl disable samgita

# Remove service file
sudo rm /etc/systemd/system/samgita.service

# Reload systemd
sudo systemctl daemon-reload

# Remove application (optional)
sudo rm -rf /opt/samgita

# Remove user (optional)
sudo userdel samgita
```
