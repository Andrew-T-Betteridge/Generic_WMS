CREATE OR REPLACE FUNCTION api.GET_PRODUCT_MEDIA(p_client_id VARCHAR,p_product_id VARCHAR)
RETURNS JSONB LANGUAGE sql STABLE AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'mediaId',m.MEDIA_ID,'skuId',m.SKU_ID,'type',m.MEDIA_TYPE,'role',m.MEDIA_ROLE,
  'url',m.MEDIA_URL,'thumbnailUrl',m.THUMBNAIL_URL,'altText',m.ALT_TEXT,
  'caption',m.CAPTION,'sortSequence',m.SORT_SEQUENCE
) ORDER BY m.SORT_SEQUENCE,m.CREATED_DSTAMP),'[]'::jsonb)
FROM core.PRODUCT_MEDIA m
WHERE m.CLIENT_ID=p_client_id AND m.PRODUCT_ID=p_product_id AND m.ACTIVE=TRUE;
$$;
