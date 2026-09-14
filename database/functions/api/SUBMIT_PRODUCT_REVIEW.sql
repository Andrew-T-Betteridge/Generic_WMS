CREATE OR REPLACE FUNCTION api.SUBMIT_PRODUCT_REVIEW(p_client_id VARCHAR,p_slug VARCHAR,p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE v_product VARCHAR; v_id UUID; v_rating INTEGER; v_email TEXT;
BEGIN
 SELECT PRODUCT_ID INTO v_product FROM core.PRODUCT WHERE CLIENT_ID=p_client_id AND SLUG=p_slug AND ACTIVE=TRUE; IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_NOT_FOUND'; END IF;
 v_rating:=(p_payload->>'rating')::integer; v_email:=LOWER(NULLIF(TRIM(p_payload->>'email'),''));
 IF v_rating NOT BETWEEN 1 AND 5 OR v_email IS NULL OR position('@' in v_email)<2 OR NULLIF(TRIM(p_payload->>'displayName'),'') IS NULL THEN RAISE EXCEPTION 'INVALID_REVIEW'; END IF;
 INSERT INTO core.PRODUCT_REVIEW(CLIENT_ID,PRODUCT_ID,SKU_ID,EMAIL,DISPLAY_NAME,RATING,REVIEW_TITLE,REVIEW_TEXT)
 VALUES(p_client_id,v_product,NULLIF(TRIM(p_payload->>'skuId'),''),v_email,LEFT(TRIM(p_payload->>'displayName'),100),v_rating,LEFT(NULLIF(TRIM(p_payload->>'title'),''),200),NULLIF(TRIM(p_payload->>'text'),'')) RETURNING REVIEW_ID INTO v_id;
 RETURN jsonb_build_object('reviewId',v_id,'status','PENDING');
END; $$;
