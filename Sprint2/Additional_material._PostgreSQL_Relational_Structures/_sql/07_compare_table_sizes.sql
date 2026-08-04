-- 07_compare_table_sizes.sql
-- Compare table sizes after inserts

\timing on

SELECT 
    pg_size_pretty(pg_relation_size('labs.test_simple')) AS test_simple_size,
    pg_size_pretty(pg_relation_size('labs.test_unlogged')) AS test_unlogged_size;
