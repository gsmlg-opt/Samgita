#!/bin/bash
# Runs once, when the official image initializes an empty data directory on the
# first primary. Standbys copy these roles through replication.
set -euo pipefail
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v repl_pw="$REPLICATION_PASSWORD" -v mon_pw="$MONITOR_PASSWORD" -v rew_pw="$REWIND_PASSWORD" <<'SQL'
CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD :'repl_pw';
-- Peer guard: connects only to read pg_is_in_recovery().
CREATE ROLE samgita_monitor WITH LOGIN PASSWORD :'mon_pw';
-- Least-privilege pg_rewind source role (PostgreSQL pg_rewind documentation).
CREATE ROLE samgita_rewind WITH LOGIN PASSWORD :'rew_pw';
GRANT EXECUTE ON FUNCTION pg_catalog.pg_ls_dir(text, boolean, boolean) TO samgita_rewind;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_stat_file(text, boolean) TO samgita_rewind;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_read_binary_file(text) TO samgita_rewind;
GRANT EXECUTE ON FUNCTION pg_catalog.pg_read_binary_file(text, bigint, bigint, boolean) TO samgita_rewind;
SELECT pg_create_physical_replication_slot('samgita_standby');
SQL
