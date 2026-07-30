-- ============================================
-- TASK 4: STAGING LAYER
-- Author: Yusuf Ziya Köse
-- Date: 2026-07-30
-- ============================================

-- 1. CREATE SCHEMAS
CREATE SCHEMA sa_cash_sales;
CREATE SCHEMA sa_card_sales;

-- 2. CREATE FILE_FDW EXTENSION AND SERVER
CREATE EXTENSION file_fdw;
CREATE SERVER file_server FOREIGN DATA WRAPPER file_fdw;

-- ============================================
-- CASH SALES
-- ============================================

-- 3. CREATE EXTERNAL (FOREIGN) TABLE FOR CASH SALES
CREATE FOREIGN TABLE sa_cash_sales.ext_cash_sales (
    payment_id VARCHAR,
    order_id VARCHAR,
    order_date VARCHAR,
    ship_date VARCHAR,
    ship_mode VARCHAR,
    customer_id VARCHAR,
    customer_name VARCHAR,
    segment VARCHAR,
    country VARCHAR,
    city VARCHAR,
    state VARCHAR,
    postal_code VARCHAR,
    region VARCHAR,
    product_id VARCHAR,
    category VARCHAR,
    sub_category VARCHAR,
    product_name VARCHAR,
    sales VARCHAR,
    quantity VARCHAR,
    discount VARCHAR,
    profit VARCHAR,
    employee_name VARCHAR,
    employee_id VARCHAR,
    payment_type VARCHAR
) SERVER file_server
OPTIONS (filename '/tmp/SRC_CASH_SALES.csv', format 'csv', header 'true');

-- 4. CREATE SOURCE TABLE FOR CASH SALES
CREATE TABLE sa_cash_sales.src_cash_sales (
    payment_id VARCHAR,
    order_id VARCHAR,
    order_date DATE,
    ship_date DATE,
    ship_mode VARCHAR,
    customer_id VARCHAR,
    customer_name VARCHAR,
    segment VARCHAR,
    country VARCHAR,
    city VARCHAR,
    state VARCHAR,
    postal_code VARCHAR,
    region VARCHAR,
    product_id VARCHAR,
    category VARCHAR,
    sub_category VARCHAR,
    product_name VARCHAR,
    sales DECIMAL,
    quantity INT,
    discount DECIMAL,
    profit DECIMAL,
    employee_name VARCHAR,
    employee_id VARCHAR,
    payment_type VARCHAR
);

-- 5. LOAD DATA FROM EXT TO SRC WITH DEDUPLICATION
INSERT INTO sa_cash_sales.src_cash_sales
SELECT DISTINCT ON (payment_id)
    payment_id,
    order_id,
    order_date::DATE,
    ship_date::DATE,
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country,
    city,
    state,
    postal_code,
    region,
    product_id,
    category,
    sub_category,
    product_name,
    sales::DECIMAL,
    quantity::INT,
    discount::DECIMAL,
    profit::DECIMAL,
    employee_name,
    employee_id,
    payment_type
FROM sa_cash_sales.ext_cash_sales;

-- ============================================
-- CARD SALES
-- ============================================

-- 6. CREATE EXTERNAL (FOREIGN) TABLE FOR CARD SALES
CREATE FOREIGN TABLE sa_card_sales.ext_card_sales (
    payment_id VARCHAR,
    order_id VARCHAR,
    order_date VARCHAR,
    ship_date VARCHAR,
    ship_mode VARCHAR,
    customer_id VARCHAR,
    customer_name VARCHAR,
    segment VARCHAR,
    country VARCHAR,
    city VARCHAR,
    state VARCHAR,
    postal_code VARCHAR,
    region VARCHAR,
    product_id VARCHAR,
    category VARCHAR,
    sub_category VARCHAR,
    product_name VARCHAR,
    sales VARCHAR,
    quantity VARCHAR,
    discount VARCHAR,
    profit VARCHAR,
    returned VARCHAR,
    employee_name VARCHAR,
    employee_id VARCHAR,
    payment_type VARCHAR
) SERVER file_server
OPTIONS (filename '/tmp/SRC_CARD_SALES.csv', format 'csv', header 'true');

-- 7. CREATE SOURCE TABLE FOR CARD SALES
CREATE TABLE sa_card_sales.src_card_sales (
    payment_id VARCHAR,
    order_id VARCHAR,
    order_date DATE,
    ship_date DATE,
    ship_mode VARCHAR,
    customer_id VARCHAR,
    customer_name VARCHAR,
    segment VARCHAR,
    country VARCHAR,
    city VARCHAR,
    state VARCHAR,
    postal_code VARCHAR,
    region VARCHAR,
    product_id VARCHAR,
    category VARCHAR,
    sub_category VARCHAR,
    product_name VARCHAR,
    sales DECIMAL,
    quantity INT,
    discount DECIMAL,
    profit DECIMAL,
    returned VARCHAR,
    employee_name VARCHAR,
    employee_id VARCHAR,
    payment_type VARCHAR
);

-- 8. LOAD DATA FROM EXT TO SRC WITH DEDUPLICATION
INSERT INTO sa_card_sales.src_card_sales
SELECT DISTINCT ON (payment_id)
    payment_id,
    order_id,
    order_date::DATE,
    ship_date::DATE,
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country,
    city,
    state,
    postal_code,
    region,
    product_id,
    category,
    sub_category,
    product_name,
    sales::DECIMAL,
    quantity::INT,
    discount::DECIMAL,
    profit::DECIMAL,
    returned,
    employee_name,
    employee_id,
    payment_type
FROM sa_card_sales.ext_card_sales;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Check ext tables
SELECT * FROM sa_cash_sales.ext_cash_sales LIMIT 5;
SELECT * FROM sa_card_sales.ext_card_sales LIMIT 5;

-- Check src tables
SELECT * FROM sa_cash_sales.src_cash_sales LIMIT 5;
SELECT * FROM sa_card_sales.src_card_sales LIMIT 5;

-- Count rows
SELECT COUNT(*) FROM sa_cash_sales.src_cash_sales;
SELECT COUNT(*) FROM sa_card_sales.src_card_sales;
