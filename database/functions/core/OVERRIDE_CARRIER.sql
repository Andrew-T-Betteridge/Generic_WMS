CREATE OR REPLACE FUNCTION core.OVERRIDE_CARRIER (
    p_client_id VARCHAR,
    p_container_id VARCHAR,
    p_carrier_id VARCHAR,
    p_service_level VARCHAR,
    p_reason VARCHAR,
    p_user_id VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (
    RESULT_STATUS VARCHAR,
    RESULT_CARRIER_ID VARCHAR,
    RESULT_SERVICE_LEVEL VARCHAR,
    RESULT_MESSAGE TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_container RECORD;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    IF p_reason IS NULL OR btrim(p_reason)='' THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,
            'A manual carrier override requires a reason.'::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_container
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM config.CARRIER_SERVICE cs
        JOIN config.CARRIER c ON c.CLIENT_ID=cs.CLIENT_ID AND c.CARRIER_ID=cs.CARRIER_ID
        WHERE cs.CLIENT_ID=p_client_id
          AND cs.CARRIER_ID=p_carrier_id
          AND cs.SERVICE_LEVEL=p_service_level
          AND cs.ACTIVE=TRUE
          AND c.ACTIVE=TRUE
    ) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,
            'Requested carrier/service is not active.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET CARRIER_ID=p_carrier_id,
        SERVICE_LEVEL=p_service_level,
        CARRIER_SELECTION_SOURCE='MANUAL_OVERRIDE',
        CARRIER_SELECTION_RULE_ID=NULL,
        CARRIER_SELECTED_DSTAMP=now(),
        CARRIER_OVERRIDE_REASON=LEFT(p_reason,250)
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    UPDATE core.SHIPPING_MANIFEST
    SET CARRIER_ID=p_carrier_id,
        SERVICE_LEVEL=p_service_level,
        CARRIER_SELECTION_RULE_ID=NULL
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id
      AND COALESCE(SHIPPED,'N')='N';

    INSERT INTO audit.RULE_DECISION_LOG
        (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
    VALUES
        (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,TRUE,'OVERRIDDEN',
         p_reason,
         jsonb_build_object('carrier_id',p_carrier_id,'service_level',p_service_level,'user_id',v_user));

    RETURN QUERY SELECT 'OVERRIDDEN'::VARCHAR,p_carrier_id::VARCHAR,p_service_level::VARCHAR,
        format('Container %s manually assigned to %s / %s.',p_container_id,p_carrier_id,p_service_level)::TEXT;
END;
$$;
