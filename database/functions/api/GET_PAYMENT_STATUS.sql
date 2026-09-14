CREATE OR REPLACE FUNCTION api.GET_PAYMENT_STATUS(
    p_client_id VARCHAR,p_payment_id UUID,p_account_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT jsonb_build_object(
    'paymentId',p.PAYMENT_ID,
    'provider',p.PROVIDER,
    'referenceType',p.REFERENCE_TYPE,
    'referenceId',p.REFERENCE_ID,
    'amount',p.AMOUNT,
    'currency',p.CURRENCY,
    'status',p.STATUS,
    'capturedAmount',p.CAPTURED_AMOUNT,
    'refundedAmount',p.REFUNDED_AMOUNT,
    'failureCode',p.FAILURE_CODE,
    'failureText',p.FAILURE_TEXT,
    'createdAt',p.CREATED_DSTAMP,
    'updatedAt',p.LAST_UPDATE_DSTAMP
)
FROM core.PAYMENT_TRANSACTION p
WHERE p.CLIENT_ID=p_client_id
  AND p.PAYMENT_ID=p_payment_id
  AND (p_account_id IS NULL OR p.ACCOUNT_ID=p_account_id);
$$;
