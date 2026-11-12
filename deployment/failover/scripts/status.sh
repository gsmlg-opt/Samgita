#!/bin/bash
# Show both sites: role marker, upstream, web, database role and replication.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
self status
peer status || echo "site=$PEER_SITE_NAME unreachable"
