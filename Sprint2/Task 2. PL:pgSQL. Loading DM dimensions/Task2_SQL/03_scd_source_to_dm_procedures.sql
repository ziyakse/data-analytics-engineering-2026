CREATE OR REPLACE FUNCTION bl_cl.fn_get_customer_scd_changes()
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

CREATE OR REPLACE PROCEDURE bl_cl.prc_load_ce_customers_scd()
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

CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_customers_scd()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

