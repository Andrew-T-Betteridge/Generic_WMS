CREATE OR REPLACE FUNCTION api.GET_CATALOG (
    p_client_id VARCHAR,
    p_category_slug VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT COALESCE(
    jsonb_agg(
        jsonb_build_object(
            'productId',x.PRODUCT_ID,
            'name',x.PRODUCT_NAME,
            'slug',x.SLUG,
            'brand',x.BRAND_NAME,
            'category',jsonb_build_object(
                'code',x.CATEGORY_CODE,
                'name',x.CATEGORY_NAME,
                'slug',x.CATEGORY_SLUG
            ),
            'shortDescription',x.SHORT_DESCRIPTION,
            'deliveryClass',x.DELIVERY_CLASS,
            'currency',x.CURRENCY,
            'fromPrice',x.FROM_PRICE,
            'toPrice',x.TO_PRICE,
            'availableQty',x.AVAILABLE_QTY,
            'featured',x.FEATURED,
            'media',x.MEDIA
        )
        ORDER BY x.SORT_SEQUENCE,x.PRODUCT_NAME
    ),
    '[]'::jsonb
)
FROM api.CATALOG_PRODUCT_LIST x
WHERE x.CLIENT_ID=p_client_id
  AND (
      p_category_slug IS NULL
      OR x.CATEGORY_SLUG=p_category_slug
  );
$$;
