-- 00_prerequisite_setup.sql
-- PostgreSQL Relational Structures Lab
-- Prerequisite setup for Task 1
-- Database used: dwh
-- Schema used: labs

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
