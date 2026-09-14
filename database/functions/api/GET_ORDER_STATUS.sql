CREATE OR REPLACE FUNCTION api.GET_ORDER_STATUS (
    p_client_id VARCHAR,
    p_order_id VARCHAR
)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT jsonb_build_object(
    'orderId',h.ORDER_ID,
    'orderDate',h.ORDER_DATE,
    'status',h.STATUS,
    'paymentStatus',h.PAYMENT_STATUS,
    'fulfilmentStatus',h.FULFILMENT_STATUS,
    'fulfilmentPreference',h.FULFILMENT_PREFERENCE,
    'dispatchMethod',h.DISPATCH_METHOD,
    'serviceLevel',h.SERVICE_LEVEL,
    'orderValue',h.ORDER_VALUE,
    'currency',h.INV_CURRENCY,
    'deliveryAddress',jsonb_build_object(
        'name',h.NAME,
        'address1',h.ADDRESS1,
        'address2',h.ADDRESS2,
        'town',h.TOWN,
        'county',h.COUNTY,
        'postcode',h.POSTCODE,
        'country',h.COUNTRY
    ),
    'lines',COALESCE((
        SELECT jsonb_agg(
            jsonb_build_object(
                'lineId',l.LINE_ID,
                'skuId',l.SKU_ID,
                'qtyOrdered',l.QTY_ORDERED,
                'qtyAllocated',l.QTY_SOFT_ALLOCATED,
                'qtyPicked',l.QTY_PICKED,
                'qtyShipped',l.QTY_SHIPPED,
                'unitPrice',l.PRODUCT_PRICE,
                'lineValue',COALESCE(l.EXTENDED_PRICE,l.PRODUCT_PRICE*l.QTY_ORDERED)
            )
            ORDER BY l.LINE_ID
        )
        FROM core.ORDER_LINE l
        WHERE l.CLIENT_ID=h.CLIENT_ID
          AND l.ORDER_ID=h.ORDER_ID
    ),'[]'::jsonb),
    'shipments',COALESCE((
        SELECT jsonb_agg(s.shipment ORDER BY s.container_id)
        FROM (
            SELECT
                sm.CONTAINER_ID AS container_id,
                jsonb_build_object(
                    'containerId',sm.CONTAINER_ID,
                    'status',MAX(sm.STATUS),
                    'carrierId',MAX(sm.CARRIER_ID),
                    'serviceLevel',MAX(sm.SERVICE_LEVEL),
                    'trackingNumber',MAX(sm.TRACKING_NUMBER),
                    'trackingUrl',MAX(sm.TRACKING_URL),
                    'trackingStatus',MAX(sm.TRACKING_STATUS),
                    'qtyShipped',SUM(COALESCE(sm.QTY_SHIPPED,0))
                ) AS shipment
            FROM core.SHIPPING_MANIFEST sm
            WHERE sm.CLIENT_ID=h.CLIENT_ID
              AND sm.ORDER_ID=h.ORDER_ID
            GROUP BY sm.CONTAINER_ID
        ) s
    ),'[]'::jsonb)
)
FROM core.ORDER_HEADER h
WHERE h.CLIENT_ID=p_client_id
  AND h.ORDER_ID=p_order_id;
$$;
