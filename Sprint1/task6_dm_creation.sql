-- ============================================
-- TASK 6: BL_DM LAYER — DDL SCRIPTS
-- Author: Yusuf Ziya Köse
-- Date: 2026-07-30
-- ============================================

-- ============================================
-- DDL: CREATE SCHEMA
-- ============================================

CREATE SCHEMA IF NOT EXISTS bl_dm;

-- ============================================
-- DDL: CREATE DIMENSION TABLES
-- ============================================

-- DIM_CUSTOMERS_SCD (SCD Type 2)
CREATE TABLE IF NOT EXISTS bl_dm.dim_customers_scd (
    customer_surr_id BIGINT PRIMARY KEY,
    customer_src_id  VARCHAR,
    customer_name    VARCHAR,
    customer_segment VARCHAR,
    source_system    VARCHAR,
    source_entity    VARCHAR,
    start_dt         DATE,
    end_dt           DATE,
    is_active        VARCHAR(1),
    insert_dt        DATE
);

-- DIM_LOCATIONS (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_dm.dim_locations (
    location_surr_id BIGINT PRIMARY KEY,
    location_src_id  VARCHAR,
    country          VARCHAR,
    city             VARCHAR,
    state            VARCHAR,
    postal_code      VARCHAR,
    region           VARCHAR,
    source_system    VARCHAR,
    source_entity    VARCHAR,
    insert_dt        DATE,
    update_dt        DATE
);

-- DIM_PRODUCTS (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_dm.dim_products (
    product_surr_id BIGINT PRIMARY KEY,
    product_src_id  VARCHAR,
    product_name    VARCHAR,
    category        VARCHAR,
    sub_category    VARCHAR,
    source_system   VARCHAR,
    source_entity   VARCHAR,
    insert_dt       DATE,
    update_dt       DATE
);

-- DIM_EMPLOYEES (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_dm.dim_employees (
    employee_surr_id BIGINT PRIMARY KEY,
    employee_src_id  VARCHAR,
    employee_name    VARCHAR,
    source_system    VARCHAR,
    source_entity    VARCHAR,
    insert_dt        DATE,
    update_dt        DATE
);

-- DIM_PAYMENTS (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_dm.dim_payments (
    payment_surr_id BIGINT PRIMARY KEY,
    payment_src_id  VARCHAR,
    payment_type    VARCHAR,
    source_system   VARCHAR,
    source_entity   VARCHAR,
    insert_dt       DATE,
    update_dt       DATE
);

-- DIM_SHIP_MODES (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_dm.dim_ship_modes (
    ship_mode_surr_id BIGINT PRIMARY KEY,
    ship_mode_src_id  VARCHAR,
    ship_mode         VARCHAR,
    source_system     VARCHAR,
    source_entity     VARCHAR,
    insert_dt         DATE,
    update_dt         DATE
);

-- DIM_RETURNED (SCD Type 1)
CREATE TABLE IF NOT EXISTS bl_dm.dim_returned (
    returned_surr_id BIGINT PRIMARY KEY,
    returned_src_id  VARCHAR,
    returned         VARCHAR,
    source_system    VARCHAR,
    source_entity    VARCHAR,
    insert_dt        DATE,
    update_dt        DATE
);

-- DIM_TIME_DAY
CREATE TABLE IF NOT EXISTS bl_dm.dim_time_day (
    date_surr_id BIGINT PRIMARY KEY,
    date         DATE,
    day_of_week  INT,
    day_name     VARCHAR,
    month        INT,
    month_name   VARCHAR,
    quarter      INT,
    year         INT,
    is_weekend   INT
);

-- FCT_SALES_DD (Fact Table)
CREATE TABLE IF NOT EXISTS bl_dm.fct_sales_dd (
    customer_surr_id   BIGINT,
    location_surr_id   BIGINT,
    product_surr_id    BIGINT,
    employee_surr_id   BIGINT,
    order_date_surr_id BIGINT,
    ship_date_surr_id  BIGINT,
    payment_surr_id    BIGINT,
    ship_mode_surr_id  BIGINT,
    returned_surr_id   BIGINT,
    order_id           VARCHAR,
    payment_id         VARCHAR,
    sales              DECIMAL,
    quantity           INT,
    discount           DECIMAL,
    profit             DECIMAL,
    profit_ratio       DECIMAL,
    insert_dt          DATE,
    update_dt          DATE
);

-- ============================================
-- DML: DEFAULT ROWS FOR DIMENSION TABLES
-- ============================================

INSERT INTO bl_dm.dim_customers_scd
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '9999-12-31', 'Y', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_customers_scd WHERE customer_surr_id = -1);

INSERT INTO bl_dm.dim_locations
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_locations WHERE location_surr_id = -1);

INSERT INTO bl_dm.dim_products
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_products WHERE product_surr_id = -1);

INSERT INTO bl_dm.dim_employees
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_employees WHERE employee_surr_id = -1);

INSERT INTO bl_dm.dim_payments
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_payments WHERE payment_surr_id = -1);

INSERT INTO bl_dm.dim_ship_modes
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_ship_modes WHERE ship_mode_surr_id = -1);

INSERT INTO bl_dm.dim_returned
SELECT -1, 'N/A', 'N/A', 'N/A', 'N/A', '1900-01-01', '1900-01-01'
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_returned WHERE returned_surr_id = -1);

INSERT INTO bl_dm.dim_time_day
SELECT -1, '1900-01-01', 0, 'N/A', 0, 'N/A', 0, 0, 0
WHERE NOT EXISTS (SELECT 1 FROM bl_dm.dim_time_day WHERE date_surr_id = -1);

COMMIT;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

SELECT 'dim_customers_scd' AS table_name, COUNT(*) FROM bl_dm.dim_customers_scd
UNION ALL
SELECT 'dim_locations', COUNT(*) FROM bl_dm.dim_locations
UNION ALL
SELECT 'dim_products', COUNT(*) FROM bl_dm.dim_products
UNION ALL
SELECT 'dim_employees', COUNT(*) FROM bl_dm.dim_employees
UNION ALL
SELECT 'dim_payments', COUNT(*) FROM bl_dm.dim_payments
UNION ALL
SELECT 'dim_ship_modes', COUNT(*) FROM bl_dm.dim_ship_modes
UNION ALL
SELECT 'dim_returned', COUNT(*) FROM bl_dm.dim_returned
UNION ALL
SELECT 'dim_time_day', COUNT(*) FROM bl_dm.dim_time_day
UNION ALL
SELECT 'fct_sales_dd', COUNT(*) FROM bl_dm.fct_sales_dd;
