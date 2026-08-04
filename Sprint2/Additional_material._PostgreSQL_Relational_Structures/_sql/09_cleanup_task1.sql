-- 09_cleanup_task1.sql
-- Optional cleanup script
-- Run this only if you want to remove Task 1 test tables.

\timing on

DROP TABLE IF EXISTS labs.test_simple;
DROP TABLE IF EXISTS labs.test_unlogged;
