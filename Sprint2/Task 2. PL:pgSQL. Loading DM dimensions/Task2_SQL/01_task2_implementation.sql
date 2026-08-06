--
-- PostgreSQL database dump
--

\restrict PTlENj67iTMOPwYhRWn4fRIYthj2JyTg3qgbhTycIRP5e1nC4NZ50xzFmPn4R9g

-- Dumped from database version 18.1 (Postgres.app)
-- Dumped by pg_dump version 18.1 (Postgres.app)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: bl_cl; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bl_cl;


--
-- Name: bl_dm; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bl_dm;


--
-- Name: ty_dim_product_row; Type: TYPE; Schema: bl_cl; Owner: -
--

CREATE TYPE bl_cl.ty_dim_product_row AS (
	product_surr_id bigint,
	product_src_id character varying,
	product_name character varying,
	category character varying,
	sub_category character varying,
	source_system character varying,
	source_entity character varying,
	insert_dt date,
	update_dt date
);


--
-- Name: fn_get_customer_scd_changes(); Type: FUNCTION; Schema: bl_cl; Owner: -
--

CREATE FUNCTION bl_cl.fn_get_customer_scd_changes() RETURNS TABLE(change_type character varying, current_customer_id bigint, new_customer_id bigint, customer_src_id character varying, customer_name character varying, customer_segment character varying, source_system character varying, source_entity character varying)
    LANGUAGE sql
    AS $$
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
$$;


--
-- Name: fn_get_dim_product_rows(); Type: FUNCTION; Schema: bl_cl; Owner: -
--

CREATE FUNCTION bl_cl.fn_get_dim_product_rows() RETURNS SETOF bl_cl.ty_dim_product_row
    LANGUAGE sql
    AS $$
    SELECT
        p.product_id::BIGINT AS product_surr_id,
        TRIM(p.product_src_id)::VARCHAR AS product_src_id,
        COALESCE(NULLIF(TRIM(p.product_name), ''), 'N/A')::VARCHAR AS product_name,
        COALESCE(NULLIF(TRIM(p.category), ''), 'N/A')::VARCHAR AS category,
        COALESCE(NULLIF(TRIM(p.sub_category), ''), 'N/A')::VARCHAR AS sub_category,
        COALESCE(NULLIF(TRIM(p.source_system), ''), 'N/A')::VARCHAR AS source_system,
        COALESCE(NULLIF(TRIM(p.source_entity), ''), 'N/A')::VARCHAR AS source_entity,
        COALESCE(p.insert_dt, CURRENT_DATE)::DATE AS insert_dt,
        COALESCE(p.update_dt, CURRENT_DATE)::DATE AS update_dt
    FROM bl_3nf.ce_products p
    WHERE p.product_id <> -1
    ORDER BY p.product_id;
$$;


--
-- Name: fn_get_new_ce_employees(); Type: FUNCTION; Schema: bl_cl; Owner: -
--

