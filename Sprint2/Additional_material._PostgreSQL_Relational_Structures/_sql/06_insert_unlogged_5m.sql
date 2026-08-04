-- 06_insert_unlogged_5m.sql
-- Insert 5,000,000 more rows into unlogged table

\timing on

INSERT INTO labs.test_unlogged(a, b)
SELECT gs, gs
FROM generate_series(1, 5000000) AS gs;

SELECT count(*) AS unlogged_table_count_after_6m
FROM labs.test_unlogged;
