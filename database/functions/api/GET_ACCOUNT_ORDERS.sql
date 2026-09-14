CREATE OR REPLACE FUNCTION api.GET_ACCOUNT_ORDERS(p_client_id VARCHAR,p_account_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'orderId',h.ORDER_ID,
    'orderDate',h.ORDER_DATE,
    'status',h.STATUS,
    'paymentStatus',h.PAYMENT_STATUS,
    'fulfilmentStatus',h.FULFILMENT_STATUS,
    'dispatchMethod',h.DISPATCH_METHOD,
    'orderValue',h.ORDER_VALUE,
    'currency',h.INV_CURRENCY
) ORDER BY h.ORDER_DATE DESC),'[]'::jsonb)
FROM core.ORDER_HEADER h
WHERE h.CLIENT_ID=p_client_id AND h.ACCOUNT_ID=p_account_id;
$$;
