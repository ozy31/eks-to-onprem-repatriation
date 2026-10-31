-- Prepare RDS as the logical replication source.
--
-- Prerequisites (parameter group, needs a reboot):
--   rds.logical_replication = 1
--   max_replication_slots / max_wal_senders >= current + 2
--
-- Run as the owner of the application tables (psql -v ON_ERROR_STOP=1).

-- Replication user used by CloudNativePG for the schema import and the
-- subscription. Password from OpenBao: migration/rds-replicator.
CREATE ROLE cnpg_replicator WITH LOGIN PASSWORD :'replicator_password';
GRANT rds_replication TO cnpg_replicator;
GRANT CONNECT ON DATABASE orders TO cnpg_replicator;
GRANT USAGE ON SCHEMA public TO cnpg_replicator;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO cnpg_replicator;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO cnpg_replicator;

-- FOR ALL TABLES needs a real superuser, which RDS does not give, so the
-- publication lists the tables explicitly. Tables created during the
-- migration window must be added with ALTER PUBLICATION (schema freeze).
SELECT format('CREATE PUBLICATION orders_migration FOR TABLE %s;',
              string_agg(format('%I.%I', schemaname, tablename), ', ' ORDER BY tablename))
FROM pg_tables
WHERE schemaname = 'public'
\gexec

-- Logical replication needs a replica identity. Tables without a primary key
-- would replicate inserts but fail on UPDATE/DELETE; list them and fix first.
SELECT c.relname AS table_without_primary_key
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relreplident = 'd'
  AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.oid AND i.indisprimary);
