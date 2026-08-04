-- ============================================================
-- ETL TASK - FINAL USED SQL
-- Database: dwh
-- ============================================================
-- This file contains the final ETL-related DDL statements,
-- functions, procedures, and SCD protection index.
-- ============================================================


-- ------------------------------------------------------------
-- Metadata columns added during the ETL task
-- ------------------------------------------------------------
ALTER TABLE bl_3nf.ce_employees
ADD COLUMN IF NOT EXISTS source_id VARCHAR;

ALTER TABLE bl_3nf.ce_products
ADD COLUMN IF NOT EXISTS source_id VARCHAR;


-- ------------------------------------------------------------
-- SCD Type 2 protection:
-- only one active row is allowed per customer source ID.
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_ce_customers_scd_one_active_customer
ON bl_3nf.ce_customers_scd (
    (BTRIM(customer_src_id))
)
WHERE UPPER(BTRIM(COALESCE(is_active, ''))) = 'Y';


-- ============================================================
-- FUNCTIONS AND PROCEDURES
-- The following objects are extracted from the current database.
-- ============================================================



-- ============================================================
-- OBJECT: bl_cl.prc_insert_load_log
-- ============================================================\nCREATE OR REPLACE PROCEDURE bl_cl.prc_insert_load_log(IN p_procedure_name character varying, IN p_target_table character varying, IN p_rows_affected bigint, IN p_status character varying, IN p_message text, IN p_error_code character varying DEFAULT NULL::character varying, IN p_error_message text DEFAULT NULL::text)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    INSERT INTO bl_cl.load_log (
        procedure_name,
        target_table,
        rows_affected,
        status,
        message,
        error_code,
        error_message
    )
    VALUES (
        p_procedure_name,
        p_target_table,
        p_rows_affected,
        p_status,
        p_message,
        p_error_code,
        p_error_message
    );
END;
$procedure$



-- ============================================================
-- OBJECT: bl_cl.fn_get_customer_scd_changes
-- ============================================================\nCREATE OR REPLACE FUNCTION bl_cl.fn_get_customer_scd_changes()
 RETURNS TABLE(change_type character varying, current_customer_id bigint, new_customer_id bigint, customer_src_id character varying, customer_name character varying, customer_segment character varying, source_system character varying, source_entity character varying)
 LANGUAGE sql
AS $function$
    WITH raw_source_data AS (

        -- Cash sales source has priority when the same customer
        -- exists in both source systems.
        SELECT DISTINCT
            1 AS source_priority,
            TRIM(c.customer_id)::VARCHAR AS customer_src_id,
            COALESCE(NULLIF(TRIM(c.customer_name), ''), 'N/A')::VARCHAR
                AS customer_name,
            COALESCE(NULLIF(TRIM(c.segment), ''), 'N/A')::VARCHAR
                AS customer_segment
        FROM sa_cash_sales.src_cash_sales c
        WHERE NULLIF(TRIM(c.customer_id), '') IS NOT NULL

        UNION ALL

        -- Card sales source.
        SELECT DISTINCT
            2 AS source_priority,
            TRIM(card.customer_id)::VARCHAR AS customer_src_id,
            COALESCE(NULLIF(TRIM(card.customer_name), ''), 'N/A')::VARCHAR
                AS customer_name,
            COALESCE(NULLIF(TRIM(card.segment), ''), 'N/A')::VARCHAR
                AS customer_segment
        FROM sa_card_sales.src_card_sales card
        WHERE NULLIF(TRIM(card.customer_id), '') IS NOT NULL
    ),

    -- Keep exactly one source version per customer business key.
    source_customers AS (
        SELECT
            customer_src_id,
            customer_name,
            customer_segment
        FROM (
            SELECT
                r.*,
                ROW_NUMBER() OVER (
                    PARTITION BY r.customer_src_id
                    ORDER BY
                        r.source_priority,
                        r.customer_name,
                        r.customer_segment
                ) AS rn
            FROM raw_source_data r
        ) ranked_source
        WHERE rn = 1
    ),

    -- Only currently active SCD records participate in comparison.
    active_target AS (
        SELECT
            t.customer_id,
            TRIM(t.customer_src_id)::VARCHAR AS customer_src_id,
            COALESCE(NULLIF(TRIM(t.customer_name), ''), 'N/A')::VARCHAR
                AS customer_name,
            COALESCE(NULLIF(TRIM(t.customer_segment), ''), 'N/A')::VARCHAR
                AS customer_segment
        FROM bl_3nf.ce_customers_scd t
        WHERE UPPER(BTRIM(COALESCE(t.is_active, ''))) = 'Y'
    ),

    -- Identify source rows that are new or changed.
    changes AS (
        SELECT
            CASE
                WHEN t.customer_id IS NULL THEN 'NEW'
                ELSE 'CHANGED'
            END::VARCHAR AS change_type,

            t.customer_id AS current_customer_id,

            s.customer_src_id,
            s.customer_name,
            s.customer_segment
        FROM source_customers s
        LEFT JOIN active_target t
            ON s.customer_src_id = t.customer_src_id
        WHERE t.customer_id IS NULL
           OR s.customer_name IS DISTINCT FROM t.customer_name
           OR s.customer_segment IS DISTINCT FROM t.customer_segment
    ),

    -- Generate next surrogate customer IDs for new SCD versions.
    max_id AS (
        SELECT COALESCE(MAX(customer_id), 0) AS max_customer_id
        FROM bl_3nf.ce_customers_scd
        WHERE customer_id <> -1
    )

    SELECT
        c.change_type,
        c.current_customer_id,

        m.max_customer_id
            + ROW_NUMBER() OVER (
                ORDER BY c.customer_src_id, c.change_type
            ) AS new_customer_id,

        c.customer_src_id,
        c.customer_name,
        c.customer_segment,

        'SA_CASH_SALES/SA_CARD_SALES'::VARCHAR AS source_system,
        'SRC_CASH_SALES/SRC_CARD_SALES'::VARCHAR AS source_entity
    FROM changes c
    CROSS JOIN max_id m;
