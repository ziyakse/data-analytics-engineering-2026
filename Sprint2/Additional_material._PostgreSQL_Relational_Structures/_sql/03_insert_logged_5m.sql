-- 03_insert_logged_5m.sql
-- Insert 5,000,000 more rows into regular logged table

\timing on

INSERT INTO labs.test_simple(a, b)
SELECT gs, gs
FROM generate_series(1, 5000000) AS gs;

SELECT count(*) AS logged_table_count_after_6m
FROM labs.test_simple;
