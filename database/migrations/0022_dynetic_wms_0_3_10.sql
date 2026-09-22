\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION api.GET_DELIVERY_OPTIONS(p_client_id VARCHAR,p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql STABLE AS $$
DECLARE v_basket JSONB; v_options JSONB:='[]'::jsonb; v_postcode TEXT; v_country TEXT; v_subtotal NUMERIC; v_has_livestock BOOLEAN; v_carrier_enabled BOOLEAN:=TRUE; z RECORD;
BEGIN
 v_basket:=api.VALIDATE_BASKET(p_client_id,COALESCE(p_payload->'items','[]'::jsonb));
 IF NOT COALESCE((v_basket->>'valid')::boolean,FALSE) THEN RETURN jsonb_build_object('valid',FALSE,'basket',v_basket,'fulfilmentOptions','[]'::jsonb); END IF;
 v_postcode:=regexp_replace(UPPER(COALESCE(p_payload#>>'{deliveryAddress,postcode}','')),'[[:space:]]','','g');
 v_country:=UPPER(COALESCE(NULLIF(TRIM(p_payload#>>'{deliveryAddress,country}'),''),'GB'));
 v_subtotal:=COALESCE((v_basket->>'subtotal')::numeric,0); v_has_livestock:=COALESCE((v_basket->>'hasLivestock')::boolean,FALSE);

 v_options:=v_options||jsonb_build_array(
   jsonb_build_object(
     'code','COLLECTION',
     'label','Collection',
     'fulfilmentMethod','COLLECTION',
     'price',0,
     'currency',v_basket->>'currency',
     'requiresManualConfirmation',FALSE
   )
 );

 FOR z IN
   SELECT *
   FROM config.DELIVERY_ZONE dz
   WHERE dz.CLIENT_ID=p_client_id
     AND dz.ACTIVE=TRUE
     AND UPPER(dz.COUNTRY)=v_country
     AND (dz.POSTCODE_PREFIX IS NULL OR v_postcode LIKE regexp_replace(UPPER(dz.POSTCODE_PREFIX),'[[:space:]]','','g')||'%')
     AND (dz.MIN_ORDER_VALUE IS NULL OR v_subtotal>=dz.MIN_ORDER_VALUE)
   ORDER BY dz.PRIORITY
 LOOP
   v_options:=v_options||jsonb_build_array(
     jsonb_build_object(
       'code',z.ZONE_ID,
       'label',z.ZONE_NAME,
       'fulfilmentMethod',z.FULFILMENT_METHOD,
       'price',z.DELIVERY_PRICE,
       'currency',z.CURRENCY,
       'requiresManualConfirmation',z.REQUIRES_MANUAL_CONFIRMATION
     )
   );
 END LOOP;

 IF v_has_livestock THEN
   SELECT CARRIER_DESPATCH_ENABLED
     INTO v_carrier_enabled
   FROM config.DELIVERY_CLASS_CONTROL
   WHERE CLIENT_ID=p_client_id
     AND UPPER(DELIVERY_CLASS)='LIVESTOCK';

   IF NOT FOUND THEN
     v_carrier_enabled:=TRUE;
   END IF;

   IF v_carrier_enabled THEN
     v_options:=v_options||jsonb_build_array(
       jsonb_build_object(
         'code','LIVESTOCK_CARRIER',
         'label','Livestock courier',
         'fulfilmentMethod','CARRIER',
         'price',NULL,
         'currency',v_basket->>'currency',
         'requiresManualConfirmation',TRUE
       )
     );
   END IF;

   v_options:=v_options||jsonb_build_array(
     jsonb_build_object(
       'code','MEET_POINT',
       'label','Meet halfway / arranged handover',
       'fulfilmentMethod','MEET_POINT',
       'price',NULL,
       'currency',v_basket->>'currency',
       'requiresManualConfirmation',TRUE
     )
   );
 ELSE
   v_options:=v_options||jsonb_build_array(
     jsonb_build_object(
       'code','STANDARD_CARRIER',
       'label','Delivery',
       'fulfilmentMethod','CARRIER',
       'price',NULL,
       'currency',v_basket->>'currency',
       'requiresManualConfirmation',TRUE
     )
   );
 END IF;

 RETURN jsonb_build_object(
   'valid',TRUE,
   'basket',v_basket,
   'fulfilmentOptions',v_options
 );
END;
$$;

UPDATE config.SYSTEM_VERSION
SET IS_CURRENT=FALSE
WHERE PRODUCT_CODE='DYNETIC_WMS'
  AND IS_CURRENT=TRUE
  AND VERSION_NUMBER <> '0.3.10';

INSERT INTO config.SYSTEM_VERSION (
    PRODUCT_CODE,
    PRODUCT_NAME,
    VERSION_NUMBER,
    VERSION_MAJOR,
    VERSION_MINOR,
    VERSION_PATCH,
    BUILD_NUMBER,
    RELEASE_CHANNEL,
    RELEASE_DATE,
    DESCRIPTION,
    IS_CURRENT
)
VALUES (
    'DYNETIC_WMS',
    'DYNETIC WMS',
    '0.3.10',
    0,
    3,
    10,
    0,
    'RELEASE',
    CURRENT_DATE,
    'Allow free collection orders to proceed without manual confirmation.',
    TRUE
)
ON CONFLICT (PRODUCT_CODE, VERSION_NUMBER)
DO UPDATE SET
    PRODUCT_NAME=EXCLUDED.PRODUCT_NAME,
    VERSION_MAJOR=EXCLUDED.VERSION_MAJOR,
    VERSION_MINOR=EXCLUDED.VERSION_MINOR,
    VERSION_PATCH=EXCLUDED.VERSION_PATCH,
    BUILD_NUMBER=EXCLUDED.BUILD_NUMBER,
    RELEASE_CHANNEL=EXCLUDED.RELEASE_CHANNEL,
    RELEASE_DATE=EXCLUDED.RELEASE_DATE,
    DESCRIPTION=EXCLUDED.DESCRIPTION,
    IS_CURRENT=TRUE;

COMMIT;