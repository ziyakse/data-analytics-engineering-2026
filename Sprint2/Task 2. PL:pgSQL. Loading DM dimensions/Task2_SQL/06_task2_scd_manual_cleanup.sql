\set ON_ERROR_STOP on

/* =========================================================
   TASK 2 - MANUAL SCD TEST CLEANUP
   Removes only AA-10315 / SCD2_TEST_SEGMENT test data.
   ========================================================= */

BEGIN;


/* Remove SCD test version from Data Mart layer */

DELETE FROM bl_dm.dim_customers_scd
WHERE customer_src_id = 'AA-10315'
  AND customer_segment = 'SCD2_TEST_SEGMENT';


/* Reopen original Data Mart version */

UPDATE bl_dm.dim_customers_scd
SET
    end_dt = DATE '9999-12-31',
    is_active = 'Y'
WHERE customer_surr_id = 1
  AND customer_src_id = 'AA-10315';


/* Remove SCD test version from 3NF layer */

DELETE FROM bl_3nf.ce_customers_scd
WHERE customer_src_id = 'AA-10315'
  AND customer_segment = 'SCD2_TEST_SEGMENT';


/* Reopen original 3NF version */

UPDATE bl_3nf.ce_customers_scd
SET
    end_dt = DATE '9999-12-31',
    is_active = 'Y'
WHERE customer_id = 1
  AND customer_src_id = 'AA-10315';


/* Restore original source segment */

UPDATE sa_cash_sales.src_cash_sales
SET segment = 'Consumer'
WHERE BTRIM(customer_id) = 'AA-10315'
  AND BTRIM(segment) = 'SCD2_TEST_SEGMENT';

COMMIT;


/* Verify cleanup */

SELECT
    COUNT(*) AS remaining_test_segment_rows
FROM sa_cash_sales.src_cash_sales
WHERE BTRIM(customer_id) = 'AA-10315'
  AND BTRIM(segment) = 'SCD2_TEST_SEGMENT';


/* Verify original customer state */

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
