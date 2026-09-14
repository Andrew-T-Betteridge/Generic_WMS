CREATE OR REPLACE FUNCTION api.GET_PRODUCT_FAVOURITES(p_client_id VARCHAR,p_account_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'productId',p.PRODUCT_ID,
    'slug',p.SLUG,
    'productName',p.PRODUCT_NAME,
    'brandName',p.BRAND_NAME,
    'categoryCode',p.CATEGORY_CODE,
    'deliveryClass',p.DELIVERY_CLASS,
    'createdAt',f.CREATED_DSTAMP
) ORDER BY f.CREATED_DSTAMP DESC),'[]'::jsonb)
FROM core.PRODUCT_FAVOURITE f
JOIN core.PRODUCT p
  ON p.CLIENT_ID=f.CLIENT_ID AND p.PRODUCT_ID=f.PRODUCT_ID
WHERE f.CLIENT_ID=p_client_id AND f.ACCOUNT_ID=p_account_id;
$$;
