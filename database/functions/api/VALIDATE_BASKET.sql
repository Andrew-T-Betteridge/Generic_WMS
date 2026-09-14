CREATE OR REPLACE FUNCTION api.VALIDATE_BASKET(p_client_id VARCHAR,p_items JSONB)
RETURNS JSONB LANGUAGE plpgsql STABLE AS $$
DECLARE v_result JSONB;
BEGIN
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
   RETURN jsonb_build_object('valid',FALSE,'errors',jsonb_build_array(jsonb_build_object('code','EMPTY_BASKET','message','Basket is empty.')),'items','[]'::jsonb);
 END IF;
 WITH requested AS (SELECT x.sku_id,x.qty FROM jsonb_to_recordset(p_items) x(sku_id VARCHAR,qty NUMERIC)),
 resolved AS (
   SELECT r.sku_id,r.qty,pv.PRODUCT_ID,p.PRODUCT_NAME,p.SLUG,p.DELIVERY_CLASS,p.CURRENCY,pv.VARIANT_NAME,pv.OPTION_VALUES,pv.WEB_PRICE,
          pv.SALE_TYPE,pv.AVAILABILITY_STATE,pv.EXPECTED_AVAILABLE_FROM,pv.EXPECTED_AVAILABLE_TO,pv.MIN_ORDER_QTY,pv.MAX_ORDER_QTY,pv.QTY_INCREMENT,
          COALESCE(a.AVAILABLE_QTY,0) AVAILABLE_QTY,
          CASE WHEN pv.SKU_ID IS NULL THEN 'SKU_NOT_FOR_SALE'
               WHEN pv.AVAILABILITY_STATE<>'AVAILABLE' THEN 'NOT_YET_AVAILABLE'
               WHEN r.qty IS NULL OR r.qty<=0 THEN 'INVALID_QTY'
               WHEN r.qty<pv.MIN_ORDER_QTY THEN 'BELOW_MIN_QTY'
               WHEN pv.MAX_ORDER_QTY IS NOT NULL AND r.qty>pv.MAX_ORDER_QTY THEN 'ABOVE_MAX_QTY'
               WHEN pv.QTY_INCREMENT>0 AND mod(r.qty-pv.MIN_ORDER_QTY,pv.QTY_INCREMENT)<>0 THEN 'INVALID_QTY_INCREMENT'
               WHEN COALESCE(a.AVAILABLE_QTY,0)<r.qty THEN 'INSUFFICIENT_STOCK' ELSE NULL END ERROR_CODE
   FROM requested r LEFT JOIN core.PRODUCT_VARIANT pv ON pv.CLIENT_ID=p_client_id AND pv.SKU_ID=r.sku_id AND pv.ACTIVE=TRUE
   LEFT JOIN core.PRODUCT p ON p.CLIENT_ID=pv.CLIENT_ID AND p.PRODUCT_ID=pv.PRODUCT_ID AND p.ACTIVE=TRUE
   LEFT JOIN api.CATALOG_VARIANT_AVAILABILITY a ON a.CLIENT_ID=pv.CLIENT_ID AND a.PRODUCT_ID=pv.PRODUCT_ID AND a.SKU_ID=pv.SKU_ID
 )
 SELECT jsonb_build_object(
   'valid',COUNT(*) FILTER(WHERE ERROR_CODE IS NOT NULL)=0,'currency',COALESCE(MAX(CURRENCY),'GBP'),
   'subtotal',COALESCE(SUM(CASE WHEN ERROR_CODE IS NULL THEN WEB_PRICE*qty ELSE 0 END),0),
   'hasStandard',COALESCE(BOOL_OR(UPPER(COALESCE(DELIVERY_CLASS,'STANDARD'))='STANDARD' AND ERROR_CODE IS NULL),FALSE),
   'hasLivestock',COALESCE(BOOL_OR(UPPER(COALESCE(DELIVERY_CLASS,''))='LIVESTOCK' AND ERROR_CODE IS NULL),FALSE),
   'deliveryClasses',COALESCE(jsonb_agg(DISTINCT DELIVERY_CLASS) FILTER(WHERE ERROR_CODE IS NULL),'[]'::jsonb),
   'items',COALESCE(jsonb_agg(jsonb_build_object('skuId',sku_id,'qty',qty,'productId',PRODUCT_ID,'productName',PRODUCT_NAME,'slug',SLUG,'variantName',VARIANT_NAME,'options',OPTION_VALUES,'deliveryClass',DELIVERY_CLASS,'saleType',SALE_TYPE,'availabilityState',AVAILABILITY_STATE,'expectedAvailableFrom',EXPECTED_AVAILABLE_FROM,'expectedAvailableTo',EXPECTED_AVAILABLE_TO,'unitPrice',WEB_PRICE,'lineTotal',CASE WHEN WEB_PRICE IS NULL THEN NULL ELSE WEB_PRICE*qty END,'availableQty',AVAILABLE_QTY,'minOrderQty',MIN_ORDER_QTY,'maxOrderQty',MAX_ORDER_QTY,'qtyIncrement',QTY_INCREMENT,'valid',ERROR_CODE IS NULL,'errorCode',ERROR_CODE) ORDER BY sku_id),'[]'::jsonb),
   'errors',COALESCE(jsonb_agg(jsonb_build_object('skuId',sku_id,'code',ERROR_CODE,'message',CASE ERROR_CODE WHEN 'SKU_NOT_FOR_SALE' THEN 'This item is not currently available for sale.' WHEN 'NOT_YET_AVAILABLE' THEN 'This item is not ready for normal checkout.' WHEN 'INVALID_QTY' THEN 'Quantity must be greater than zero.' WHEN 'BELOW_MIN_QTY' THEN 'Quantity is below the minimum for this offer.' WHEN 'ABOVE_MAX_QTY' THEN 'Quantity is above the maximum for this offer.' WHEN 'INVALID_QTY_INCREMENT' THEN 'Quantity does not match this offer''s required increment.' WHEN 'INSUFFICIENT_STOCK' THEN 'Requested quantity is not currently available.' ELSE 'Basket validation failed.' END)) FILTER(WHERE ERROR_CODE IS NOT NULL),'[]'::jsonb)
 ) INTO v_result FROM resolved;
 RETURN v_result;
END; $$;
