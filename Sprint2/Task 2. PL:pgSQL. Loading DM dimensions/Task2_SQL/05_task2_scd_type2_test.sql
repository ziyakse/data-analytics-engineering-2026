\set ON_ERROR_STOP on

/* =========================================================
   TASK 2 - SCD TYPE 2 TRANSACTIONAL TEST
   Test customer: AA-10315 / Alex Avila

   Important:
   This test ends with ROLLBACK.
   Do not replace ROLLBACK with COMMIT.
   ========================================================= */


/* =========================================================
   1. Initial customer state
   ========================================================= */

SELECT
    'BL_3NF' AS layer_name,
    customer_id AS version_id,
    customer_src_id,
    customer_name,
    customer_segment,
    start_dt,
    end_dt,
    is_active
FROM bl_3nf.ce_customers_scd
WHERE customer_src_id = 'AA-10315'

UNION ALL

SELECT
    'BL_DM' AS layer_name,
    customer_surr_id AS version_id,
    customer_src_id,
    customer_name,
    customer_segment,
    start_dt,
    end_dt,
    is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = 'AA-10315'

ORDER BY layer_name, version_id;


/* =========================================================
   2. Start test transaction
   ========================================================= */

BEGIN;


/* =========================================================
   3. Simulate customer segment change in source
   ========================================================= */

UPDATE sa_cash_sales.src_cash_sales
SET segment = 'SCD2_TEST_SEGMENT'
WHERE BTRIM(customer_id) = 'AA-10315';


/* =========================================================
   4. Validate source change
   ========================================================= */

SELECT
    BTRIM(customer_id) AS customer_src_id,
    BTRIM(customer_name) AS customer_name,
    BTRIM(segment) AS customer_segment,
    COUNT(*) AS source_row_count
FROM sa_cash_sales.src_cash_sales
WHERE BTRIM(customer_id) = 'AA-10315'
GROUP BY
    BTRIM(customer_id),
    BTRIM(customer_name),
    BTRIM(segment)
ORDER BY customer_name, customer_segment;


/* =========================================================
   5. Detect customer SCD change
   ========================================================= */

SELECT
    change_type,
    current_customer_id,
    new_customer_id,
    customer_src_id,
    customer_name,
    customer_segment,
    source_system,
    source_entity
FROM bl_cl.fn_get_customer_scd_changes()
WHERE customer_src_id = 'AA-10315';


/* =========================================================
   6. Load SCD customer change to BL_3NF
   ========================================================= */

CALL bl_cl.prc_load_ce_customers_scd();


/* =========================================================
   7. Show old and new SCD versions in BL_3NF
   ========================================================= */

SELECT
    customer_id,
    customer_src_id,
    customer_name,
    customer_segment,
    start_dt,
    end_dt,
    is_active,
    source_system,
    source_entity,
    insert_dt
FROM bl_3nf.ce_customers_scd
WHERE customer_src_id = 'AA-10315'
ORDER BY customer_id;


/* =========================================================
   8. Propagate SCD versions to BL_DM
   ========================================================= */

CALL bl_cl.prc_load_dim_customers_scd();


/* =========================================================
   9. Compare SCD versions in BL_3NF and BL_DM
   ========================================================= */

SELECT
    'BL_3NF' AS layer_name,
    customer_id AS version_id,
    customer_src_id,
    customer_name,
    customer_segment,
    start_dt,
    end_dt,
    is_active
FROM bl_3nf.ce_customers_scd
WHERE customer_src_id = 'AA-10315'

UNION ALL

SELECT
    'BL_DM' AS layer_name,
    customer_surr_id AS version_id,
    customer_src_id,
    customer_name,
    customer_segment,
    start_dt,
    end_dt,
    is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = 'AA-10315'

ORDER BY
    layer_name,
    version_id;


/* =========================================================
   10. Validate exactly one active version per layer
   ========================================================= */

SELECT
    layer_name,
    COUNT(*) AS total_versions,
    COUNT(*) FILTER (
        WHERE UPPER(BTRIM(is_active)) = 'Y'
    ) AS active_versions,
    COUNT(*) FILTER (
        WHERE UPPER(BTRIM(is_active)) = 'N'
    ) AS inactive_versions
FROM (
    SELECT
        'BL_3NF' AS layer_name,
        is_active
    FROM bl_3nf.ce_customers_scd
    WHERE customer_src_id = 'AA-10315'

    UNION ALL

    SELECT
        'BL_DM' AS layer_name,
        is_active
    FROM bl_dm.dim_customers_scd
    WHERE customer_src_id = 'AA-10315'
) s
GROUP BY layer_name
ORDER BY layer_name;


/* =========================================================
   11. SCD execution log
   Expected:
   - prc_load_ce_customers_scd: 2 affected rows
   - prc_load_dim_customers_scd: 2 affected rows
   ========================================================= */

SELECT
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
    'prc_load_ce_customers_scd',
    'prc_load_dim_customers_scd'
)
ORDER BY log_id DESC
LIMIT 6;


/* =========================================================
   12. Rollback all test changes
   ========================================================= */

ROLLBACK;


/* =========================================================
   13. Confirm test source data was removed
   Expected: 0
   ========================================================= */

SELECT
    COUNT(*) AS remaining_test_segment_rows
FROM sa_cash_sales.src_cash_sales
WHERE BTRIM(customer_id) = 'AA-10315'
  AND BTRIM(segment) = 'SCD2_TEST_SEGMENT';


/* =========================================================
   14. Confirm normal customer state after rollback
   ========================================================= */

SELECT
    'BL_3NF' AS layer_name,
    customer_id AS version_id,
    customer_src_id,
    customer_name,
    customer_segment,
    start_dt,
    end_dt,
    is_active
FROM bl_3nf.ce_customers_scd
WHERE customer_src_id = 'AA-10315'

UNION ALL

SELECT
    'BL_DM' AS layer_name,
    customer_surr_id AS version_id,
    customer_src_id,
    customer_name,
    customer_segment,
    start_dt,
    end_dt,
    is_active
FROM bl_dm.dim_customers_scd
WHERE customer_src_id = 'AA-10315'

ORDER BY
    layer_name,
    version_id;
