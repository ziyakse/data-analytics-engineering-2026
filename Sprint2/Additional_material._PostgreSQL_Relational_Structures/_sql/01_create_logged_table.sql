-- 01_create_logged_table.sql
-- Create regular logged table

\timing on

DROP TABLE IF EXISTS labs.test_simple;

CREATE TABLE labs.test_simple (
    a int,
    b int
);
