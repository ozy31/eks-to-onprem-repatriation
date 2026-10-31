# 5. Move PostgreSQL with logical replication, keep a reverse path

Status: accepted

## Context

The RDS database is about 400 GB, and the service tolerates a few minutes of
write downtime but not hours. RDS does not allow physical replication to a
server outside RDS, so a CloudNativePG replica cluster streaming from RDS is
not an option.

## Decision

- CloudNativePG imports the schema only (`initdb.import.schemaOnly`).
- A declarative `Subscription` copies the data and streams changes from a
  publication on RDS. RDS does not grant superuser, so the publication lists
  the tables explicitly (`rds-source.sql`).
- `cutover.sh` does the switch: wait for lag 0, copy sequences, compare row
  counts, disable the subscription.
- Right after the switch RDS subscribes to a publication on CloudNativePG, so
  for the rollback window RDS stays current and rolling back is a secret
  change, not a restore.

## Consequences

- The write downtime is the time to drain the lag and copy sequences: minutes.
- Logical replication does not carry DDL or sequences. The schema is frozen
  during the migration window, and sequences are copied at cutover (both ways
  on rollback).
- Every table needs a primary key or replica identity; `rds-source.sql` lists
  the ones that do not.
- The new cluster can run a newer PostgreSQL major version than RDS; the
  migration is also the upgrade.

## Alternatives considered

- **pg_dump / pg_restore in a window.** Hours of downtime at this size.
- **AWS DMS.** Works, but it is one more service to run, it handles some types
  poorly, and it offers no rollback path.
