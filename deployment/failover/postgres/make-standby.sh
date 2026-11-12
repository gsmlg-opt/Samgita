#!/bin/bash
# Runs inside a stopped site's db container (as postgres) to make its data
# directory follow the peer primary. The password comes from PGPASSFILE, never
# from the connection string.
set -euo pipefail
primary_host="${1:?usage: make-standby.sh <primary-host>}"
data=/var/lib/postgresql/data
auto="$data/postgresql.auto.conf"
touch "$auto"
sed -i -e '/^primary_conninfo/d' -e '/^primary_slot_name/d' "$auto"
cat >> "$auto" <<CONF
primary_conninfo = 'host=$primary_host port=5432 user=replicator passfile=$PGPASSFILE application_name=samgita_standby'
primary_slot_name = 'samgita_standby'
CONF
touch "$data/standby.signal"
echo "Data directory now follows $primary_host as a standby."
