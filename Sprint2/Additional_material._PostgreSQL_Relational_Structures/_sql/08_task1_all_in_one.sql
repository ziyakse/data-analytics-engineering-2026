-- 08_task1_all_in_one.sql
-- Full Task 1 script
-- This file runs the whole Task 1 from beginning to end.

\timing on

CREATE SCHEMA IF NOT EXISTS labs;

SET search_path TO labs, public;

DROP TABLE IF EXISTS labs.person CASCADE;

CREATE TABLE labs.person (
    id integer NOT NULL,
    name varchar(15)
);

INSERT INTO labs.person(id, name) VALUES (1, 'Bob');
INSERT INTO labs.person(id, name) VALUES (2, 'Alice');
INSERT INTO labs.person(id, name) VALUES (3, 'Robert');

SELECT * FROM labs.person;


DROP TABLE IF EXISTS labs.test_simple;
DROP TABLE IF EXISTS labs.test_unlogged;


CREATE TABLE labs.test_simple (
    a int,
    b int
);

INSERT INTO labs.test_simple(a, b)
SELECT gs, gs
FROM generate_series(1, 1000000) AS gs;

SELECT count(*) AS logged_table_count_after_1m
FROM labs.test_simple;

INSERT INTO labs.test_simple(a, b)
SELECT gs, gs
FROM generate_series(1, 5000000) AS gs;

SELECT count(*) AS logged_table_count_after_6m
FROM labs.test_simple;


CREATE UNLOGGED TABLE labs.test_unlogged (
    a int,
    b int
);

INSERT INTO labs.test_unlogged(a, b)
SELECT gs, gs
FROM generate_series(1, 1000000) AS gs;

SELECT count(*) AS unlogged_table_count_after_1m
FROM labs.test_unlogged;

INSERT INTO labs.test_unlogged(a, b)
SELECT gs, gs
FROM generate_series(1, 5000000) AS gs;

SELECT count(*) AS unlogged_table_count_after_6m
FROM labs.test_unlogged;


SELECT 
    pg_size_pretty(pg_relation_size('labs.test_simple')) AS test_simple_size,
    pg_size_pretty(pg_relation_size('labs.test_unlogged')) AS test_unlogged_size;
