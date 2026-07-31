-- ============================================
-- TASK 5: BL_3NF LAYER — DDL & DML SCRIPTS
-- Author: Yusuf Ziya Köse
-- Date: 2026-07-30
-- ============================================

-- ============================================
-- DDL: CREATE SCHEMA AND TABLES
-- ============================================

CREATE SCHEMA IF NOT EXISTS bl_3nf;

-- CE_CUSTOMERS_SCD (SCD Type 2)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_customers_scd (
    customer_id     BIGINT PRIMARY KEY,
    customer_src_id VARCHAR,
    customer_name   VARCHAR,
    customer_segment VARCHAR,
    source_system   VARCHAR,
    source_entity   VARCHAR,
    start_dt        DATE,
    end_dt          DATE,
    is_active       VARCHAR(1),
    insert_dt       DATE
);

-- CE_LOCATIONS (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_locations (
    location_id     BIGINT PRIMARY KEY,
    location_src_id VARCHAR,
    country         VARCHAR,
    city            VARCHAR,
    state           VARCHAR,
    postal_code     VARCHAR,
    region          VARCHAR,
    source_system   VARCHAR,
    source_entity   VARCHAR,
    insert_dt       DATE,
    update_dt       DATE
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
    insert_dt       DATE,
    update_dt       DATE
);

-- CE_EMPLOYEES (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_employees (
    employee_id     BIGINT PRIMARY KEY,
    employee_src_id VARCHAR,
    employee_name   VARCHAR,
    source_system   VARCHAR,
    source_entity   VARCHAR,
    insert_dt       DATE,
    update_dt       DATE
);

-- CE_PAYMENTS (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_payments (
    payment_id      BIGINT PRIMARY KEY,
    payment_src_id  VARCHAR,
    payment_type    VARCHAR,
    source_system   VARCHAR,
    source_entity   VARCHAR,
    insert_dt       DATE,
    update_dt       DATE
);

-- CE_SHIP_MODES (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_ship_modes (
    ship_mode_id     BIGINT PRIMARY KEY,
    ship_mode_src_id VARCHAR,
    ship_mode        VARCHAR,
    source_system    VARCHAR,
    source_entity    VARCHAR,
    insert_dt        DATE,
    update_dt        DATE
);

-- CE_RETURNED (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_3nf.ce_returned (
    returned_id     BIGINT PRIMARY KEY,
    returned_src_id VARCHAR,
    returned        VARCHAR,
    source_system   VARCHAR,
    source_entity   VARCHAR,
    insert_dt       DATE,
    update_dt       DATE
);

-- ============================================
-- DML: DEFAULT ROWS
-- ============================================

INSERT INTO bl_3nf.ce_customers_scd
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '9999-12-31', 'Y', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_customers_scd WHERE customer_id = -1);

INSERT INTO bl_3nf.ce_locations
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_locations WHERE location_id = -1);

INSERT INTO bl_3nf.ce_products
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_products WHERE product_id = -1);

INSERT INTO bl_3nf.ce_employees
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_employees WHERE employee_id = -1);

INSERT INTO bl_3nf.ce_payments
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_payments WHERE payment_id = -1);

INSERT INTO bl_3nf.ce_ship_modes
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_ship_modes WHERE ship_mode_id = -1);

INSERT INTO bl_3nf.ce_returned
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_3nf.ce_returned WHERE returned_id = -1);

COMMIT;

-- ============================================
-- DML: LOAD DATA FROM SRC TO CE_ TABLES
-- ============================================

-- CE_SHIP_MODES
INSERT INTO bl_3nf.ce_ship_modes (
    ship_mode_id, ship_mode_src_id, ship_mode,
    source_system, source_entity, insert_dt, update_dt
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY ship_mode) AS ship_mode_id,
    ship_mode AS ship_mode_src_id,
    COALESCE(ship_mode, 'N/A') AS ship_mode,
    'SA_CASH_SALES' AS source_system,
    'SRC_CASH_SALES' AS source_entity,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM (
    SELECT DISTINCT ship_mode FROM sa_cash_sales.src_cash_sales
    UNION
    SELECT DISTINCT ship_mode FROM sa_card_sales.src_card_sales
) combined
WHERE ship_mode NOT IN (
    SELECT ship_mode_src_id FROM bl_3nf.ce_ship_modes WHERE ship_mode_id != -1
);

COMMIT;

-- CE_RETURNED
INSERT INTO bl_3nf.ce_returned (
    returned_id, returned_src_id, returned,
    source_system, source_entity, insert_dt, update_dt
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY returned) AS returned_id,
    returned AS returned_src_id,
    COALESCE(returned, 'N/A') AS returned,
    'SA_CARD_SALES' AS source_system,
    'SRC_CARD_SALES' AS source_entity,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM (
    SELECT DISTINCT returned FROM sa_card_sales.src_card_sales
) combined
WHERE returned NOT IN (
    SELECT returned_src_id FROM bl_3nf.ce_returned WHERE returned_id != -1
);

COMMIT;

