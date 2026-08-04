-- 02_insert_logged_1m.sql
-- Insert 1,000,000 rows into regular logged table

\timing on

INSERT INTO labs.test_simple(a, b)
SELECT gs, gs
FROM generate_series(1, 1000000) AS gs;

SELECT count(*) AS logged_table_count_after_1m
FROM labs.test_simple;
