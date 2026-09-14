CREATE OR REPLACE FUNCTION api.GET_PRODUCT(p_client_id VARCHAR,p_slug VARCHAR)
RETURNS JSONB LANGUAGE sql STABLE AS $$
SELECT jsonb_build_object(
 'productId',p.PRODUCT_ID,'name',p.PRODUCT_NAME,'slug',p.SLUG,'brand',p.BRAND_NAME,'productType',p.PRODUCT_TYPE,
 'category',jsonb_build_object('code',p.CATEGORY_CODE,'name',c.CATEGORY_NAME,'slug',c.SLUG),
 'shortDescription',p.SHORT_DESCRIPTION,'description',p.DESCRIPTION,'deliveryClass',p.DELIVERY_CLASS,
 'currency',p.CURRENCY,'media',api.GET_PRODUCT_MEDIA(p.CLIENT_ID,p.PRODUCT_ID),
 'specification',p.SPECIFICATION,'searchMetadata',p.SEARCH_METADATA,
 'variants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'skuId',v.SKU_ID,'name',v.VARIANT_NAME,'options',v.OPTION_VALUES,'price',v.WEB_PRICE,
   'compareAtPrice',v.COMPARE_AT_PRICE,'availableQty',v.AVAILABLE_QTY,'available',v.AVAILABLE_QTY>0,
   'saleType',v.SALE_TYPE,'availabilityState',v.AVAILABILITY_STATE,
   'expectedAvailableFrom',v.EXPECTED_AVAILABLE_FROM,'expectedAvailableTo',v.EXPECTED_AVAILABLE_TO,
   'metadata',v.WEB_METADATA,'minOrderQty',v.MIN_ORDER_QTY,'maxOrderQty',v.MAX_ORDER_QTY,'qtyIncrement',v.QTY_INCREMENT
 ) ORDER BY v.SKU_ID) FROM api.CATALOG_VARIANT_AVAILABILITY v WHERE v.CLIENT_ID=p.CLIENT_ID AND v.PRODUCT_ID=p.PRODUCT_ID AND v.ACTIVE=TRUE),'[]'::jsonb),
 'affiliateLinks',COALESCE((SELECT jsonb_agg(jsonb_build_object('linkId',a.LINK_ID,'skuId',a.SKU_ID,'merchant',a.MERCHANT_NAME,'campaignCode',a.CAMPAIGN_CODE) ORDER BY a.SORT_SEQUENCE) FROM core.PRODUCT_AFFILIATE_LINK a WHERE a.CLIENT_ID=p.CLIENT_ID AND a.PRODUCT_ID=p.PRODUCT_ID AND a.ACTIVE=TRUE),'[]'::jsonb)
)
FROM core.PRODUCT p LEFT JOIN core.PRODUCT_CATEGORY c ON c.CLIENT_ID=p.CLIENT_ID AND c.CATEGORY_CODE=p.CATEGORY_CODE
WHERE p.CLIENT_ID=p_client_id AND p.SLUG=p_slug AND p.ACTIVE=TRUE;
$$;
