-- 05_insert_unlogged_1m.sql
-- Insert 1,000,000 rows into unlogged table

\timing on

INSERT INTO labs.test_unlogged(a, b)
SELECT gs, gs
FROM generate_series(1, 1000000) AS gs;

SELECT count(*) AS unlogged_table_count_after_1m
FROM labs.test_unlogged;
