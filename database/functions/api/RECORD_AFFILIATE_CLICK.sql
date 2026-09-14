CREATE OR REPLACE FUNCTION api.RECORD_AFFILIATE_CLICK(p_client_id VARCHAR,p_link_id UUID,p_payload JSONB DEFAULT '{}'::jsonb)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE v_url TEXT; v_click UUID;
BEGIN
 SELECT DESTINATION_URL INTO v_url FROM core.PRODUCT_AFFILIATE_LINK WHERE CLIENT_ID=p_client_id AND LINK_ID=p_link_id AND ACTIVE=TRUE;
 IF NOT FOUND THEN RAISE EXCEPTION 'AFFILIATE_LINK_NOT_FOUND'; END IF;
 INSERT INTO audit.AFFILIATE_CLICK(CLIENT_ID,LINK_ID,SESSION_ID,SOURCE,REFERRER,USER_AGENT)
 VALUES(p_client_id,p_link_id,NULLIF(TRIM(p_payload->>'sessionId'),''),NULLIF(TRIM(p_payload->>'source'),''),NULLIF(TRIM(p_payload->>'referrer'),''),NULLIF(TRIM(p_payload->>'userAgent'),''))
 RETURNING CLICK_ID INTO v_click;
 RETURN jsonb_build_object('clickId',v_click,'destinationUrl',v_url);
END; $$;