-- CE_PAYMENTS
INSERT INTO bl_3nf.ce_payments (
    payment_id, payment_src_id, payment_type,
    source_system, source_entity, insert_dt, update_dt
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY payment_type) AS payment_id,
    payment_type AS payment_src_id,
    COALESCE(payment_type, 'N/A') AS payment_type,
    'SA_CASH_SALES' AS source_system,
    'SRC_CASH_SALES' AS source_entity,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM (
    SELECT DISTINCT payment_type FROM sa_cash_sales.src_cash_sales
    UNION
    SELECT DISTINCT payment_type FROM sa_card_sales.src_card_sales
) combined
WHERE payment_type NOT IN (
    SELECT payment_src_id FROM bl_3nf.ce_payments WHERE payment_id != -1
);

COMMIT;

-- CE_LOCATIONS
INSERT INTO bl_3nf.ce_locations (
    location_id, location_src_id, country, city, state,
    postal_code, region, source_system, source_entity, insert_dt, update_dt
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY country, city, state) AS location_id,
    CONCAT(country, '_', city, '_', state) AS location_src_id,
    COALESCE(country, 'N/A') AS country,
    COALESCE(city, 'N/A') AS city,
    COALESCE(state, 'N/A') AS state,
    COALESCE(postal_code, 'N/A') AS postal_code,
    COALESCE(region, 'N/A') AS region,
    'SA_CASH_SALES' AS source_system,
    'SRC_CASH_SALES' AS source_entity,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM (
    SELECT DISTINCT country, city, state, postal_code, region 
    FROM sa_cash_sales.src_cash_sales
    UNION
    SELECT DISTINCT country, city, state, postal_code, region 
    FROM sa_card_sales.src_card_sales
) combined
WHERE CONCAT(country, '_', city, '_', state) NOT IN (
    SELECT location_src_id FROM bl_3nf.ce_locations WHERE location_id != -1
);

COMMIT;

-- CE_EMPLOYEES
INSERT INTO bl_3nf.ce_employees (
    employee_id, employee_src_id, employee_name,
    source_system, source_entity, insert_dt, update_dt
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY employee_id) AS employee_id,
    employee_id AS employee_src_id,
    COALESCE(employee_name, 'N/A') AS employee_name,
    'SA_CASH_SALES' AS source_system,
    'SRC_CASH_SALES' AS source_entity,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM (
    SELECT DISTINCT employee_id, employee_name 
    FROM sa_cash_sales.src_cash_sales
    UNION
    SELECT DISTINCT employee_id, employee_name 
    FROM sa_card_sales.src_card_sales
) combined
WHERE employee_id NOT IN (
    SELECT employee_src_id FROM bl_3nf.ce_employees WHERE employee_id != -1
);

COMMIT;

-- CE_PRODUCTS
INSERT INTO bl_3nf.ce_products (
    product_id, product_src_id, product_name,
    category, sub_category, source_system, source_entity, insert_dt, update_dt
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY product_id) AS product_id,
    product_id AS product_src_id,
    COALESCE(product_name, 'N/A') AS product_name,
    COALESCE(category, 'N/A') AS category,
    COALESCE(sub_category, 'N/A') AS sub_category,
    'SA_CASH_SALES' AS source_system,
    'SRC_CASH_SALES' AS source_entity,
    CURRENT_DATE AS insert_dt,
    CURRENT_DATE AS update_dt
FROM (
    SELECT DISTINCT product_id, product_name, category, sub_category 
    FROM sa_cash_sales.src_cash_sales
    UNION
    SELECT DISTINCT product_id, product_name, category, sub_category 
    FROM sa_card_sales.src_card_sales
) combined
WHERE product_id NOT IN (
    SELECT product_src_id FROM bl_3nf.ce_products WHERE product_id != -1
);

COMMIT;

-- CE_CUSTOMERS_SCD (SCD Type 2)
INSERT INTO bl_3nf.ce_customers_scd (
    customer_id, customer_src_id, customer_name, customer_segment,
    source_system, source_entity, start_dt, end_dt, is_active, insert_dt
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY customer_id) AS customer_id,
    customer_id AS customer_src_id,
    COALESCE(customer_name, 'N/A') AS customer_name,
    COALESCE(segment, 'N/A') AS customer_segment,
    'SA_CASH_SALES' AS source_system,
    'SRC_CASH_SALES' AS source_entity,
    CURRENT_DATE AS start_dt,
    '9999-12-31'::DATE AS end_dt,
    'Y' AS is_active,
    CURRENT_DATE AS insert_dt
FROM (
    SELECT DISTINCT customer_id, customer_name, segment 
    FROM sa_cash_sales.src_cash_sales
    UNION
    SELECT DISTINCT customer_id, customer_name, segment 
    FROM sa_card_sales.src_card_sales
) combined
WHERE customer_id NOT IN (
    SELECT customer_src_id FROM bl_3nf.ce_customers_scd WHERE customer_id != -1
);

COMMIT;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

SELECT 'ce_customers_scd' AS table_name, COUNT(*) FROM bl_3nf.ce_customers_scd
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
SELECT 'ce_returned', COUNT(*) FROM bl_3nf.ce_returned;