CREATE FUNCTION bl_cl.fn_get_new_ce_employees() RETURNS TABLE(employee_id bigint, employee_src_id character varying, employee_name character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
    LANGUAGE sql
    AS $$
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
$$;


--
-- Name: fn_get_new_ce_locations(); Type: FUNCTION; Schema: bl_cl; Owner: -
--

CREATE FUNCTION bl_cl.fn_get_new_ce_locations() RETURNS TABLE(location_id bigint, location_src_id character varying, country character varying, city character varying, state character varying, postal_code character varying, region character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
    LANGUAGE sql
    AS $$
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
$$;


--
-- Name: fn_get_new_ce_payments(); Type: FUNCTION; Schema: bl_cl; Owner: -
--

CREATE FUNCTION bl_cl.fn_get_new_ce_payments() RETURNS TABLE(payment_id bigint, payment_src_id character varying, payment_type character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
    LANGUAGE sql
    AS $$
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
$$;


--
-- Name: fn_get_new_ce_products(); Type: FUNCTION; Schema: bl_cl; Owner: -
--

CREATE FUNCTION bl_cl.fn_get_new_ce_products() RETURNS TABLE(product_id bigint, product_src_id character varying, product_name character varying, category character varying, sub_category character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
    LANGUAGE sql
    AS $$
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
$$;


--
-- Name: fn_get_new_ce_returned(); Type: FUNCTION; Schema: bl_cl; Owner: -
--

CREATE FUNCTION bl_cl.fn_get_new_ce_returned() RETURNS TABLE(returned_id bigint, returned_src_id character varying, returned character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
    LANGUAGE sql
    AS $$
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
$$;


--
-- Name: fn_get_new_ce_ship_modes(); Type: FUNCTION; Schema: bl_cl; Owner: -
--

CREATE FUNCTION bl_cl.fn_get_new_ce_ship_modes() RETURNS TABLE(ship_mode_id bigint, ship_mode_src_id character varying, ship_mode character varying, source_system character varying, source_entity character varying, source_id character varying, insert_dt date, update_dt date)
    LANGUAGE sql
    AS $$
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
$$;


--
-- Name: prc_insert_load_log(character varying, character varying, bigint, character varying, text, character varying, text); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_insert_load_log(IN p_procedure_name character varying, IN p_target_table character varying, IN p_rows_affected bigint, IN p_status character varying, IN p_message text, IN p_error_code character varying DEFAULT NULL::character varying, IN p_error_message text DEFAULT NULL::text)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: prc_load_ce_customers_scd(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_ce_customers_scd()
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: prc_load_ce_employees(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_ce_employees()
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: prc_load_ce_locations(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_ce_locations()
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: prc_load_ce_payments(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_ce_payments()
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: prc_load_ce_products(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_ce_products()
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: prc_load_ce_returned(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_ce_returned()
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: prc_load_ce_ship_modes(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_ce_ship_modes()
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: prc_load_dim_customers_scd(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_dim_customers_scd()
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows_affected BIGINT := 0;
    v_step_rows     BIGINT := 0;
BEGIN
    /*
      STEP 1:
      First update existing customer SCD versions.

      This is important because an old active version must become
      inactive before a new active version is inserted.
    */
    UPDATE bl_dm.dim_customers_scd AS d
    SET
        customer_src_id  = s.customer_src_id,
        customer_name    = s.customer_name,
        customer_segment = s.customer_segment,
        source_system    = s.source_system,
        source_entity    = s.source_entity,
        start_dt         = s.start_dt,
        end_dt           = s.end_dt,
        is_active        = s.is_active,
        insert_dt        = s.insert_dt
    FROM (
        SELECT
            c.customer_id::BIGINT AS customer_surr_id,
            TRIM(c.customer_src_id)::VARCHAR AS customer_src_id,
            COALESCE(NULLIF(TRIM(c.customer_name), ''), 'N/A')::VARCHAR
                AS customer_name,
            COALESCE(NULLIF(TRIM(c.customer_segment), ''), 'N/A')::VARCHAR
                AS customer_segment,
            COALESCE(NULLIF(TRIM(c.source_system), ''), 'N/A')::VARCHAR
                AS source_system,
            COALESCE(NULLIF(TRIM(c.source_entity), ''), 'N/A')::VARCHAR
                AS source_entity,
            COALESCE(c.start_dt, CURRENT_DATE)::DATE AS start_dt,
            COALESCE(c.end_dt, DATE '9999-12-31')::DATE AS end_dt,
            COALESCE(
                NULLIF(UPPER(TRIM(c.is_active)), ''),
                'Y'
            )::VARCHAR AS is_active,
            COALESCE(c.insert_dt, CURRENT_DATE)::DATE AS insert_dt
        FROM bl_3nf.ce_customers_scd c
        WHERE c.customer_id <> -1
    ) s
    WHERE d.customer_surr_id = s.customer_surr_id
      AND ROW(
            d.customer_src_id,
            d.customer_name,
            d.customer_segment,
            d.source_system,
            d.source_entity,
            d.start_dt,
            d.end_dt,
            d.is_active,
            d.insert_dt
          )
          IS DISTINCT FROM
          ROW(
            s.customer_src_id,
            s.customer_name,
            s.customer_segment,
            s.source_system,
            s.source_entity,
            s.start_dt,
            s.end_dt,
            s.is_active,
            s.insert_dt
          );

    GET DIAGNOSTICS v_step_rows = ROW_COUNT;
    v_rows_affected := v_rows_affected + v_step_rows;


    /*
      STEP 2:
      Insert only new customer SCD versions.

      The UPDATE above is intentionally executed first, so the
      previous active row is closed before a new active row is added.
    */
    INSERT INTO bl_dm.dim_customers_scd (
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
    )
    SELECT
        c.customer_id,
        TRIM(c.customer_src_id),
        COALESCE(NULLIF(TRIM(c.customer_name), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(c.customer_segment), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(c.source_system), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(c.source_entity), ''), 'N/A'),
        COALESCE(c.start_dt, CURRENT_DATE),
        COALESCE(c.end_dt, DATE '9999-12-31'),
        COALESCE(
            NULLIF(UPPER(TRIM(c.is_active)), ''),
            'Y'
        ),
        COALESCE(c.insert_dt, CURRENT_DATE)
    FROM bl_3nf.ce_customers_scd c
    WHERE c.customer_id <> -1
      AND NOT EXISTS (
          SELECT 1
          FROM bl_dm.dim_customers_scd d
          WHERE d.customer_surr_id = c.customer_id
      )

    ON CONFLICT (customer_surr_id) DO NOTHING;

    GET DIAGNOSTICS v_step_rows = ROW_COUNT;
    v_rows_affected := v_rows_affected + v_step_rows;


    CALL bl_cl.prc_insert_load_log(
        'prc_load_dim_customers_scd',
        'bl_dm.dim_customers_scd',
        v_rows_affected,
        'SUCCESS',
        'DIM_CUSTOMERS_SCD loaded successfully with safe SCD Type 2 version propagation.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_dim_customers_scd',
            'bl_dm.dim_customers_scd',
            0,
            'ERROR',
            'Error while loading DIM_CUSTOMERS_SCD.',
            SQLSTATE,
            SQLERRM
        );
END;
$$;


--
-- Name: prc_load_dim_employees(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_dim_employees()
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows_affected BIGINT := 0;
BEGIN
    INSERT INTO bl_dm.dim_employees AS d (
        employee_surr_id,
        employee_src_id,
        employee_name,
        source_system,
        source_entity,
        insert_dt,
        update_dt
    )
    SELECT
        e.employee_id,
        TRIM(e.employee_src_id),
        COALESCE(NULLIF(TRIM(e.employee_name), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(e.source_system), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(e.source_entity), ''), 'N/A'),
        COALESCE(e.insert_dt, CURRENT_DATE),
        COALESCE(e.update_dt, CURRENT_DATE)
    FROM bl_3nf.ce_employees e
    WHERE e.employee_id <> -1

    ON CONFLICT (employee_surr_id) DO UPDATE
    SET
        employee_src_id = EXCLUDED.employee_src_id,
        employee_name   = EXCLUDED.employee_name,
        source_system   = EXCLUDED.source_system,
        source_entity   = EXCLUDED.source_entity,
        update_dt       = CURRENT_DATE

    WHERE ROW(
        d.employee_src_id,
        d.employee_name,
        d.source_system,
        d.source_entity
    ) IS DISTINCT FROM ROW(
        EXCLUDED.employee_src_id,
        EXCLUDED.employee_name,
        EXCLUDED.source_system,
        EXCLUDED.source_entity
    );

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_dim_employees',
        'bl_dm.dim_employees',
        v_rows_affected,
        'SUCCESS',
        'DIM_EMPLOYEES loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_dim_employees',
            'bl_dm.dim_employees',
            0,
            'ERROR',
            'Error while loading DIM_EMPLOYEES.',
            SQLSTATE,
            SQLERRM
        );
END;
$$;


--
-- Name: prc_load_dim_locations(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_dim_locations()
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_location_cursor REFCURSOR;
    v_location        RECORD;
    v_rows_affected   BIGINT := 0;
    v_current_rows    BIGINT := 0;
BEGIN
    /*
      A REFCURSOR variable is used to read 3NF location rows.
      This fulfils the cursor variable requirement.
    */
    OPEN v_location_cursor FOR
        SELECT
            l.location_id::BIGINT AS location_surr_id,
            TRIM(l.location_src_id)::VARCHAR AS location_src_id,
            COALESCE(NULLIF(TRIM(l.country), ''), 'N/A')::VARCHAR AS country,
            COALESCE(NULLIF(TRIM(l.city), ''), 'N/A')::VARCHAR AS city,
            COALESCE(NULLIF(TRIM(l.state), ''), 'N/A')::VARCHAR AS state,
            COALESCE(NULLIF(TRIM(l.postal_code), ''), 'N/A')::VARCHAR AS postal_code,
            COALESCE(NULLIF(TRIM(l.region), ''), 'N/A')::VARCHAR AS region,
            COALESCE(NULLIF(TRIM(l.source_system), ''), 'N/A')::VARCHAR AS source_system,
            COALESCE(NULLIF(TRIM(l.source_entity), ''), 'N/A')::VARCHAR AS source_entity,
            COALESCE(l.insert_dt, CURRENT_DATE)::DATE AS insert_dt,
            COALESCE(l.update_dt, CURRENT_DATE)::DATE AS update_dt
        FROM bl_3nf.ce_locations l
        WHERE l.location_id <> -1
        ORDER BY l.location_id;

    LOOP
        FETCH v_location_cursor INTO v_location;
        EXIT WHEN NOT FOUND;

        INSERT INTO bl_dm.dim_locations AS d (
            location_surr_id,
            location_src_id,
            country,
            city,
            state,
            postal_code,
            region,
            source_system,
            source_entity,
            insert_dt,
            update_dt
        )
        VALUES (
            v_location.location_surr_id,
            v_location.location_src_id,
            v_location.country,
            v_location.city,
            v_location.state,
            v_location.postal_code,
            v_location.region,
            v_location.source_system,
            v_location.source_entity,
            v_location.insert_dt,
            v_location.update_dt
        )

        ON CONFLICT (location_surr_id) DO UPDATE
        SET
            location_src_id = EXCLUDED.location_src_id,
            country         = EXCLUDED.country,
            city            = EXCLUDED.city,
            state           = EXCLUDED.state,
            postal_code     = EXCLUDED.postal_code,
            region          = EXCLUDED.region,
            source_system   = EXCLUDED.source_system,
            source_entity   = EXCLUDED.source_entity,
            update_dt       = CURRENT_DATE

        WHERE ROW(
            d.location_src_id,
            d.country,
            d.city,
            d.state,
            d.postal_code,
            d.region,
            d.source_system,
            d.source_entity
        ) IS DISTINCT FROM ROW(
            EXCLUDED.location_src_id,
            EXCLUDED.country,
            EXCLUDED.city,
            EXCLUDED.state,
            EXCLUDED.postal_code,
            EXCLUDED.region,
            EXCLUDED.source_system,
            EXCLUDED.source_entity
        );

        GET DIAGNOSTICS v_current_rows = ROW_COUNT;
        v_rows_affected := v_rows_affected + v_current_rows;
    END LOOP;

    CLOSE v_location_cursor;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_dim_locations',
        'bl_dm.dim_locations',
        v_rows_affected,
        'SUCCESS',
        'DIM_LOCATIONS loaded successfully using a REFCURSOR variable.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_dim_locations',
            'bl_dm.dim_locations',
            0,
            'ERROR',
            'Error while loading DIM_LOCATIONS.',
            SQLSTATE,
            SQLERRM
        );
END;
$$;


--
-- Name: prc_load_dim_payments(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_dim_payments()
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows_affected BIGINT := 0;
BEGIN
    INSERT INTO bl_dm.dim_payments AS d (
        payment_surr_id,
        payment_src_id,
        payment_type,
        source_system,
        source_entity,
        insert_dt,
        update_dt
    )
    SELECT
        s.payment_id,
        TRIM(s.payment_src_id),
        COALESCE(NULLIF(TRIM(s.payment_type), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(s.source_system), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(s.source_entity), ''), 'N/A'),
        COALESCE(s.insert_dt, CURRENT_DATE),
        COALESCE(s.update_dt, CURRENT_DATE)
    FROM bl_3nf.ce_payments s
    WHERE s.payment_id <> -1

    ON CONFLICT (payment_surr_id) DO UPDATE
    SET
        payment_src_id = EXCLUDED.payment_src_id,
        payment_type   = EXCLUDED.payment_type,
        source_system  = EXCLUDED.source_system,
        source_entity  = EXCLUDED.source_entity,
        update_dt      = CURRENT_DATE
    WHERE ROW(
        d.payment_src_id,
        d.payment_type,
        d.source_system,
        d.source_entity
    ) IS DISTINCT FROM ROW(
        EXCLUDED.payment_src_id,
        EXCLUDED.payment_type,
        EXCLUDED.source_system,
        EXCLUDED.source_entity
    );

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_dim_payments',
        'bl_dm.dim_payments',
        v_rows_affected,
        'SUCCESS',
        'DIM_PAYMENTS loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_dim_payments',
            'bl_dm.dim_payments',
            0,
            'ERROR',
            'Error while loading DIM_PAYMENTS.',
            SQLSTATE,
            SQLERRM
        );
END;
$$;


--
-- Name: prc_load_dim_products(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_dim_products()
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_product       bl_cl.ty_dim_product_row;
    v_rows_affected BIGINT := 0;
    v_current_rows  BIGINT := 0;
BEGIN
    /*
      Cursor FOR LOOP:
      The query automatically creates and processes a cursor.
      v_product is a variable based on the custom composite type.
    */
    FOR v_product IN
        SELECT *
        FROM bl_cl.fn_get_dim_product_rows()
    LOOP
        INSERT INTO bl_dm.dim_products AS d (
            product_surr_id,
            product_src_id,
            product_name,
            category,
            sub_category,
            source_system,
            source_entity,
            insert_dt,
            update_dt
        )
        VALUES (
            v_product.product_surr_id,
            v_product.product_src_id,
            v_product.product_name,
            v_product.category,
            v_product.sub_category,
            v_product.source_system,
            v_product.source_entity,
            v_product.insert_dt,
            v_product.update_dt
        )

        ON CONFLICT (product_surr_id) DO UPDATE
        SET
            product_src_id = EXCLUDED.product_src_id,
            product_name   = EXCLUDED.product_name,
            category       = EXCLUDED.category,
            sub_category   = EXCLUDED.sub_category,
            source_system  = EXCLUDED.source_system,
            source_entity  = EXCLUDED.source_entity,
            update_dt      = CURRENT_DATE

        WHERE ROW(
            d.product_src_id,
            d.product_name,
            d.category,
            d.sub_category,
            d.source_system,
            d.source_entity
        ) IS DISTINCT FROM ROW(
            EXCLUDED.product_src_id,
            EXCLUDED.product_name,
            EXCLUDED.category,
            EXCLUDED.sub_category,
            EXCLUDED.source_system,
            EXCLUDED.source_entity
        );

        GET DIAGNOSTICS v_current_rows = ROW_COUNT;
        v_rows_affected := v_rows_affected + v_current_rows;
    END LOOP;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_dim_products',
        'bl_dm.dim_products',
        v_rows_affected,
        'SUCCESS',
        'DIM_PRODUCTS loaded successfully using composite type and cursor FOR LOOP.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_dim_products',
            'bl_dm.dim_products',
            0,
            'ERROR',
            'Error while loading DIM_PRODUCTS.',
            SQLSTATE,
            SQLERRM
        );
END;
$$;


--
-- Name: prc_load_dim_returned(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_dim_returned()
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows_affected BIGINT := 0;
BEGIN
    INSERT INTO bl_dm.dim_returned AS d (
        returned_surr_id,
        returned_src_id,
        returned,
        source_system,
        source_entity,
        insert_dt,
        update_dt
    )
    SELECT
        s.returned_id,
        TRIM(s.returned_src_id),
        COALESCE(NULLIF(TRIM(s.returned), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(s.source_system), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(s.source_entity), ''), 'N/A'),
        COALESCE(s.insert_dt, CURRENT_DATE),
        COALESCE(s.update_dt, CURRENT_DATE)
    FROM bl_3nf.ce_returned s
    WHERE s.returned_id <> -1

    ON CONFLICT (returned_surr_id) DO UPDATE
    SET
        returned_src_id = EXCLUDED.returned_src_id,
        returned        = EXCLUDED.returned,
        source_system   = EXCLUDED.source_system,
        source_entity   = EXCLUDED.source_entity,
        update_dt       = CURRENT_DATE
    WHERE ROW(
        d.returned_src_id,
        d.returned,
        d.source_system,
        d.source_entity
    ) IS DISTINCT FROM ROW(
        EXCLUDED.returned_src_id,
        EXCLUDED.returned,
        EXCLUDED.source_system,
        EXCLUDED.source_entity
    );

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_dim_returned',
        'bl_dm.dim_returned',
        v_rows_affected,
        'SUCCESS',
        'DIM_RETURNED loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_dim_returned',
            'bl_dm.dim_returned',
            0,
            'ERROR',
            'Error while loading DIM_RETURNED.',
            SQLSTATE,
            SQLERRM
        );
END;
$$;


--
-- Name: prc_load_dim_ship_modes(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_dim_ship_modes()
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows_affected BIGINT := 0;
BEGIN
    INSERT INTO bl_dm.dim_ship_modes AS d (
        ship_mode_surr_id,
        ship_mode_src_id,
        ship_mode,
        source_system,
        source_entity,
        insert_dt,
        update_dt
    )
    SELECT
        s.ship_mode_id,
        TRIM(s.ship_mode_src_id),
        COALESCE(NULLIF(TRIM(s.ship_mode), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(s.source_system), ''), 'N/A'),
        COALESCE(NULLIF(TRIM(s.source_entity), ''), 'N/A'),
        COALESCE(s.insert_dt, CURRENT_DATE),
        COALESCE(s.update_dt, CURRENT_DATE)
    FROM bl_3nf.ce_ship_modes s
    WHERE s.ship_mode_id <> -1

    ON CONFLICT (ship_mode_surr_id) DO UPDATE
    SET
        ship_mode_src_id = EXCLUDED.ship_mode_src_id,
        ship_mode        = EXCLUDED.ship_mode,
        source_system    = EXCLUDED.source_system,
        source_entity    = EXCLUDED.source_entity,
        update_dt        = CURRENT_DATE
    WHERE ROW(
        d.ship_mode_src_id,
        d.ship_mode,
        d.source_system,
        d.source_entity
    ) IS DISTINCT FROM ROW(
        EXCLUDED.ship_mode_src_id,
        EXCLUDED.ship_mode,
        EXCLUDED.source_system,
        EXCLUDED.source_entity
    );

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_dim_ship_modes',
        'bl_dm.dim_ship_modes',
        v_rows_affected,
        'SUCCESS',
        'DIM_SHIP_MODES loaded successfully.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_dim_ship_modes',
            'bl_dm.dim_ship_modes',
            0,
            'ERROR',
            'Error while loading DIM_SHIP_MODES.',
            SQLSTATE,
            SQLERRM
        );
END;
$$;


--
-- Name: prc_load_dim_time_day(); Type: PROCEDURE; Schema: bl_cl; Owner: -
--

CREATE PROCEDURE bl_cl.prc_load_dim_time_day()
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_sql           TEXT;
    v_rows_affected BIGINT := 0;
BEGIN
    /*
      Dynamic SQL is used to load the calendar dimension
      from the available cash and card sales staging sources.
    */
    v_sql := $sql$
        INSERT INTO bl_dm.dim_time_day AS d (
            date_surr_id,
            date,
            day_of_week,
            day_name,
            month,
            month_name,
            quarter,
            year,
            is_weekend
        )
        SELECT
            TO_CHAR(src.calendar_date, 'YYYYMMDD')::BIGINT AS date_surr_id,
            src.calendar_date AS date,
            EXTRACT(ISODOW FROM src.calendar_date)::INTEGER AS day_of_week,
            TO_CHAR(src.calendar_date, 'FMDay')::VARCHAR AS day_name,
            EXTRACT(MONTH FROM src.calendar_date)::INTEGER AS month,
            TO_CHAR(src.calendar_date, 'FMMonth')::VARCHAR AS month_name,
            EXTRACT(QUARTER FROM src.calendar_date)::INTEGER AS quarter,
            EXTRACT(YEAR FROM src.calendar_date)::INTEGER AS year,
            CASE
                WHEN EXTRACT(ISODOW FROM src.calendar_date) IN (6, 7)
                    THEN 1
                ELSE 0
            END AS is_weekend
        FROM (
            SELECT DISTINCT order_date AS calendar_date
            FROM sa_cash_sales.src_cash_sales
            WHERE order_date IS NOT NULL

            UNION

            SELECT DISTINCT ship_date AS calendar_date
            FROM sa_cash_sales.src_cash_sales
            WHERE ship_date IS NOT NULL

            UNION

            SELECT DISTINCT order_date AS calendar_date
            FROM sa_card_sales.src_card_sales
            WHERE order_date IS NOT NULL

            UNION

            SELECT DISTINCT ship_date AS calendar_date
            FROM sa_card_sales.src_card_sales
            WHERE ship_date IS NOT NULL
        ) src

        ON CONFLICT (date_surr_id) DO UPDATE
        SET
            date        = EXCLUDED.date,
            day_of_week = EXCLUDED.day_of_week,
            day_name    = EXCLUDED.day_name,
            month       = EXCLUDED.month,
            month_name  = EXCLUDED.month_name,
            quarter     = EXCLUDED.quarter,
            year        = EXCLUDED.year,
            is_weekend  = EXCLUDED.is_weekend

        WHERE ROW(
            d.date,
            d.day_of_week,
            d.day_name,
            d.month,
            d.month_name,
            d.quarter,
            d.year,
            d.is_weekend
        ) IS DISTINCT FROM ROW(
            EXCLUDED.date,
            EXCLUDED.day_of_week,
            EXCLUDED.day_name,
            EXCLUDED.month,
            EXCLUDED.month_name,
            EXCLUDED.quarter,
            EXCLUDED.year,
            EXCLUDED.is_weekend
        );
    $sql$;

    EXECUTE v_sql;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    CALL bl_cl.prc_insert_load_log(
        'prc_load_dim_time_day',
        'bl_dm.dim_time_day',
        v_rows_affected,
        'SUCCESS',
        'DIM_TIME_DAY loaded successfully using dynamic SQL EXECUTE.',
        NULL,
        NULL
    );

EXCEPTION
    WHEN OTHERS THEN
        CALL bl_cl.prc_insert_load_log(
            'prc_load_dim_time_day',
            'bl_dm.dim_time_day',
            0,
            'ERROR',
            'Error while loading DIM_TIME_DAY.',
            SQLSTATE,
            SQLERRM
        );
END;
$_$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bkp_ce_locations_20260804; Type: TABLE; Schema: bl_cl; Owner: -
--

CREATE TABLE bl_cl.bkp_ce_locations_20260804 (
    backup_id bigint NOT NULL,
    backup_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    backup_reason text NOT NULL,
    location_id bigint,
    location_src_id character varying,
    country character varying,
    city character varying,
    state character varying,
    postal_code character varying,
    region character varying,
    source_system character varying,
    source_entity character varying,
    insert_dt date,
    update_dt date,
    source_id character varying
);


--
-- Name: bkp_ce_locations_20260804_backup_id_seq; Type: SEQUENCE; Schema: bl_cl; Owner: -
--

CREATE SEQUENCE bl_cl.bkp_ce_locations_20260804_backup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bkp_ce_locations_20260804_backup_id_seq; Type: SEQUENCE OWNED BY; Schema: bl_cl; Owner: -
--

ALTER SEQUENCE bl_cl.bkp_ce_locations_20260804_backup_id_seq OWNED BY bl_cl.bkp_ce_locations_20260804.backup_id;


--
-- Name: load_log; Type: TABLE; Schema: bl_cl; Owner: -
--

CREATE TABLE bl_cl.load_log (
    log_id bigint NOT NULL,
    log_datetime timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    procedure_name character varying(255) NOT NULL,
    target_table character varying(255),
    rows_affected bigint,
    status character varying(50) NOT NULL,
    message text,
    error_code character varying(50),
    error_message text
);


--
-- Name: load_log_log_id_seq; Type: SEQUENCE; Schema: bl_cl; Owner: -
--

CREATE SEQUENCE bl_cl.load_log_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: load_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: bl_cl; Owner: -
--

ALTER SEQUENCE bl_cl.load_log_log_id_seq OWNED BY bl_cl.load_log.log_id;


--
-- Name: dim_customers_scd; Type: TABLE; Schema: bl_dm; Owner: -
--

CREATE TABLE bl_dm.dim_customers_scd (
    customer_surr_id bigint NOT NULL,
    customer_src_id character varying,
    customer_name character varying,
    customer_segment character varying,
    source_system character varying,
    source_entity character varying,
    start_dt date,
    end_dt date,
    is_active character varying(1),
    insert_dt date
);


--
-- Name: dim_employees; Type: TABLE; Schema: bl_dm; Owner: -
--

CREATE TABLE bl_dm.dim_employees (
    employee_surr_id bigint NOT NULL,
    employee_src_id character varying,
    employee_name character varying,
    source_system character varying,
    source_entity character varying,
    insert_dt date,
    update_dt date
);


--
-- Name: dim_locations; Type: TABLE; Schema: bl_dm; Owner: -
--

CREATE TABLE bl_dm.dim_locations (
    location_surr_id bigint NOT NULL,
    location_src_id character varying,
    country character varying,
    city character varying,
    state character varying,
    postal_code character varying,
    region character varying,
    source_system character varying,
    source_entity character varying,
    insert_dt date,
    update_dt date
);


--
-- Name: dim_payments; Type: TABLE; Schema: bl_dm; Owner: -
--

CREATE TABLE bl_dm.dim_payments (
    payment_surr_id bigint NOT NULL,
    payment_src_id character varying,
    payment_type character varying,
    source_system character varying,
    source_entity character varying,
    insert_dt date,
    update_dt date
);


--
-- Name: dim_products; Type: TABLE; Schema: bl_dm; Owner: -
--

CREATE TABLE bl_dm.dim_products (
    product_surr_id bigint NOT NULL,
    product_src_id character varying,
    product_name character varying,
    category character varying,
    sub_category character varying,
    source_system character varying,
    source_entity character varying,
    insert_dt date,
    update_dt date
);


--
-- Name: dim_returned; Type: TABLE; Schema: bl_dm; Owner: -
--

CREATE TABLE bl_dm.dim_returned (
    returned_surr_id bigint NOT NULL,
    returned_src_id character varying,
    returned character varying,
    source_system character varying,
    source_entity character varying,
    insert_dt date,
    update_dt date
);


--
-- Name: dim_ship_modes; Type: TABLE; Schema: bl_dm; Owner: -
--

CREATE TABLE bl_dm.dim_ship_modes (
    ship_mode_surr_id bigint NOT NULL,
    ship_mode_src_id character varying,
    ship_mode character varying,
    source_system character varying,
    source_entity character varying,
    insert_dt date,
    update_dt date
);


--
-- Name: dim_time_day; Type: TABLE; Schema: bl_dm; Owner: -
--

CREATE TABLE bl_dm.dim_time_day (
    date_surr_id bigint NOT NULL,
    date date,
    day_of_week integer,
    day_name character varying,
    month integer,
    month_name character varying,
    quarter integer,
    year integer,
    is_weekend integer
);


--
-- Name: fct_sales_dd; Type: TABLE; Schema: bl_dm; Owner: -
--

CREATE TABLE bl_dm.fct_sales_dd (
    customer_surr_id bigint,
    location_surr_id bigint,
    product_surr_id bigint,
    employee_surr_id bigint,
    order_date_surr_id bigint,
    ship_date_surr_id bigint,
    payment_surr_id bigint,
    ship_mode_surr_id bigint,
    returned_surr_id bigint,
    order_id character varying,
    payment_id character varying,
    sales numeric,
    quantity integer,
    discount numeric,
    profit numeric,
    profit_ratio numeric,
    insert_dt date,
    update_dt date
);


--
-- Name: bkp_ce_locations_20260804 backup_id; Type: DEFAULT; Schema: bl_cl; Owner: -
--

ALTER TABLE ONLY bl_cl.bkp_ce_locations_20260804 ALTER COLUMN backup_id SET DEFAULT nextval('bl_cl.bkp_ce_locations_20260804_backup_id_seq'::regclass);


--
-- Name: load_log log_id; Type: DEFAULT; Schema: bl_cl; Owner: -
--

ALTER TABLE ONLY bl_cl.load_log ALTER COLUMN log_id SET DEFAULT nextval('bl_cl.load_log_log_id_seq'::regclass);


--
-- Name: bkp_ce_locations_20260804 bkp_ce_locations_20260804_pkey; Type: CONSTRAINT; Schema: bl_cl; Owner: -
--

ALTER TABLE ONLY bl_cl.bkp_ce_locations_20260804
    ADD CONSTRAINT bkp_ce_locations_20260804_pkey PRIMARY KEY (backup_id);


--
-- Name: load_log load_log_pkey; Type: CONSTRAINT; Schema: bl_cl; Owner: -
--

ALTER TABLE ONLY bl_cl.load_log
    ADD CONSTRAINT load_log_pkey PRIMARY KEY (log_id);


--
-- Name: dim_customers_scd dim_customers_scd_pkey; Type: CONSTRAINT; Schema: bl_dm; Owner: -
--

ALTER TABLE ONLY bl_dm.dim_customers_scd
    ADD CONSTRAINT dim_customers_scd_pkey PRIMARY KEY (customer_surr_id);


--
-- Name: dim_employees dim_employees_pkey; Type: CONSTRAINT; Schema: bl_dm; Owner: -
--

ALTER TABLE ONLY bl_dm.dim_employees
    ADD CONSTRAINT dim_employees_pkey PRIMARY KEY (employee_surr_id);


--
-- Name: dim_locations dim_locations_pkey; Type: CONSTRAINT; Schema: bl_dm; Owner: -
--

ALTER TABLE ONLY bl_dm.dim_locations
    ADD CONSTRAINT dim_locations_pkey PRIMARY KEY (location_surr_id);


--
-- Name: dim_payments dim_payments_pkey; Type: CONSTRAINT; Schema: bl_dm; Owner: -
--

ALTER TABLE ONLY bl_dm.dim_payments
    ADD CONSTRAINT dim_payments_pkey PRIMARY KEY (payment_surr_id);


--
-- Name: dim_products dim_products_pkey; Type: CONSTRAINT; Schema: bl_dm; Owner: -
--

ALTER TABLE ONLY bl_dm.dim_products
    ADD CONSTRAINT dim_products_pkey PRIMARY KEY (product_surr_id);


--
-- Name: dim_returned dim_returned_pkey; Type: CONSTRAINT; Schema: bl_dm; Owner: -
--

ALTER TABLE ONLY bl_dm.dim_returned
    ADD CONSTRAINT dim_returned_pkey PRIMARY KEY (returned_surr_id);


--
-- Name: dim_ship_modes dim_ship_modes_pkey; Type: CONSTRAINT; Schema: bl_dm; Owner: -
--

ALTER TABLE ONLY bl_dm.dim_ship_modes
    ADD CONSTRAINT dim_ship_modes_pkey PRIMARY KEY (ship_mode_surr_id);


--
-- Name: dim_time_day dim_time_day_pkey; Type: CONSTRAINT; Schema: bl_dm; Owner: -
--

ALTER TABLE ONLY bl_dm.dim_time_day
    ADD CONSTRAINT dim_time_day_pkey PRIMARY KEY (date_surr_id);


--
-- Name: ix_dim_locations_src_id; Type: INDEX; Schema: bl_dm; Owner: -
--

CREATE INDEX ix_dim_locations_src_id ON bl_dm.dim_locations USING btree (btrim((location_src_id)::text));


--
-- Name: ux_dim_customers_scd_one_active; Type: INDEX; Schema: bl_dm; Owner: -
--

CREATE UNIQUE INDEX ux_dim_customers_scd_one_active ON bl_dm.dim_customers_scd USING btree (btrim((customer_src_id)::text)) WHERE ((customer_surr_id <> '-1'::integer) AND (upper(btrim((COALESCE(is_active, ''::character varying))::text)) = 'Y'::text));


--
-- Name: ux_dim_customers_scd_version; Type: INDEX; Schema: bl_dm; Owner: -
--

CREATE UNIQUE INDEX ux_dim_customers_scd_version ON bl_dm.dim_customers_scd USING btree (btrim((customer_src_id)::text), start_dt) WHERE (customer_surr_id <> '-1'::integer);


--
-- Name: ux_dim_employees_src_id; Type: INDEX; Schema: bl_dm; Owner: -
--

CREATE UNIQUE INDEX ux_dim_employees_src_id ON bl_dm.dim_employees USING btree (btrim((employee_src_id)::text)) WHERE (employee_surr_id <> '-1'::integer);


--
-- Name: ux_dim_payments_src_id; Type: INDEX; Schema: bl_dm; Owner: -
--

CREATE UNIQUE INDEX ux_dim_payments_src_id ON bl_dm.dim_payments USING btree (btrim((payment_src_id)::text)) WHERE (payment_surr_id <> '-1'::integer);


--
-- Name: ux_dim_products_src_id; Type: INDEX; Schema: bl_dm; Owner: -
--

CREATE UNIQUE INDEX ux_dim_products_src_id ON bl_dm.dim_products USING btree (btrim((product_src_id)::text)) WHERE (product_surr_id <> '-1'::integer);


--
-- Name: ux_dim_returned_src_id; Type: INDEX; Schema: bl_dm; Owner: -
--

CREATE UNIQUE INDEX ux_dim_returned_src_id ON bl_dm.dim_returned USING btree (btrim((returned_src_id)::text)) WHERE (returned_surr_id <> '-1'::integer);


--
-- Name: ux_dim_ship_modes_src_id; Type: INDEX; Schema: bl_dm; Owner: -
--

CREATE UNIQUE INDEX ux_dim_ship_modes_src_id ON bl_dm.dim_ship_modes USING btree (btrim((ship_mode_src_id)::text)) WHERE (ship_mode_surr_id <> '-1'::integer);


--
-- Name: ux_dim_time_day_date; Type: INDEX; Schema: bl_dm; Owner: -
--

CREATE UNIQUE INDEX ux_dim_time_day_date ON bl_dm.dim_time_day USING btree (date) WHERE (date_surr_id <> '-1'::integer);


--
-- Name: SCHEMA bl_cl; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA bl_cl TO bl_cl;


--
-- Name: SCHEMA bl_dm; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA bl_dm TO bl_cl;


--
-- Name: FUNCTION fn_get_customer_scd_changes(); Type: ACL; Schema: bl_cl; Owner: -
--

GRANT ALL ON FUNCTION bl_cl.fn_get_customer_scd_changes() TO bl_cl;


--
-- Name: FUNCTION fn_get_new_ce_employees(); Type: ACL; Schema: bl_cl; Owner: -
--

GRANT ALL ON FUNCTION bl_cl.fn_get_new_ce_employees() TO bl_cl;


--
-- Name: FUNCTION fn_get_new_ce_locations(); Type: ACL; Schema: bl_cl; Owner: -
--

GRANT ALL ON FUNCTION bl_cl.fn_get_new_ce_locations() TO bl_cl;


--
-- Name: FUNCTION fn_get_new_ce_payments(); Type: ACL; Schema: bl_cl; Owner: -
--

GRANT ALL ON FUNCTION bl_cl.fn_get_new_ce_payments() TO bl_cl;


--
-- Name: FUNCTION fn_get_new_ce_products(); Type: ACL; Schema: bl_cl; Owner: -
--

GRANT ALL ON FUNCTION bl_cl.fn_get_new_ce_products() TO bl_cl;


--
-- Name: FUNCTION fn_get_new_ce_returned(); Type: ACL; Schema: bl_cl; Owner: -
--

GRANT ALL ON FUNCTION bl_cl.fn_get_new_ce_returned() TO bl_cl;


--
-- Name: FUNCTION fn_get_new_ce_ship_modes(); Type: ACL; Schema: bl_cl; Owner: -
--

GRANT ALL ON FUNCTION bl_cl.fn_get_new_ce_ship_modes() TO bl_cl;


--
-- Name: TABLE dim_customers_scd; Type: ACL; Schema: bl_dm; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bl_dm.dim_customers_scd TO bl_cl;


--
-- Name: TABLE dim_employees; Type: ACL; Schema: bl_dm; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bl_dm.dim_employees TO bl_cl;


--
-- Name: TABLE dim_locations; Type: ACL; Schema: bl_dm; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bl_dm.dim_locations TO bl_cl;


--
-- Name: TABLE dim_payments; Type: ACL; Schema: bl_dm; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bl_dm.dim_payments TO bl_cl;


--
-- Name: TABLE dim_products; Type: ACL; Schema: bl_dm; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bl_dm.dim_products TO bl_cl;


--
-- Name: TABLE dim_returned; Type: ACL; Schema: bl_dm; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bl_dm.dim_returned TO bl_cl;


--
-- Name: TABLE dim_ship_modes; Type: ACL; Schema: bl_dm; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bl_dm.dim_ship_modes TO bl_cl;


--
-- Name: TABLE dim_time_day; Type: ACL; Schema: bl_dm; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bl_dm.dim_time_day TO bl_cl;


--
-- Name: TABLE fct_sales_dd; Type: ACL; Schema: bl_dm; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE bl_dm.fct_sales_dd TO bl_cl;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: bl_cl; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA bl_cl GRANT ALL ON FUNCTIONS TO bl_cl;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: bl_dm; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA bl_dm GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES TO bl_cl;


--
-- PostgreSQL database dump complete
--

\unrestrict PTlENj67iTMOPwYhRWn4fRIYthj2JyTg3qgbhTycIRP5e1nC4NZ50xzFmPn4R9g

