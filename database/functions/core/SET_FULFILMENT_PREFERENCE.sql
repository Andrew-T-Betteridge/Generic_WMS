CREATE OR REPLACE FUNCTION core.SET_FULFILMENT_PREFERENCE (
    p_client_id VARCHAR,
    p_order_id VARCHAR,
    p_preference VARCHAR,
    p_user_id VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (RESULT_STATUS VARCHAR, RESULT_PREFERENCE VARCHAR, RESULT_MESSAGE TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_pref VARCHAR(30) := UPPER(COALESCE(p_preference,''));
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    IF v_pref NOT IN ('CONSOLIDATE','SPLIT_WHEN_REQUIRED') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,
            'Preference must be CONSOLIDATE or SPLIT_WHEN_REQUIRED.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_HEADER
    SET FULFILMENT_PREFERENCE=v_pref,
        LAST_UPDATED_BY=v_user,
        LAST_UPDATE_DATE=now()
    WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT 'UPDATED'::VARCHAR,v_pref,
        format('Order fulfilment preference set to %s.',v_pref)::TEXT;
END;
$$;
