CREATE OR REPLACE FUNCTION core.SET_DELIVERY_HOLD (
    p_client_id VARCHAR,
    p_container_id VARCHAR,
    p_hold_status VARCHAR,
    p_reason VARCHAR,
    p_source VARCHAR DEFAULT 'MANUAL',
    p_user_id VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (RESULT_STATUS VARCHAR, RESULT_MESSAGE TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    IF p_reason IS NULL OR btrim(p_reason)='' THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,'A hold requires a reason.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET HOLD_STATUS=UPPER(COALESCE(NULLIF(p_hold_status,''),'DELIVERY_HOLD')),
        HOLD_REASON=LEFT(p_reason,250),
        HOLD_DSTAMP=now(),
        HOLD_SOURCE=UPPER(COALESCE(NULLIF(p_source,''),'MANUAL')),
        RELEASE_DSTAMP=NULL,
        RELEASED_BY=NULL
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    INSERT INTO audit.RULE_DECISION_LOG
        (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
    VALUES
        (p_client_id,'DELIVERY_HOLD','ORDER_CONTAINER',p_container_id,TRUE,'HELD',
         p_reason,jsonb_build_object('source',p_source,'user_id',v_user));

    RETURN QUERY SELECT 'HELD'::VARCHAR,'Delivery hold applied.'::TEXT;
END;
$$;
