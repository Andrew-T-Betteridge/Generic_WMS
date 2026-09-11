CREATE OR REPLACE FUNCTION core.EVALUATE_DELIVERY_HOLD (
    p_client_id VARCHAR,
    p_container_id VARCHAR,
    p_user_id VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (
    RESULT_STATUS VARCHAR,
    RESULT_HOLD_STATUS VARCHAR,
    RESULT_MESSAGE TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_container RECORD;
    v_enabled BOOLEAN := TRUE;
    v_config_reason VARCHAR(250);
    v_delivery_class VARCHAR(30);
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    SELECT *
    INTO v_container
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID = p_client_id
      AND CONTAINER_ID = p_container_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT 'ERROR'::VARCHAR, NULL::VARCHAR,
               'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    v_delivery_class := UPPER(COALESCE(v_container.DELIVERY_CLASS,'STANDARD'));

    -- Only carrier fulfilment is controlled here.
    -- Local delivery / collection / route delivery can still proceed.
    IF UPPER(COALESCE(v_container.FULFILMENT_METHOD,'CARRIER')) <> 'CARRIER' THEN
        UPDATE core.ORDER_CONTAINER
        SET HOLD_STATUS='NONE',
            HOLD_REASON=NULL,
            HOLD_DSTAMP=NULL,
            HOLD_SOURCE=NULL
        WHERE CLIENT_ID=p_client_id
          AND CONTAINER_ID=p_container_id
          AND HOLD_SOURCE='DELIVERY_CLASS_CONTROL';

        RETURN QUERY
        SELECT 'ALLOWED'::VARCHAR, 'NONE'::VARCHAR,
               'Container is not using carrier fulfilment.'::TEXT;
        RETURN;
    END IF;

    SELECT
        d.CARRIER_DESPATCH_ENABLED,
        d.HOLD_REASON
    INTO
        v_enabled,
        v_config_reason
    FROM config.DELIVERY_CLASS_CONTROL d
    WHERE d.CLIENT_ID = p_client_id
      AND UPPER(d.DELIVERY_CLASS) = v_delivery_class;

    -- No row means no restriction for that class.
    IF NOT FOUND THEN
        v_enabled := TRUE;
        v_config_reason := NULL;
    END IF;

    IF NOT COALESCE(v_enabled,TRUE) THEN
        UPDATE core.ORDER_CONTAINER
        SET HOLD_STATUS='DELIVERY_HOLD',
            HOLD_REASON=COALESCE(
                NULLIF(v_config_reason,''),
                v_delivery_class || ' carrier despatch is currently disabled.'
            ),
            HOLD_DSTAMP=now(),
            HOLD_SOURCE='DELIVERY_CLASS_CONTROL',
            RELEASE_DSTAMP=NULL,
            RELEASED_BY=NULL
        WHERE CLIENT_ID=p_client_id
          AND CONTAINER_ID=p_container_id;

        INSERT INTO audit.RULE_DECISION_LOG (
            CLIENT_ID,
            ENGINE_NAME,
            ENTITY_TYPE,
            ENTITY_ID,
            MATCHED,
            DECISION,
            REASON,
            DETAIL
        )
        VALUES (
            p_client_id,
            'DELIVERY_HOLD',
            'ORDER_CONTAINER',
            p_container_id,
            TRUE,
            'HELD',
            COALESCE(
                NULLIF(v_config_reason,''),
                v_delivery_class || ' carrier despatch is currently disabled.'
            ),
            jsonb_build_object(
                'delivery_class', v_delivery_class,
                'fulfilment_method', 'CARRIER',
                'control_source', 'DELIVERY_CLASS_CONTROL',
                'user_id', v_user
            )
        );

        RETURN QUERY
        SELECT
            'HELD'::VARCHAR,
            'DELIVERY_HOLD'::VARCHAR,
            COALESCE(
                NULLIF(v_config_reason,''),
                v_delivery_class || ' carrier despatch is currently disabled.'
            )::TEXT;
        RETURN;
    END IF;

    -- Never remove a manual/weather/other hold here.
    IF v_container.HOLD_STATUS <> 'NONE'
       AND COALESCE(v_container.HOLD_SOURCE,'') <> 'DELIVERY_CLASS_CONTROL'
    THEN
        RETURN QUERY
        SELECT
            'HELD'::VARCHAR,
            v_container.HOLD_STATUS::VARCHAR,
            COALESCE(v_container.HOLD_REASON,'Container is held.')::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET HOLD_STATUS='NONE',
        HOLD_REASON=NULL,
        HOLD_DSTAMP=NULL,
        HOLD_SOURCE=NULL
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_container_id
      AND (
          HOLD_SOURCE='DELIVERY_CLASS_CONTROL'
          OR HOLD_STATUS='NONE'
      );

    RETURN QUERY
    SELECT
        'ALLOWED'::VARCHAR,
        'NONE'::VARCHAR,
        'Carrier despatch is enabled for this delivery class.'::TEXT;
END;
$$;
