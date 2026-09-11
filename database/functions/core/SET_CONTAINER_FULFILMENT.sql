CREATE OR REPLACE FUNCTION core.SET_CONTAINER_FULFILMENT (
    p_client_id VARCHAR,
    p_container_id VARCHAR,
    p_fulfilment_method VARCHAR,
    p_user_id VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (RESULT_STATUS VARCHAR, RESULT_METHOD VARCHAR, RESULT_MESSAGE TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_method VARCHAR(30) := UPPER(COALESCE(p_fulfilment_method,''));
BEGIN
    IF v_method NOT IN ('CARRIER','LOCAL_DELIVERY','COLLECTION','ROUTE_DELIVERY','MEET_POINT') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,'Unsupported fulfilment method.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET FULFILMENT_METHOD=v_method
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    -- Re-evaluate because moving livestock from CARRIER to LOCAL_DELIVERY
    -- should remove only the master carrier gate hold.
    PERFORM core.EVALUATE_DELIVERY_HOLD(p_client_id,p_container_id,p_user_id);

    RETURN QUERY SELECT 'UPDATED'::VARCHAR,v_method,
        format('Container fulfilment method set to %s.',v_method)::TEXT;
END;
$$;
