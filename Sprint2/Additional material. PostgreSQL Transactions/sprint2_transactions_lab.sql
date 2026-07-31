-- ============================================================================
-- EPAM Systems - Data Analytics Engineering Internship
-- Sprint 2: PostgreSQL Transactions & Isolation Levels Lab Scripts
-- Author: Yusuf Ziya Köse
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: Sandbox Table Creation
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.employee (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    status VARCHAR(100)
);

-- ----------------------------------------------------------------------------
-- TASK 2: First & Second & Third Transactions (Read Committed - Default)
-- ----------------------------------------------------------------------------

-- --- SESSION A (Left Terminal) ---
BEGIN;
SELECT txid_current(); -- Note down the XID (e.g., 847)
INSERT INTO public.employee ("name", status) VALUES ('Alice', 'Not fired');
SELECT id, name, status, xmin, xmax FROM public.employee; -- Alice is visible here with xmin = 847
-- Keep transaction open!

-- --- SESSION B (Right Terminal) ---
BEGIN;
SELECT id, name, status, xmin, xmax FROM public.employee; -- Alice is NOT visible (Dirty Read prevented)
COMMIT;

-- --- SESSION A (Left Terminal) ---
COMMIT; -- Alice is now committed.

-- --- SESSION B (Right Terminal) ---
SELECT id, name, status, xmin, xmax FROM public.employee; -- Alice is now visible with xmin = 847


-- ----------------------------------------------------------------------------
-- TASK 5: Repeatable Read & Command Identifiers (cmin / cmax)
-- ----------------------------------------------------------------------------
-- Reset Table
TRUNCATE TABLE public.employee;
INSERT INTO public.employee ("name", status) VALUES ('Alice', 'Not fired');

-- --- SESSION A (Left Terminal) ---
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT id, name, status, xmin, xmax, cmin, cmax FROM public.employee; -- Alice visible (xmin=852, xmax=0, cmin=0, cmax=0)

-- --- SESSION B (Right Terminal) ---
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
DELETE FROM public.employee WHERE name = 'Alice';
COMMIT; -- Alice is deleted and committed in Session B (XID = 853)

-- --- SESSION A (Left Terminal) ---
-- Alice is still visible because of REPEATABLE READ snapshot isolation!
SELECT id, name, status, xmin, xmax, cmin, cmax FROM public.employee; -- xmax shows 853, but Alice is still in our snapshot.

-- Demonstrating internal command counters (cmin/cmax incrementation)
INSERT INTO public.employee ("name", status) VALUES ('Bob', 'Not fired'); -- This first insert gets cmin = 0
SELECT id, name, status, xmin, xmax, cmin, cmax FROM public.employee WHERE name = 'Bob';

INSERT INTO public.employee ("name", status) VALUES ('Charlie', 'Not fired'); -- This second insert gets cmin = 1
SELECT id, name, status, xmin, xmax, cmin, cmax FROM public.employee WHERE name = 'Charlie';
COMMIT;


-- ----------------------------------------------------------------------------
-- TASK 6: Serialization Anomaly (Write Skew) Test
-- ----------------------------------------------------------------------------
-- Reset Table
TRUNCATE TABLE public.employee;
INSERT INTO public.employee (id, "name", status) VALUES (1, 'Alice', 'Not fired');
INSERT INTO public.employee (id, "name", status) VALUES (2, 'Bob', 'Not fired');

-- --- SESSION A (Left Terminal) ---
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) FROM public.employee WHERE status = 'Not fired'; -- Sees 2
UPDATE public.employee SET status = 'Fired' WHERE name = 'Alice';

-- --- SESSION B (Right Terminal) ---
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) FROM public.employee WHERE status = 'Not fired'; -- Sees 2
UPDATE public.employee SET status = 'Fired' WHERE name = 'Bob';
COMMIT; -- Session B commits successfully first.

-- --- SESSION A (Left Terminal) ---
COMMIT; -- Throws ERROR: could not serialize access due to read/write dependencies


-- ----------------------------------------------------------------------------
-- TASK 7: Lost Update & Row-Level Locking Test
-- ----------------------------------------------------------------------------
-- Reset Table
TRUNCATE TABLE public.employee;
INSERT INTO public.employee (id, "name", status) VALUES (2, 'Alice', 'Not fired');

-- --- SESSION A (Left Terminal) ---
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
UPDATE public.employee SET status = 'Fired' WHERE id = 2; -- Obtains row-level exclusive lock on Alice

-- --- SESSION B (Right Terminal) ---
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
UPDATE public.employee SET status = 'Promoted' WHERE id = 2; -- HANGS! (Waiting for Session A's lock)

-- --- SESSION A (Left Terminal) ---
COMMIT; -- Releases the lock. Session B instantly unblocks and executes!

-- --- SESSION B (Right Terminal) ---
COMMIT;