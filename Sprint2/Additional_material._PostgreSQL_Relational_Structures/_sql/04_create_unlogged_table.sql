-- 04_create_unlogged_table.sql
-- Create unlogged table

\timing on

DROP TABLE IF EXISTS labs.test_unlogged;

CREATE UNLOGGED TABLE labs.test_unlogged (
    a int,
    b int
);
