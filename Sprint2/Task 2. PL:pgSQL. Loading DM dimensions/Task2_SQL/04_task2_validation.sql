\set ON_ERROR_STOP on

/* =========================================================
   TASK 2 - DIMENSION VALIDATION QUERIES
   ========================================================= */


/* =========================================================
   1. Verify the 8 dimension loading procedures
   ========================================================= */

SELECT
    n.nspname AS schema_name,
    p.proname AS procedure_name
FROM pg_proc p
JOIN pg_namespace n
    ON n.oid = p.pronamespace
WHERE n.nspname = 'bl_cl'
  AND p.prokind = 'p'
  AND p.proname IN (
      'prc_load_dim_customers_scd',
      'prc_load_dim_employees',
      'prc_load_dim_locations',
      'prc_load_dim_payments',
      'prc_load_dim_products',
      'prc_load_dim_returned',
      'prc_load_dim_ship_modes',
      'prc_load_dim_time_day'
  )
ORDER BY p.proname;


/* =========================================================
   2. Dimension row count validation
   ========================================================= */

SELECT
    'dim_ship_modes' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE ship_mode_surr_id = -1) AS default_rows,
    COUNT(*) FILTER (WHERE ship_mode_surr_id <> -1) AS business_rows
FROM bl_dm.dim_ship_modes

UNION ALL

SELECT
    'dim_returned',
    COUNT(*),
    COUNT(*) FILTER (WHERE returned_surr_id = -1),
    COUNT(*) FILTER (WHERE returned_surr_id <> -1)
FROM bl_dm.dim_returned

UNION ALL

SELECT
    'dim_payments',
    COUNT(*),
    COUNT(*) FILTER (WHERE payment_surr_id = -1),
    COUNT(*) FILTER (WHERE payment_surr_id <> -1)
FROM bl_dm.dim_payments

UNION ALL

SELECT
    'dim_locations',
    COUNT(*),
    COUNT(*) FILTER (WHERE location_surr_id = -1),
    COUNT(*) FILTER (WHERE location_surr_id <> -1)
FROM bl_dm.dim_locations

UNION ALL

SELECT
    'dim_employees',
    COUNT(*),
    COUNT(*) FILTER (WHERE employee_surr_id = -1),
    COUNT(*) FILTER (WHERE employee_surr_id <> -1)
FROM bl_dm.dim_employees

UNION ALL

SELECT
    'dim_products',
    COUNT(*),
    COUNT(*) FILTER (WHERE product_surr_id = -1),
    COUNT(*) FILTER (WHERE product_surr_id <> -1)
FROM bl_dm.dim_products

UNION ALL

SELECT
    'dim_customers_scd',
    COUNT(*),
    COUNT(*) FILTER (WHERE customer_surr_id = -1),
    COUNT(*) FILTER (WHERE customer_surr_id <> -1)
FROM bl_dm.dim_customers_scd

UNION ALL

SELECT
    'dim_time_day',
    COUNT(*),
    COUNT(*) FILTER (WHERE date_surr_id = -1),
    COUNT(*) FILTER (WHERE date_surr_id <> -1)
FROM bl_dm.dim_time_day

ORDER BY table_name;


/* =========================================================
   3. Run all dimension procedures again for idempotency test
   ========================================================= */

CALL bl_cl.prc_load_dim_ship_modes();
CALL bl_cl.prc_load_dim_returned();
CALL bl_cl.prc_load_dim_payments();
CALL bl_cl.prc_load_dim_locations();
CALL bl_cl.prc_load_dim_employees();
CALL bl_cl.prc_load_dim_products();
CALL bl_cl.prc_load_dim_customers_scd();
CALL bl_cl.prc_load_dim_time_day();


/* =========================================================
   4. Idempotency results from centralized ETL log
   Expected:
   - 8 rows
   - SUCCESS
   - rows_affected = 0
   ========================================================= */

SELECT DISTINCT ON (procedure_name)
    log_id,
    log_datetime,
    procedure_name,
    target_table,
    rows_affected,
    status,
    message,
    error_code,
    error_message
FROM bl_cl.load_log
WHERE procedure_name IN (
    'prc_load_dim_ship_modes',
    'prc_load_dim_returned',
    'prc_load_dim_payments',
    'prc_load_dim_locations',
    'prc_load_dim_employees',
    'prc_load_dim_products',
    'prc_load_dim_customers_scd',
    'prc_load_dim_time_day'
)
ORDER BY
    procedure_name,
    log_id DESC;


/* =========================================================
   5. BL_3NF and BL_DM customer SCD reconciliation
   Expected:
   only_in_bl_3nf = 0
   only_in_bl_dm  = 0
   ========================================================= */

SELECT
    'only_in_bl_3nf' AS difference_type,
    COUNT(*) AS row_count
FROM (
    SELECT
        customer_id,
        customer_src_id,
        customer_name,
        customer_segment,
        source_system,
        source_entity,
        start_dt,
        end_dt,
        is_active,
        insert_dt
    FROM bl_3nf.ce_customers_scd

    EXCEPT

    SELECT
        customer_surr_id,
        customer_src_id,
        customer_name,
        customer_segment,
        source_system,
        source_entity,
        start_dt,
        end_dt,
        is_active,
        insert_dt
    FROM bl_dm.dim_customers_scd
) x

UNION ALL

SELECT
    'only_in_bl_dm',
    COUNT(*)
FROM (
    SELECT
        customer_surr_id,
        customer_src_id,
        customer_name,
        customer_segment,
        source_system,
        source_entity,
        start_dt,
        end_dt,
        is_active,
        insert_dt
    FROM bl_dm.dim_customers_scd

    EXCEPT

    SELECT
        customer_id,
        customer_src_id,
        customer_name,
        customer_segment,
        source_system,
        source_entity,
        start_dt,
        end_dt,
        is_active,
        insert_dt
    FROM bl_3nf.ce_customers_scd
) x;


/* =========================================================
   6. One active SCD version validation in BL_3NF
   Expected: 0 rows
   ========================================================= */

SELECT
    customer_src_id,
    COUNT(*) AS active_version_count
FROM bl_3nf.ce_customers_scd
WHERE customer_id <> -1
  AND UPPER(BTRIM(is_active)) = 'Y'
GROUP BY customer_src_id
HAVING COUNT(*) <> 1;


/* =========================================================
   7. One active SCD version validation in BL_DM
   Expected: 0 rows
   ========================================================= */

SELECT
    customer_src_id,
    COUNT(*) AS active_version_count
FROM bl_dm.dim_customers_scd
WHERE customer_surr_id <> -1
  AND UPPER(BTRIM(is_active)) = 'Y'
GROUP BY customer_src_id
HAVING COUNT(*) <> 1;