$function$



-- ============================================================
-- OBJECT: bl_cl.fn_get_new_ce_employees
-- ============================================================\nCREATE OR REPLACE FUNCTION bl_cl.fn_get_new_ce_employees()
 RETURNS TABLE(employee_id bigint, employee_src_id character varying, employee_name character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
 LANGUAGE sql
AS $function$
    WITH source_data AS (

        -- Get distinct employees from cash sales.
        SELECT DISTINCT
            TRIM(c.employee_id)::VARCHAR AS employee_src_id,
            COALESCE(NULLIF(TRIM(c.employee_name), ''), 'N/A')::VARCHAR AS employee_name
        FROM sa_cash_sales.src_cash_sales c
        WHERE NULLIF(TRIM(c.employee_id), '') IS NOT NULL

        UNION

        -- Get distinct employees from card sales.
        SELECT DISTINCT
            TRIM(card.employee_id)::VARCHAR AS employee_src_id,
            COALESCE(NULLIF(TRIM(card.employee_name), ''), 'N/A')::VARCHAR AS employee_name
        FROM sa_card_sales.src_card_sales card
        WHERE NULLIF(TRIM(card.employee_id), '') IS NOT NULL
    ),

    -- LEFT JOIN anti-join:
    -- Return only source employees that do not exist in target.
    new_rows AS (
        SELECT
            s.employee_src_id,
            s.employee_name
        FROM source_data s
        LEFT JOIN bl_3nf.ce_employees t
            ON s.employee_src_id = t.employee_src_id
        WHERE t.employee_id IS NULL
    ),

    -- Generate next available surrogate IDs.
    max_id AS (
        SELECT COALESCE(MAX(t.employee_id), 0) AS max_employee_id
        FROM bl_3nf.ce_employees t
        WHERE t.employee_id <> -1
    )

    SELECT
        m.max_employee_id
            + ROW_NUMBER() OVER (ORDER BY n.employee_src_id)
            AS employee_id,

        n.employee_src_id,
        n.employee_name,

        'SA_CASH_SALES/SA_CARD_SALES'::VARCHAR AS source_system,
        'SRC_CASH_SALES/SRC_CARD_SALES'::VARCHAR AS source_entity,

        n.employee_src_id::VARCHAR AS source_id,

        CURRENT_DATE AS insert_dt,
        CURRENT_DATE AS update_dt
    FROM new_rows n
    CROSS JOIN max_id m;
$function$



-- ============================================================
-- OBJECT: bl_cl.fn_get_new_ce_locations
-- ============================================================\nCREATE OR REPLACE FUNCTION bl_cl.fn_get_new_ce_locations()
 RETURNS TABLE(location_id bigint, location_src_id character varying, country character varying, city character varying, state character varying, postal_code character varying, region character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
 LANGUAGE sql
AS $function$
    WITH source_data AS (

        -- Read distinct locations from cash sales.
        SELECT DISTINCT
            CONCAT_WS(
                '_',
                COALESCE(c.country::VARCHAR, 'N/A'),
                COALESCE(c.city::VARCHAR, 'N/A'),
                COALESCE(c.state::VARCHAR, 'N/A')
            )::VARCHAR AS location_src_id,

            COALESCE(c.country::VARCHAR, 'N/A') AS country,
            COALESCE(c.city::VARCHAR, 'N/A') AS city,
            COALESCE(c.state::VARCHAR, 'N/A') AS state,
            COALESCE(c.postal_code::VARCHAR, 'N/A') AS postal_code,
            COALESCE(c.region::VARCHAR, 'N/A') AS region
        FROM sa_cash_sales.src_cash_sales c

        UNION

        -- Read distinct locations from card sales.
        SELECT DISTINCT
            CONCAT_WS(
                '_',
                COALESCE(card.country::VARCHAR, 'N/A'),
                COALESCE(card.city::VARCHAR, 'N/A'),
                COALESCE(card.state::VARCHAR, 'N/A')
            )::VARCHAR AS location_src_id,

            COALESCE(card.country::VARCHAR, 'N/A') AS country,
            COALESCE(card.city::VARCHAR, 'N/A') AS city,
            COALESCE(card.state::VARCHAR, 'N/A') AS state,
            COALESCE(card.postal_code::VARCHAR, 'N/A') AS postal_code,
            COALESCE(card.region::VARCHAR, 'N/A') AS region
        FROM sa_card_sales.src_card_sales card
    ),

    -- Use LEFT JOIN anti-join logic.
    -- A location is considered already loaded only when all
    -- descriptive location attributes match.
    new_rows AS (
        SELECT
            s.location_src_id,
            s.country,
            s.city,
            s.state,
            s.postal_code,
            s.region
        FROM source_data s
        LEFT JOIN bl_3nf.ce_locations t
            ON COALESCE(t.country, 'N/A') = s.country
           AND COALESCE(t.city, 'N/A') = s.city
           AND COALESCE(t.state, 'N/A') = s.state
           AND COALESCE(t.postal_code, 'N/A') = s.postal_code
           AND COALESCE(t.region, 'N/A') = s.region
        WHERE t.location_id IS NULL
    ),

    max_id AS (
        SELECT COALESCE(MAX(location_id), 0) AS max_location_id
        FROM bl_3nf.ce_locations
        WHERE location_id <> -1
    )

    SELECT
        m.max_location_id
            + ROW_NUMBER() OVER (ORDER BY n.location_src_id, n.postal_code)
            AS location_id,

        n.location_src_id,
        n.country,
        n.city,
        n.state,
        n.postal_code,
        n.region,

        'SA_CASH_SALES/SA_CARD_SALES'::VARCHAR AS source_system,
        'SRC_CASH_SALES/SRC_CARD_SALES'::VARCHAR AS source_entity,

        n.location_src_id::VARCHAR AS source_id,

        CURRENT_DATE AS insert_dt,
        CURRENT_DATE AS update_dt
    FROM new_rows n
    CROSS JOIN max_id m;
$function$



-- ============================================================
-- OBJECT: bl_cl.fn_get_new_ce_payments
-- ============================================================\nCREATE OR REPLACE FUNCTION bl_cl.fn_get_new_ce_payments()
 RETURNS TABLE(payment_id bigint, payment_src_id character varying, payment_type character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
 LANGUAGE sql
AS $function$
    WITH source_data AS (
        SELECT DISTINCT
            COALESCE(c.payment_type, 'N/A') AS payment_src_id,
            COALESCE(c.payment_type, 'N/A') AS payment_type
        FROM sa_cash_sales.src_cash_sales c

        UNION

        SELECT DISTINCT
            COALESCE(card.payment_type, 'N/A') AS payment_src_id,
            COALESCE(card.payment_type, 'N/A') AS payment_type
        FROM sa_card_sales.src_card_sales card
    ),
    new_rows AS (
        SELECT
            s.payment_src_id,
            s.payment_type
        FROM source_data s
        LEFT JOIN bl_3nf.ce_payments t
            ON s.payment_src_id = t.payment_src_id
        WHERE t.payment_id IS NULL
    ),
    max_id AS (
        SELECT COALESCE(MAX(t.payment_id), 0) AS max_payment_id
        FROM bl_3nf.ce_payments t
        WHERE t.payment_id <> -1
    )
    SELECT
        m.max_payment_id + ROW_NUMBER() OVER (ORDER BY n.payment_src_id) AS payment_id,
        n.payment_src_id,
        n.payment_type,
        'SA_CASH_SALES/SA_CARD_SALES'::VARCHAR AS source_system,
        'SRC_CASH_SALES/SRC_CARD_SALES'::VARCHAR AS source_entity,
        n.payment_src_id::VARCHAR AS source_id,
        CURRENT_DATE AS insert_dt,
        CURRENT_DATE AS update_dt
    FROM new_rows n
    CROSS JOIN max_id m;
$function$



-- ============================================================
-- OBJECT: bl_cl.fn_get_new_ce_products
-- ============================================================\nCREATE OR REPLACE FUNCTION bl_cl.fn_get_new_ce_products()
 RETURNS TABLE(product_id bigint, product_src_id character varying, product_name character varying, category character varying, sub_category character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
 LANGUAGE sql
AS $function$
    WITH raw_source_data AS (

        -- Products from cash sales source.
        SELECT
            1 AS source_priority,
            TRIM(c.product_id)::VARCHAR AS product_src_id,
            COALESCE(NULLIF(TRIM(c.product_name), ''), 'N/A')::VARCHAR AS product_name,
            COALESCE(NULLIF(TRIM(c.category), ''), 'N/A')::VARCHAR AS category,
            COALESCE(NULLIF(TRIM(c.sub_category), ''), 'N/A')::VARCHAR AS sub_category
        FROM sa_cash_sales.src_cash_sales c
        WHERE NULLIF(TRIM(c.product_id), '') IS NOT NULL

        UNION ALL

        -- Products from card sales source.
        SELECT
            2 AS source_priority,
            TRIM(card.product_id)::VARCHAR AS product_src_id,
            COALESCE(NULLIF(TRIM(card.product_name), ''), 'N/A')::VARCHAR AS product_name,
            COALESCE(NULLIF(TRIM(card.category), ''), 'N/A')::VARCHAR AS category,
            COALESCE(NULLIF(TRIM(card.sub_category), ''), 'N/A')::VARCHAR AS sub_category
        FROM sa_card_sales.src_card_sales card
        WHERE NULLIF(TRIM(card.product_id), '') IS NOT NULL
    ),

    -- Keep one normalized record for each product business key.
    -- Cash source has priority when the same product exists
    -- in both source systems.
    source_data AS (
        SELECT
            product_src_id,
            product_name,
            category,
            sub_category
        FROM (
            SELECT
                r.*,
                ROW_NUMBER() OVER (
                    PARTITION BY r.product_src_id
                    ORDER BY
                        r.source_priority,
                        r.product_name,
                        r.category,
                        r.sub_category
                ) AS rn
            FROM raw_source_data r
        ) ranked_source
        WHERE rn = 1
    ),

    -- LEFT JOIN anti-join:
    -- return only products absent from CE_PRODUCTS.
    new_rows AS (
        SELECT
            s.product_src_id,
            s.product_name,
            s.category,
            s.sub_category
        FROM source_data s
        LEFT JOIN bl_3nf.ce_products t
            ON s.product_src_id = t.product_src_id
        WHERE t.product_id IS NULL
    ),

    -- Find the next available surrogate key.
    max_id AS (
        SELECT COALESCE(MAX(product_id), 0) AS max_product_id
        FROM bl_3nf.ce_products
        WHERE product_id <> -1
    )

    SELECT
        m.max_product_id
            + ROW_NUMBER() OVER (ORDER BY n.product_src_id)
            AS product_id,

        n.product_src_id,
        n.product_name,
        n.category,
        n.sub_category,

        'SA_CASH_SALES/SA_CARD_SALES'::VARCHAR AS source_system,
        'SRC_CASH_SALES/SRC_CARD_SALES'::VARCHAR AS source_entity,

        n.product_src_id::VARCHAR AS source_id,

        CURRENT_DATE AS insert_dt,
        CURRENT_DATE AS update_dt
    FROM new_rows n
    CROSS JOIN max_id m;
$function$



-- ============================================================
-- OBJECT: bl_cl.fn_get_new_ce_returned
-- ============================================================\nCREATE OR REPLACE FUNCTION bl_cl.fn_get_new_ce_returned()
 RETURNS TABLE(returned_id bigint, returned_src_id character varying, returned character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
 LANGUAGE sql
AS $function$
    WITH source_data AS (
        SELECT DISTINCT
            COALESCE(card.returned, 'N/A') AS returned_src_id,
            COALESCE(card.returned, 'N/A') AS returned
        FROM sa_card_sales.src_card_sales card
    ),
    new_rows AS (
        SELECT
            s.returned_src_id,
            s.returned
        FROM source_data s
        LEFT JOIN bl_3nf.ce_returned t
            ON s.returned_src_id = t.returned_src_id
        WHERE t.returned_id IS NULL
    ),
    max_id AS (
        SELECT COALESCE(MAX(t.returned_id), 0) AS max_returned_id
        FROM bl_3nf.ce_returned t
        WHERE t.returned_id <> -1
    )
    SELECT
        m.max_returned_id + ROW_NUMBER() OVER (ORDER BY n.returned_src_id) AS returned_id,
        n.returned_src_id,
        n.returned,
        'SA_CARD_SALES'::VARCHAR AS source_system,
        'SRC_CARD_SALES'::VARCHAR AS source_entity,
        n.returned_src_id::VARCHAR AS source_id,
        CURRENT_DATE AS insert_dt,
        CURRENT_DATE AS update_dt
    FROM new_rows n
    CROSS JOIN max_id m;
$function$



-- ============================================================
-- OBJECT: bl_cl.fn_get_new_ce_ship_modes
-- ============================================================\nCREATE OR REPLACE FUNCTION bl_cl.fn_get_new_ce_ship_modes()
 RETURNS TABLE(ship_mode_id bigint, ship_mode_src_id character varying, ship_mode character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
 LANGUAGE sql
AS $function$
    WITH source_data AS (
        SELECT DISTINCT
            COALESCE(c.ship_mode, 'N/A') AS ship_mode_src_id,
            COALESCE(c.ship_mode, 'N/A') AS ship_mode
        FROM sa_cash_sales.src_cash_sales c

        UNION

        SELECT DISTINCT
            COALESCE(card.ship_mode, 'N/A') AS ship_mode_src_id,
            COALESCE(card.ship_mode, 'N/A') AS ship_mode
        FROM sa_card_sales.src_card_sales card
    ),
    new_rows AS (
        SELECT
            s.ship_mode_src_id,
            s.ship_mode
        FROM source_data s
        LEFT JOIN bl_3nf.ce_ship_modes t
            ON s.ship_mode_src_id = t.ship_mode_src_id
        WHERE t.ship_mode_id IS NULL
    ),
    max_id AS (
        SELECT COALESCE(MAX(t.ship_mode_id), 0) AS max_ship_mode_id
        FROM bl_3nf.ce_ship_modes t
        WHERE t.ship_mode_id <> -1
    )
    SELECT
        m.max_ship_mode_id + ROW_NUMBER() OVER (ORDER BY n.ship_mode_src_id) AS ship_mode_id,
        n.ship_mode_src_id,
        n.ship_mode,
        'SA_CASH_SALES/SA_CARD_SALES'::VARCHAR AS source_system,
        'SRC_CASH_SALES/SRC_CARD_SALES'::VARCHAR AS source_entity,
        n.ship_mode_src_id::VARCHAR AS source_id,
        CURRENT_DATE AS insert_dt,
        CURRENT_DATE AS update_dt
    FROM new_rows n
    CROSS JOIN max_id m;
$function$



-- ============================================================
-- OBJECT: bl_cl.prc_load_ce_customers_scd
-- ============================================================\nCREATE OR REPLACE PROCEDURE bl_cl.prc_load_ce_customers_scd()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_rows_affected BIGINT := 0;
    v_default_rows  BIGINT := 0;
    v_closed_rows   BIGINT := 0;
    v_rec           RECORD;
BEGIN
    -- Prevent concurrent SCD runs from creating conflicting
    -- active versions for the same customer.
    LOCK TABLE bl_3nf.ce_customers_scd
    IN SHARE ROW EXCLUSIVE MODE;

    -- Ensure the default / unknown customer record exists.
    INSERT INTO bl_3nf.ce_customers_scd (
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
    )
    SELECT
        -1,
        'N/A',
        'N/A',
        'N/A',
        'MANUAL',
        'MANUAL',
        DATE '1900-01-01',
        DATE '9999-12-31',
        'Y',
        DATE '1900-01-01'
    WHERE NOT EXISTS (
        SELECT 1
        FROM bl_3nf.ce_customers_scd
        WHERE customer_id = -1
    );

    GET DIAGNOSTICS v_default_rows = ROW_COUNT;

    -- Process all new or changed customers.
    FOR v_rec IN
        SELECT *
        FROM bl_cl.fn_get_customer_scd_changes()
    LOOP

        -- For a changed customer, close the currently active version.
        IF v_rec.change_type = 'CHANGED' THEN

            UPDATE bl_3nf.ce_customers_scd
            SET
                end_dt = CURRENT_DATE - 1,
                is_active = 'N'
            WHERE customer_id = v_rec.current_customer_id
              AND UPPER(BTRIM(COALESCE(is_active, ''))) = 'Y';

            GET DIAGNOSTICS v_closed_rows = ROW_COUNT;

            -- A changed row must close exactly one active version.
            IF v_closed_rows <> 1 THEN
                RAISE EXCEPTION
                    'SCD Type 2 close operation affected % rows for customer_src_id %.',
                    v_closed_rows,
                    v_rec.customer_src_id;
            END IF;

            v_rows_affected := v_rows_affected + v_closed_rows;
        END IF;

        -- Insert a new active version:
        -- - for a completely new customer
        -- - or for the changed customer after old version is closed
        INSERT INTO bl_3nf.ce_customers_scd (
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
        )
        VALUES (
            v_rec.new_customer_id,
            v_rec.customer_src_id,
            v_rec.customer_name,
            v_rec.customer_segment,
            v_rec.source_system,
            v_rec.source_entity,
            CURRENT_DATE,
            DATE '9999-12-31',
            'Y',
            CURRENT_DATE
        );

        v_rows_affected := v_rows_affected + 1;
    END LOOP;

    v_rows_affected := v_rows_affected + v_default_rows;

    -- Log successful execution.
    CALL bl_cl.prc_insert_load_log(
        'prc_load_ce_customers_scd',
        'bl_3nf.ce_customers_scd',
        v_rows_affected,
        'SUCCESS',
        'CE_CUSTOMERS_SCD loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Log any failure in the centralized ETL log.
        CALL bl_cl.prc_insert_load_log(
            'prc_load_ce_customers_scd',
            'bl_3nf.ce_customers_scd',
            0,
            'ERROR',
            'Error while loading CE_CUSTOMERS_SCD.',
            SQLSTATE,
            SQLERRM
        );
END;
$procedure$



-- ============================================================
-- OBJECT: bl_cl.prc_load_ce_employees
-- ============================================================\nCREATE OR REPLACE PROCEDURE bl_cl.prc_load_ce_employees()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_rows_affected BIGINT := 0;
    v_default_rows  BIGINT := 0;
    v_rec           RECORD;
BEGIN
    -- Ensure default/unknown employee row exists.
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
        'MANUAL',
        'MANUAL',
        'N/A',
        DATE '1900-01-01',
        DATE '1900-01-01'
    WHERE NOT EXISTS (
        SELECT 1
        FROM bl_3nf.ce_employees
        WHERE employee_id = -1
    );

    GET DIAGNOSTICS v_default_rows = ROW_COUNT;

    -- Loop over only new employees returned by function.
    FOR v_rec IN
        SELECT *
        FROM bl_cl.fn_get_new_ce_employees()
    LOOP
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
        VALUES (
            v_rec.employee_id,
            v_rec.employee_src_id,
            v_rec.employee_name,
            v_rec.source_system,
            v_rec.source_entity,
            v_rec.source_id,
            v_rec.insert_dt,
            v_rec.update_dt
        );

        v_rows_affected := v_rows_affected + 1;
    END LOOP;

    v_rows_affected := v_rows_affected + v_default_rows;

    -- Write successful execution to centralized log.
    CALL bl_cl.prc_insert_load_log(
        'prc_load_ce_employees',
        'bl_3nf.ce_employees',
        v_rows_affected,
        'SUCCESS',
        'CE_EMPLOYEES loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Write error details to centralized log.
        CALL bl_cl.prc_insert_load_log(
            'prc_load_ce_employees',
            'bl_3nf.ce_employees',
            0,
            'ERROR',
            'Error while loading CE_EMPLOYEES.',
            SQLSTATE,
            SQLERRM
        );
END;
$procedure$



-- ============================================================
-- OBJECT: bl_cl.prc_load_ce_locations
-- ============================================================\nCREATE OR REPLACE PROCEDURE bl_cl.prc_load_ce_locations()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_rows_affected BIGINT := 0;
    v_default_rows  BIGINT := 0;
    v_rec           RECORD;
BEGIN
    -- Ensure default unknown row exists.
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
        'MANUAL',
        'MANUAL',
        'N/A',
        '1900-01-01'::DATE,
        '1900-01-01'::DATE
    WHERE NOT EXISTS (
        SELECT 1
        FROM bl_3nf.ce_locations
        WHERE location_id = -1
    );

    GET DIAGNOSTICS v_default_rows = ROW_COUNT;

    -- Load only new locations.
    FOR v_rec IN
        SELECT *
        FROM bl_cl.fn_get_new_ce_locations()
    LOOP
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
        VALUES (
            v_rec.location_id,
            v_rec.location_src_id,
            v_rec.country,
            v_rec.city,
            v_rec.state,
            v_rec.postal_code,
            v_rec.region,
            v_rec.source_system,
            v_rec.source_entity,
            v_rec.source_id,
            v_rec.insert_dt,
            v_rec.update_dt
        );

        v_rows_affected := v_rows_affected + 1;
    END LOOP;

    v_rows_affected := v_rows_affected + v_default_rows;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_ce_locations',
        'bl_3nf.ce_locations',
        v_rows_affected,
        'SUCCESS',
        'CE_LOCATIONS loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_ce_locations',
            'bl_3nf.ce_locations',
            0,
            'ERROR',
            'Error while loading CE_LOCATIONS.',
            SQLSTATE,
            SQLERRM
        );
END;
$procedure$



-- ============================================================
-- OBJECT: bl_cl.prc_load_ce_payments
-- ============================================================\nCREATE OR REPLACE PROCEDURE bl_cl.prc_load_ce_payments()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_rows_affected BIGINT := 0;
    v_default_rows  BIGINT := 0;
    v_rec           RECORD;
BEGIN
    -- Ensure default unknown row exists.
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
        'MANUAL',
        'MANUAL',
        'N/A',
        '1900-01-01'::DATE,
        '1900-01-01'::DATE
    WHERE NOT EXISTS (
        SELECT 1
        FROM bl_3nf.ce_payments
        WHERE payment_id = -1
    );

    GET DIAGNOSTICS v_default_rows = ROW_COUNT;

    -- Load only new payment types.
    FOR v_rec IN
        SELECT *
        FROM bl_cl.fn_get_new_ce_payments()
    LOOP
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
        VALUES (
            v_rec.payment_id,
            v_rec.payment_src_id,
            v_rec.payment_type,
            v_rec.source_system,
            v_rec.source_entity,
            v_rec.source_id,
            v_rec.insert_dt,
            v_rec.update_dt
        );

        v_rows_affected := v_rows_affected + 1;
    END LOOP;

    v_rows_affected := v_rows_affected + v_default_rows;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_ce_payments',
        'bl_3nf.ce_payments',
        v_rows_affected,
        'SUCCESS',
        'CE_PAYMENTS loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_ce_payments',
            'bl_3nf.ce_payments',
            0,
            'ERROR',
            'Error while loading CE_PAYMENTS.',
            SQLSTATE,
            SQLERRM
        );
END;
$procedure$



-- ============================================================
-- OBJECT: bl_cl.prc_load_ce_products
-- ============================================================\nCREATE OR REPLACE PROCEDURE bl_cl.prc_load_ce_products()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_rows_affected BIGINT := 0;
    v_default_rows  BIGINT := 0;
    v_rec           RECORD;
BEGIN
    -- Ensure the default unknown product row exists.
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
        'MANUAL',
        'MANUAL',
        'N/A',
        DATE '1900-01-01',
        DATE '1900-01-01'
    WHERE NOT EXISTS (
        SELECT 1
        FROM bl_3nf.ce_products
        WHERE product_id = -1
    );

    GET DIAGNOSTICS v_default_rows = ROW_COUNT;

    -- Insert only products returned by the anti-join function.
    FOR v_rec IN
        SELECT *
        FROM bl_cl.fn_get_new_ce_products()
    LOOP
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
        VALUES (
            v_rec.product_id,
            v_rec.product_src_id,
            v_rec.product_name,
            v_rec.category,
            v_rec.sub_category,
            v_rec.source_system,
            v_rec.source_entity,
            v_rec.source_id,
            v_rec.insert_dt,
            v_rec.update_dt
        );

        v_rows_affected := v_rows_affected + 1;
    END LOOP;

    v_rows_affected := v_rows_affected + v_default_rows;

    -- Write successful load information to centralized log.
    CALL bl_cl.prc_insert_load_log(
        'prc_load_ce_products',
        'bl_3nf.ce_products',
        v_rows_affected,
        'SUCCESS',
        'CE_PRODUCTS loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Write error details to centralized log.
        CALL bl_cl.prc_insert_load_log(
            'prc_load_ce_products',
            'bl_3nf.ce_products',
            0,
            'ERROR',
            'Error while loading CE_PRODUCTS.',
            SQLSTATE,
            SQLERRM
        );
END;
$procedure$



-- ============================================================
-- OBJECT: bl_cl.prc_load_ce_returned
-- ============================================================\nCREATE OR REPLACE PROCEDURE bl_cl.prc_load_ce_returned()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_rows_affected BIGINT := 0;
    v_default_rows  BIGINT := 0;
    v_rec           RECORD;
BEGIN
    -- Ensure default unknown row exists.
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
        'MANUAL',
        'MANUAL',
        'N/A',
        '1900-01-01'::DATE,
        '1900-01-01'::DATE
    WHERE NOT EXISTS (
        SELECT 1
        FROM bl_3nf.ce_returned
        WHERE returned_id = -1
    );

    GET DIAGNOSTICS v_default_rows = ROW_COUNT;

    -- Load only new returned statuses.
    FOR v_rec IN
        SELECT *
        FROM bl_cl.fn_get_new_ce_returned()
    LOOP
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
        VALUES (
            v_rec.returned_id,
            v_rec.returned_src_id,
            v_rec.returned,
            v_rec.source_system,
            v_rec.source_entity,
            v_rec.source_id,
            v_rec.insert_dt,
            v_rec.update_dt
        );

        v_rows_affected := v_rows_affected + 1;
    END LOOP;

    v_rows_affected := v_rows_affected + v_default_rows;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_ce_returned',
        'bl_3nf.ce_returned',
        v_rows_affected,
        'SUCCESS',
        'CE_RETURNED loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_ce_returned',
            'bl_3nf.ce_returned',
            0,
            'ERROR',
            'Error while loading CE_RETURNED.',
            SQLSTATE,
            SQLERRM
        );
END;
$procedure$



-- ============================================================
-- OBJECT: bl_cl.prc_load_ce_ship_modes
-- ============================================================\nCREATE OR REPLACE PROCEDURE bl_cl.prc_load_ce_ship_modes()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_rows_affected BIGINT := 0;
    v_default_rows  BIGINT := 0;
    v_rec           RECORD;
BEGIN
    -- Ensure default unknown row exists.
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
        'MANUAL',
        'MANUAL',
        'N/A',
        '1900-01-01'::DATE,
        '1900-01-01'::DATE
    WHERE NOT EXISTS (
        SELECT 1
        FROM bl_3nf.ce_ship_modes
        WHERE ship_mode_id = -1
    );

    GET DIAGNOSTICS v_default_rows = ROW_COUNT;

    -- Load only new ship modes.
    -- The function already uses LEFT JOIN anti-join logic.
    FOR v_rec IN
        SELECT *
        FROM bl_cl.fn_get_new_ce_ship_modes()
    LOOP
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
        VALUES (
            v_rec.ship_mode_id,
            v_rec.ship_mode_src_id,
            v_rec.ship_mode,
            v_rec.source_system,
            v_rec.source_entity,
            v_rec.source_id,
            v_rec.insert_dt,
            v_rec.update_dt
        );

        v_rows_affected := v_rows_affected + 1;
    END LOOP;

    -- Include default row in affected count only if it was inserted.
    v_rows_affected := v_rows_affected + v_default_rows;

    -- Success log
    CALL bl_cl.prc_insert_load_log(
        'prc_load_ce_ship_modes',
        'bl_3nf.ce_ship_modes',
        v_rows_affected,
        'SUCCESS',
        'CE_SHIP_MODES loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Error log
        CALL bl_cl.prc_insert_load_log(
            'prc_load_ce_ship_modes',
            'bl_3nf.ce_ship_modes',
            0,
            'ERROR',
            'Error while loading CE_SHIP_MODES.',
            SQLSTATE,
            SQLERRM
        );
END;
$procedure$

