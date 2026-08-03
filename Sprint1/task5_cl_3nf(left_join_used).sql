-- ============================================
-- TASK 5: BL_3NF LAYER — DDL & DML SCRIPTS
-- Author: Yusuf Ziya Köse
-- Description:
-- This script creates and loads BL_3NF layer tables.
-- Mentor feedback applied: duplicate checks are handled with LEFT JOIN anti-join logic.
-- ============================================


-- ============================================
-- DDL: CREATE SCHEMA
-- ============================================

CREATE SCHEMA IF NOT EXISTS bl_3nf;


-- ============================================
-- DDL: CREATE 3NF TABLES
-- ============================================

-- CE_CUSTOMERS_SCD (SCD Type 2)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_customers_scd (
    customer_id       BIGINT PRIMARY KEY,
    customer_src_id   VARCHAR,
    customer_name     VARCHAR,
    customer_segment  VARCHAR,
    source_system     VARCHAR,
    source_entity     VARCHAR,
    source_id         VARCHAR,
    start_dt          DATE,
    end_dt            DATE,
    is_active         VARCHAR(1),
    insert_dt         DATE
);

-- CE_LOCATIONS (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_locations (
    location_id      BIGINT PRIMARY KEY,
    location_src_id  VARCHAR,
    country          VARCHAR,
    city             VARCHAR,
    state            VARCHAR,
    postal_code      VARCHAR,
    region           VARCHAR,
    source_system    VARCHAR,
    source_entity    VARCHAR,
    source_id        VARCHAR,
    insert_dt        DATE,
    update_dt        DATE
);

-- CE_PRODUCTS (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_products (
    product_id      BIGINT PRIMARY KEY,
    product_src_id  VARCHAR,
    product_name    VARCHAR,
    category        VARCHAR,
    sub_category    VARCHAR,
    source_system   VARCHAR,
    source_entity   VARCHAR,
    source_id       VARCHAR,
    insert_dt       DATE,
    update_dt       DATE
);

-- CE_EMPLOYEES (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_employees (
    employee_id      BIGINT PRIMARY KEY,
    employee_src_id  VARCHAR,
    employee_name    VARCHAR,
    source_system    VARCHAR,
    source_entity    VARCHAR,
    source_id        VARCHAR,
    insert_dt        DATE,
    update_dt        DATE
);

-- CE_PAYMENTS (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_payments (
    payment_id      BIGINT PRIMARY KEY,
    payment_src_id  VARCHAR,
    payment_type    VARCHAR,
    source_system   VARCHAR,
    source_entity   VARCHAR,
    source_id       VARCHAR,
    insert_dt       DATE,
    update_dt       DATE
);

-- CE_SHIP_MODES (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_ship_modes (
    ship_mode_id      BIGINT PRIMARY KEY,
    ship_mode_src_id  VARCHAR,
    ship_mode         VARCHAR,
    source_system     VARCHAR,
    source_entity     VARCHAR,
    source_id         VARCHAR,
    insert_dt         DATE,
    update_dt         DATE
);

-- CE_RETURNED (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_returned (
    returned_id      BIGINT PRIMARY KEY,
    returned_src_id  VARCHAR,
    returned         VARCHAR,
    source_system    VARCHAR,
    source_entity    VARCHAR,
    source_id        VARCHAR,
    insert_dt        DATE,
    update_dt        DATE
);


-- ============================================
-- OPTIONAL DDL FIX:
-- If older version of tables already exists without SOURCE_ID,
-- this makes the script safer.
-- ============================================

ALTER TABLE bl_3nf.ce_customers_scd ADD COLUMN IF NOT EXISTS source_id VARCHAR;
ALTER TABLE bl_3nf.ce_locations     ADD COLUMN IF NOT EXISTS source_id VARCHAR;
ALTER TABLE bl_3nf.ce_products      ADD COLUMN IF NOT EXISTS source_id VARCHAR;
ALTER TABLE bl_3nf.ce_employees     ADD COLUMN IF NOT EXISTS source_id VARCHAR;
ALTER TABLE bl_3nf.ce_payments      ADD COLUMN IF NOT EXISTS source_id VARCHAR;
ALTER TABLE bl_3nf.ce_ship_modes    ADD COLUMN IF NOT EXISTS source_id VARCHAR;
ALTER TABLE bl_3nf.ce_returned      ADD COLUMN IF NOT EXISTS source_id VARCHAR;


-- ============================================
-- DML: DEFAULT ROWS
-- ============================================

BEGIN;

INSERT INTO bl_3nf.ce_customers_scd (
    customer_id,
    customer_src_id,
    customer_name,
    customer_segment,
    source_system,
    source_entity,
    source_id,
    start_dt,
    end_dt,
    is_active,
    insert_dt
)
SELECT
    -1,
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    '1900-01-01'::DATE,
    '9999-12-31'::DATE,
    'Y',
    '1900-01-01'::DATE
WHERE NOT EXISTS (
    SELECT 1
    FROM bl_3nf.ce_customers_scd
    WHERE customer_id = -1
);

INSERT INTO bl_3nf.ce_locations (
    location_id,
    location_src_id,
    country,
    city,
    state,
    postal_code,
    region,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    -1,
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    '1900-01-01'::DATE,
    '1900-01-01'::DATE
WHERE NOT EXISTS (
    SELECT 1
    FROM bl_3nf.ce_locations
    WHERE location_id = -1
);

INSERT INTO bl_3nf.ce_products (
    product_id,
    product_src_id,
    product_name,
    category,
    sub_category,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    -1,
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    '1900-01-01'::DATE,
    '1900-01-01'::DATE
WHERE NOT EXISTS (
    SELECT 1
    FROM bl_3nf.ce_products
    WHERE product_id = -1
);

INSERT INTO bl_3nf.ce_employees (
    employee_id,
    employee_src_id,
    employee_name,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    -1,
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    '1900-01-01'::DATE,
    '1900-01-01'::DATE
WHERE NOT EXISTS (
    SELECT 1
    FROM bl_3nf.ce_employees
    WHERE employee_id = -1
);

INSERT INTO bl_3nf.ce_payments (
    payment_id,
    payment_src_id,
    payment_type,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    -1,
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    '1900-01-01'::DATE,
    '1900-01-01'::DATE
WHERE NOT EXISTS (
    SELECT 1
    FROM bl_3nf.ce_payments
    WHERE payment_id = -1
);

INSERT INTO bl_3nf.ce_ship_modes (
    ship_mode_id,
    ship_mode_src_id,
    ship_mode,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    -1,
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    '1900-01-01'::DATE,
    '1900-01-01'::DATE
WHERE NOT EXISTS (
    SELECT 1
    FROM bl_3nf.ce_ship_modes
    WHERE ship_mode_id = -1
);

INSERT INTO bl_3nf.ce_returned (
    returned_id,
    returned_src_id,
    returned,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    -1,
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    'N/A',
    '1900-01-01'::DATE,
    '1900-01-01'::DATE
WHERE NOT EXISTS (
    SELECT 1
    FROM bl_3nf.ce_returned
    WHERE returned_id = -1
);

COMMIT;


-- ============================================
-- DML: LOAD CE_SHIP_MODES
-- LEFT JOIN anti-join is used instead of NOT IN.
-- ============================================

BEGIN;

WITH source_data AS (
    SELECT DISTINCT
        COALESCE(ship_mode, 'N/A') AS ship_mode_src_id,
        COALESCE(ship_mode, 'N/A') AS ship_mode
    FROM sa_cash_sales.src_cash_sales

    UNION

    SELECT DISTINCT
        COALESCE(ship_mode, 'N/A') AS ship_mode_src_id,
        COALESCE(ship_mode, 'N/A') AS ship_mode
    FROM sa_card_sales.src_card_sales
),
new_rows AS (
    SELECT s.*
    FROM source_data s
    LEFT JOIN bl_3nf.ce_ship_modes t
        ON s.ship_mode_src_id = t.ship_mode_src_id
    WHERE t.ship_mode_id IS NULL
),
max_id AS (
    SELECT COALESCE(MAX(ship_mode_id), 0) AS max_ship_mode_id
    FROM bl_3nf.ce_ship_modes
    WHERE ship_mode_id <> -1
)
INSERT INTO bl_3nf.ce_ship_modes (
    ship_mode_id,
    ship_mode_src_id,
    ship_mode,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    m.max_ship_mode_id + ROW_NUMBER() OVER (ORDER BY n.ship_mode_src_id) AS ship_mode_id,
    n.ship_mode_src_id,
    n.ship_mode,
    'SA_CASH_SALES/SA_CARD_SALES' AS source_system,
    'SRC_CASH_SALES/SRC_CARD_SALES' AS source_entity,
    n.ship_mode_src_id AS source_id,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM new_rows n
CROSS JOIN max_id m;

COMMIT;


-- ============================================
-- DML: LOAD CE_RETURNED
-- ============================================

BEGIN;

WITH source_data AS (
    SELECT DISTINCT
        COALESCE(returned, 'N/A') AS returned_src_id,
        COALESCE(returned, 'N/A') AS returned
    FROM sa_card_sales.src_card_sales
),
new_rows AS (
    SELECT s.*
    FROM source_data s
    LEFT JOIN bl_3nf.ce_returned t
        ON s.returned_src_id = t.returned_src_id
    WHERE t.returned_id IS NULL
),
max_id AS (
    SELECT COALESCE(MAX(returned_id), 0) AS max_returned_id
    FROM bl_3nf.ce_returned
    WHERE returned_id <> -1
)
INSERT INTO bl_3nf.ce_returned (
    returned_id,
    returned_src_id,
    returned,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    m.max_returned_id + ROW_NUMBER() OVER (ORDER BY n.returned_src_id) AS returned_id,
    n.returned_src_id,
    n.returned,
    'SA_CARD_SALES' AS source_system,
    'SRC_CARD_SALES' AS source_entity,
    n.returned_src_id AS source_id,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM new_rows n
CROSS JOIN max_id m;

COMMIT;


-- ============================================
-- DML: LOAD CE_PAYMENTS
-- ============================================

BEGIN;

WITH source_data AS (
    SELECT DISTINCT
        COALESCE(payment_type, 'N/A') AS payment_src_id,
        COALESCE(payment_type, 'N/A') AS payment_type
    FROM sa_cash_sales.src_cash_sales

    UNION

    SELECT DISTINCT
        COALESCE(payment_type, 'N/A') AS payment_src_id,
        COALESCE(payment_type, 'N/A') AS payment_type
    FROM sa_card_sales.src_card_sales
),
new_rows AS (
    SELECT s.*
    FROM source_data s
    LEFT JOIN bl_3nf.ce_payments t
        ON s.payment_src_id = t.payment_src_id
    WHERE t.payment_id IS NULL
),
max_id AS (
    SELECT COALESCE(MAX(payment_id), 0) AS max_payment_id
    FROM bl_3nf.ce_payments
    WHERE payment_id <> -1
)
INSERT INTO bl_3nf.ce_payments (
    payment_id,
    payment_src_id,
    payment_type,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    m.max_payment_id + ROW_NUMBER() OVER (ORDER BY n.payment_src_id) AS payment_id,
    n.payment_src_id,
    n.payment_type,
    'SA_CASH_SALES/SA_CARD_SALES' AS source_system,
    'SRC_CASH_SALES/SRC_CARD_SALES' AS source_entity,
    n.payment_src_id AS source_id,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM new_rows n
CROSS JOIN max_id m;

COMMIT;


-- ============================================
-- DML: LOAD CE_LOCATIONS
-- ============================================

BEGIN;

WITH source_data AS (
    SELECT DISTINCT
        CONCAT_WS('|',
            COALESCE(country, 'N/A'),
            COALESCE(city, 'N/A'),
            COALESCE(state, 'N/A'),
            COALESCE(postal_code, 'N/A'),
            COALESCE(region, 'N/A')
        ) AS location_src_id,
        COALESCE(country, 'N/A') AS country,
        COALESCE(city, 'N/A') AS city,
        COALESCE(state, 'N/A') AS state,
        COALESCE(postal_code, 'N/A') AS postal_code,
        COALESCE(region, 'N/A') AS region
    FROM sa_cash_sales.src_cash_sales

    UNION

    SELECT DISTINCT
        CONCAT_WS('|',
            COALESCE(country, 'N/A'),
            COALESCE(city, 'N/A'),
            COALESCE(state, 'N/A'),
            COALESCE(postal_code, 'N/A'),
            COALESCE(region, 'N/A')
        ) AS location_src_id,
        COALESCE(country, 'N/A') AS country,
        COALESCE(city, 'N/A') AS city,
        COALESCE(state, 'N/A') AS state,
        COALESCE(postal_code, 'N/A') AS postal_code,
        COALESCE(region, 'N/A') AS region
    FROM sa_card_sales.src_card_sales
),
new_rows AS (
    SELECT s.*
    FROM source_data s
    LEFT JOIN bl_3nf.ce_locations t
        ON s.location_src_id = t.location_src_id
    WHERE t.location_id IS NULL
),
max_id AS (
    SELECT COALESCE(MAX(location_id), 0) AS max_location_id
    FROM bl_3nf.ce_locations
    WHERE location_id <> -1
)
INSERT INTO bl_3nf.ce_locations (
    location_id,
    location_src_id,
    country,
    city,
    state,
    postal_code,
    region,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    m.max_location_id + ROW_NUMBER() OVER (ORDER BY n.location_src_id) AS location_id,
    n.location_src_id,
    n.country,
    n.city,
    n.state,
    n.postal_code,
    n.region,
    'SA_CASH_SALES/SA_CARD_SALES' AS source_system,
    'SRC_CASH_SALES/SRC_CARD_SALES' AS source_entity,
    n.location_src_id AS source_id,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM new_rows n
CROSS JOIN max_id m;

COMMIT;


-- ============================================
-- DML: LOAD CE_EMPLOYEES
-- ============================================

BEGIN;

WITH source_data AS (
    SELECT
        COALESCE(employee_id, 'N/A') AS employee_src_id,
        COALESCE(MAX(employee_name), 'N/A') AS employee_name
    FROM (
        SELECT employee_id, employee_name
        FROM sa_cash_sales.src_cash_sales

        UNION ALL

        SELECT employee_id, employee_name
        FROM sa_card_sales.src_card_sales
    ) src
    GROUP BY COALESCE(employee_id, 'N/A')
),
new_rows AS (
    SELECT s.*
    FROM source_data s
    LEFT JOIN bl_3nf.ce_employees t
        ON s.employee_src_id = t.employee_src_id
    WHERE t.employee_id IS NULL
),
max_id AS (
    SELECT COALESCE(MAX(employee_id), 0) AS max_employee_id
    FROM bl_3nf.ce_employees
    WHERE employee_id <> -1
)
INSERT INTO bl_3nf.ce_employees (
    employee_id,
    employee_src_id,
    employee_name,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    m.max_employee_id + ROW_NUMBER() OVER (ORDER BY n.employee_src_id) AS employee_id,
    n.employee_src_id,
    n.employee_name,
    'SA_CASH_SALES/SA_CARD_SALES' AS source_system,
    'SRC_CASH_SALES/SRC_CARD_SALES' AS source_entity,
    n.employee_src_id AS source_id,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM new_rows n
CROSS JOIN max_id m;

COMMIT;


-- ============================================
-- DML: LOAD CE_PRODUCTS
-- ============================================

BEGIN;

WITH source_data AS (
    SELECT
        COALESCE(product_id, 'N/A') AS product_src_id,
        COALESCE(MAX(product_name), 'N/A') AS product_name,
        COALESCE(MAX(category), 'N/A') AS category,
        COALESCE(MAX(sub_category), 'N/A') AS sub_category
    FROM (
        SELECT product_id, product_name, category, sub_category
        FROM sa_cash_sales.src_cash_sales

        UNION ALL

        SELECT product_id, product_name, category, sub_category
        FROM sa_card_sales.src_card_sales
    ) src
    GROUP BY COALESCE(product_id, 'N/A')
),
new_rows AS (
    SELECT s.*
    FROM source_data s
    LEFT JOIN bl_3nf.ce_products t
        ON s.product_src_id = t.product_src_id
    WHERE t.product_id IS NULL
),
max_id AS (
    SELECT COALESCE(MAX(product_id), 0) AS max_product_id
    FROM bl_3nf.ce_products
    WHERE product_id <> -1
)
INSERT INTO bl_3nf.ce_products (
    product_id,
    product_src_id,
    product_name,
    category,
    sub_category,
    source_system,
    source_entity,
    source_id,
    insert_dt,
    update_dt
)
SELECT
    m.max_product_id + ROW_NUMBER() OVER (ORDER BY n.product_src_id) AS product_id,
    n.product_src_id,
    n.product_name,
    n.category,
    n.sub_category,
    'SA_CASH_SALES/SA_CARD_SALES' AS source_system,
    'SRC_CASH_SALES/SRC_CARD_SALES' AS source_entity,
    n.product_src_id AS source_id,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM new_rows n
CROSS JOIN max_id m;

COMMIT;


-- ============================================
-- DML: LOAD CE_CUSTOMERS_SCD
-- SCD Type 2 logic:
-- 1. Close changed active records.
-- 2. Insert new customers or new versions.
-- ============================================

-- Step 1: Close changed active customer rows
BEGIN;

WITH source_data AS (
    SELECT
        COALESCE(customer_id, 'N/A') AS customer_src_id,
        COALESCE(MAX(customer_name), 'N/A') AS customer_name,
        COALESCE(MAX(segment), 'N/A') AS customer_segment
    FROM (
        SELECT customer_id, customer_name, segment
        FROM sa_cash_sales.src_cash_sales

        UNION ALL

        SELECT customer_id, customer_name, segment
        FROM sa_card_sales.src_card_sales
    ) src
    GROUP BY COALESCE(customer_id, 'N/A')
)
UPDATE bl_3nf.ce_customers_scd t
SET
    end_dt = CURRENT_DATE - 1,
    is_active = 'N'
FROM source_data s
WHERE t.customer_src_id = s.customer_src_id
  AND t.is_active = 'Y'
  AND t.customer_id <> -1
  AND (
        COALESCE(t.customer_name, 'N/A') <> s.customer_name
        OR COALESCE(t.customer_segment, 'N/A') <> s.customer_segment
  );

COMMIT;


-- Step 2: Insert new customers or new SCD2 versions
BEGIN;

WITH source_data AS (
    SELECT
        COALESCE(customer_id, 'N/A') AS customer_src_id,
        COALESCE(MAX(customer_name), 'N/A') AS customer_name,
        COALESCE(MAX(segment), 'N/A') AS customer_segment
    FROM (
        SELECT customer_id, customer_name, segment
        FROM sa_cash_sales.src_cash_sales

        UNION ALL

        SELECT customer_id, customer_name, segment
        FROM sa_card_sales.src_card_sales
    ) src
    GROUP BY COALESCE(customer_id, 'N/A')
),
new_rows AS (
    SELECT s.*
    FROM source_data s
    LEFT JOIN bl_3nf.ce_customers_scd t
        ON s.customer_src_id = t.customer_src_id
       AND t.is_active = 'Y'
       AND COALESCE(t.customer_name, 'N/A') = s.customer_name
       AND COALESCE(t.customer_segment, 'N/A') = s.customer_segment
    WHERE t.customer_id IS NULL
),
max_id AS (
    SELECT COALESCE(MAX(customer_id), 0) AS max_customer_id
    FROM bl_3nf.ce_customers_scd
    WHERE customer_id <> -1
)
INSERT INTO bl_3nf.ce_customers_scd (
    customer_id,
    customer_src_id,
    customer_name,
    customer_segment,
    source_system,
    source_entity,
    source_id,
    start_dt,
    end_dt,
    is_active,
    insert_dt
)
SELECT
    m.max_customer_id + ROW_NUMBER() OVER (ORDER BY n.customer_src_id) AS customer_id,
    n.customer_src_id,
    n.customer_name,
    n.customer_segment,
    'SA_CASH_SALES/SA_CARD_SALES' AS source_system,
    'SRC_CASH_SALES/SRC_CARD_SALES' AS source_entity,
    n.customer_src_id AS source_id,
    CURRENT_DATE AS start_dt,
    '9999-12-31'::DATE AS end_dt,
    'Y' AS is_active,
    CURRENT_DATE AS insert_dt
FROM new_rows n
CROSS JOIN max_id m;

COMMIT;


-- ============================================
-- VERIFICATION QUERIES
-- ============================================

SELECT 'ce_customers_scd' AS table_name, COUNT(*) AS row_count FROM bl_3nf.ce_customers_scd
UNION ALL
SELECT 'ce_locations', COUNT(*) FROM bl_3nf.ce_locations
UNION ALL
SELECT 'ce_products', COUNT(*) FROM bl_3nf.ce_products
UNION ALL
SELECT 'ce_employees', COUNT(*) FROM bl_3nf.ce_employees
UNION ALL
SELECT 'ce_payments', COUNT(*) FROM bl_3nf.ce_payments
UNION ALL
SELECT 'ce_ship_modes', COUNT(*) FROM bl_3nf.ce_ship_modes
UNION ALL
SELECT 'ce_returned', COUNT(*) FROM bl_3nf.ce_returned
ORDER BY table_name;


-- ============================================
-- OPTIONAL DUPLICATE CHECKS
-- These should return 0 rows if the load is clean.
-- ============================================

SELECT product_src_id, COUNT(*)
FROM bl_3nf.ce_products
WHERE product_id <> -1
GROUP BY product_src_id
HAVING COUNT(*) > 1;

SELECT customer_src_id, COUNT(*)
FROM bl_3nf.ce_customers_scd
WHERE customer_id <> -1
  AND is_active = 'Y'
GROUP BY customer_src_id
HAVING COUNT(*) > 1;

SELECT location_src_id, COUNT(*)
FROM bl_3nf.ce_locations
WHERE location_id <> -1
GROUP BY location_src_id
HAVING COUNT(*) > 1;