CREATE OR REPLACE FUNCTION api.SET_PRODUCT_FAVOURITE(
    p_client_id VARCHAR,p_account_id UUID,p_product_slug VARCHAR,p_favourite BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE v_product_id VARCHAR(50);
BEGIN
    SELECT PRODUCT_ID INTO v_product_id
      FROM core.PRODUCT
     WHERE CLIENT_ID=p_client_id AND SLUG=p_product_slug AND ACTIVE=TRUE;

    IF v_product_id IS NULL THEN RAISE EXCEPTION 'PRODUCT_NOT_FOUND'; END IF;

    IF p_favourite THEN
        INSERT INTO core.PRODUCT_FAVOURITE(ACCOUNT_ID,CLIENT_ID,PRODUCT_ID)
        VALUES(p_account_id,p_client_id,v_product_id)
        ON CONFLICT DO NOTHING;
    ELSE
        DELETE FROM core.PRODUCT_FAVOURITE
         WHERE ACCOUNT_ID=p_account_id AND CLIENT_ID=p_client_id AND PRODUCT_ID=v_product_id;
    END IF;

    RETURN jsonb_build_object('productId',v_product_id,'favourite',p_favourite);
END;
$$;
