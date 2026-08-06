CREATE OR REPLACE PROCEDURE bl_cl.prc_insert_load_log(IN p_procedure_name character varying, IN p_target_table character varying, IN p_rows_affected bigint, IN p_status character varying, IN p_message text, IN p_error_code character varying DEFAULT NULL::character varying, IN p_error_message text DEFAULT NULL::text)
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

CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_employees()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_locations()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_payments()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_products()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_returned()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_ship_modes()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

CREATE OR REPLACE PROCEDURE bl_cl.prc_load_dim_time_day()
 LANGUAGE plpgsql
AS $procedure$
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
$procedure$

