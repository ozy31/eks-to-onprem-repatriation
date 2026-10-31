#!/usr/bin/env bash
# Move writes for "orders" from RDS to CloudNativePG.
#
#   RDS_URL=postgres://...rds...  CNPG_URL=postgres://...orders-db-rw...  ./cutover.sh check
#   ... ./cutover.sh cutover
#
# "check" is read-only and can run any time. "cutover" expects the application
# to be in maintenance mode (writes stopped) and does, in order:
#   1. wait until the subscription has applied everything RDS has written
#   2. copy sequence values (logical replication does not replicate sequences)
#   3. compare row counts per table
#   4. disable the RDS -> CNPG subscription
#   5. subscribe RDS to CNPG's rollback publication (reverse replication)
# Switching the application's database secret is the next, separate step
# (docs/runbook.md, phase 3).
set -euo pipefail

: "${RDS_URL:?RDS_URL is required}"
: "${CNPG_URL:?CNPG_URL is required}"
SUBSCRIPTION="${SUBSCRIPTION:-orders_from_rds}"
PUBLICATION="${PUBLICATION:-orders_migration}"
ROLLBACK_PUBLICATION="${ROLLBACK_PUBLICATION:-orders_rollback}"
CNPG_PUBLIC_URL="${CNPG_PUBLIC_URL:-}"   # how RDS reaches CNPG (over the VPN)

rds()  { psql "$RDS_URL"  -v ON_ERROR_STOP=1 -XAtq "$@"; }
cnpg() { psql "$CNPG_URL" -v ON_ERROR_STOP=1 -XAtq "$@"; }
log()  { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# Bytes of WAL the subscription slot on RDS has not confirmed yet.
lag_bytes() {
  rds -c "SELECT COALESCE(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn), -1)::bigint
          FROM pg_replication_slots WHERE slot_name = '${SUBSCRIPTION}'"
}

# Tables still in the initial copy (state other than r = ready).
tables_syncing() {
  cnpg -c "SELECT count(*) FROM pg_subscription_rel sr
           JOIN pg_subscription s ON s.oid = sr.srsubid
           WHERE s.subname = '${SUBSCRIPTION}' AND sr.srsubstate <> 'r'"
}

compare_counts() {
  local failed=0 table src dst
  for table in $(rds -c "SELECT format('%I.%I', schemaname, tablename)
                         FROM pg_publication_tables WHERE pubname = '${PUBLICATION}' ORDER BY 1"); do
    src=$(rds  -c "SELECT count(*) FROM ${table}")
    dst=$(cnpg -c "SELECT count(*) FROM ${table}")
    if [ "$src" != "$dst" ]; then
      log "MISMATCH ${table}: rds=${src} cnpg=${dst}"
      failed=1
    fi
  done
  return "$failed"
}

check() {
  log "tables still in initial copy: $(tables_syncing)"
  log "replication lag: $(lag_bytes) bytes"
}

cutover() {
  local syncing lag
  syncing=$(tables_syncing)
  if [ "$syncing" != "0" ]; then
    log "abort: ${syncing} tables are still in the initial copy"
    exit 1
  fi

  log "waiting for the subscription to catch up"
  for _ in $(seq 1 120); do
    lag=$(lag_bytes)
    [ "$lag" = "0" ] && break
    log "lag ${lag} bytes"
    sleep 5
  done
  if [ "$lag" != "0" ]; then
    log "abort: lag did not reach 0 in 10 minutes; are writes really stopped?"
    exit 1
  fi

  log "copying sequence values"
  rds -c "SELECT format('SELECT setval(%L, %s, true);', format('%I.%I', schemaname, sequencename), last_value)
          FROM pg_sequences WHERE last_value IS NOT NULL" | cnpg

  log "comparing row counts"
  compare_counts || { log "abort: row counts differ; RDS is still the primary"; exit 1; }

  log "disabling subscription ${SUBSCRIPTION}"
  cnpg -c "ALTER SUBSCRIPTION ${SUBSCRIPTION} DISABLE"

  if [ -n "$CNPG_PUBLIC_URL" ]; then
    log "subscribing RDS to ${ROLLBACK_PUBLICATION} (copy_data=false: RDS already has the data)"
    rds -c "CREATE SUBSCRIPTION orders_rollback CONNECTION '${CNPG_PUBLIC_URL}'
            PUBLICATION ${ROLLBACK_PUBLICATION} WITH (copy_data = false)"
  else
    log "CNPG_PUBLIC_URL not set: no reverse replication, rollback means a restore"
  fi

  log "done: point the application at CloudNativePG and leave maintenance mode"
  log "next: merge the PR that removes subscription.yaml; deleting the Subscription"
  log "      drops its slot on RDS, which otherwise keeps WAL growing"
}

case "${1:-check}" in
  check) check ;;
  cutover) cutover ;;
  *) echo "usage: $0 check|cutover" >&2; exit 2 ;;
esac
