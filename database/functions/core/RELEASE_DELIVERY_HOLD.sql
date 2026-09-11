CREATE OR REPLACE FUNCTION core.RELEASE_DELIVERY_HOLD (
    p_client_id VARCHAR,
    p_container_id VARCHAR,
    p_reason VARCHAR,
    p_user_id VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (RESULT_STATUS VARCHAR, RESULT_MESSAGE TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    IF p_reason IS NULL OR btrim(p_reason)='' THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,'A release/override requires a reason.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET HOLD_STATUS='NONE',
        HOLD_REASON=NULL,
        HOLD_DSTAMP=NULL,
        HOLD_SOURCE='MANUAL_OVERRIDE',
        RELEASE_DSTAMP=now(),
        RELEASED_BY=v_user
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    INSERT INTO audit.RULE_DECISION_LOG
        (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
    VALUES
        (p_client_id,'DELIVERY_HOLD','ORDER_CONTAINER',p_container_id,TRUE,'RELEASED',
         p_reason,jsonb_build_object('user_id',v_user));

    RETURN QUERY SELECT 'RELEASED'::VARCHAR,'Delivery hold released.'::TEXT;
END;
$$;
