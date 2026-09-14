CREATE OR REPLACE FUNCTION api.GET_PRODUCT (
    p_client_id VARCHAR,
    p_slug VARCHAR
)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT jsonb_build_object(
    'productId',p.PRODUCT_ID,
    'name',p.PRODUCT_NAME,
    'slug',p.SLUG,
    'brand',p.BRAND_NAME,
    'category',jsonb_build_object(
        'code',p.CATEGORY_CODE,
        'name',c.CATEGORY_NAME,
        'slug',c.SLUG
    ),
    'shortDescription',p.SHORT_DESCRIPTION,
    'description',p.DESCRIPTION,
    'deliveryClass',p.DELIVERY_CLASS,
    'currency',p.CURRENCY,
    'media',p.MEDIA,
    'specification',p.SPECIFICATION,
    'variants',COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'skuId',v.SKU_ID,
                    'name',v.VARIANT_NAME,
                    'options',v.OPTION_VALUES,
                    'price',v.WEB_PRICE,
                    'compareAtPrice',v.COMPARE_AT_PRICE,
                    'availableQty',v.AVAILABLE_QTY,
                    'available',v.AVAILABLE_QTY>0
                )
                ORDER BY pv.SORT_SEQUENCE,pv.SKU_ID
            )
            FROM core.PRODUCT_VARIANT pv
            JOIN api.CATALOG_VARIANT_AVAILABILITY v
              ON v.CLIENT_ID=pv.CLIENT_ID
             AND v.PRODUCT_ID=pv.PRODUCT_ID
             AND v.SKU_ID=pv.SKU_ID
            WHERE pv.CLIENT_ID=p.CLIENT_ID
              AND pv.PRODUCT_ID=p.PRODUCT_ID
              AND pv.ACTIVE=TRUE
        ),
        '[]'::jsonb
    )
)
FROM core.PRODUCT p
LEFT JOIN core.PRODUCT_CATEGORY c
  ON c.CLIENT_ID=p.CLIENT_ID
 AND c.CATEGORY_CODE=p.CATEGORY_CODE
WHERE p.CLIENT_ID=p_client_id
  AND p.SLUG=p_slug
  AND p.ACTIVE=TRUE;
$$;
