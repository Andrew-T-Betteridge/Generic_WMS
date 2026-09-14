CREATE OR REPLACE FUNCTION api.GET_ACCOUNT_INTERESTS(p_client_id VARCHAR,p_account_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'interestId',i.INTEREST_ID,
    'interestType',i.INTEREST_TYPE,
    'productId',i.PRODUCT_ID,
    'skuId',i.SKU_ID,
    'requestedQty',i.REQUESTED_QTY,
    'status',i.STATUS,
    'createdAt',i.CREATED_DSTAMP,
    'notifiedAt',i.NOTIFIED_DSTAMP
) ORDER BY i.CREATED_DSTAMP DESC),'[]'::jsonb)
FROM core.CUSTOMER_INTEREST i
WHERE i.CLIENT_ID=p_client_id AND i.ACCOUNT_ID=p_account_id;
$$;
