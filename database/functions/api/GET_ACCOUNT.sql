CREATE OR REPLACE FUNCTION api.GET_ACCOUNT(p_client_id VARCHAR,p_account_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT jsonb_build_object(
    'accountId',a.ACCOUNT_ID,
    'customerId',a.CUSTOMER_ID,
    'email',a.EMAIL,
    'emailVerified',a.EMAIL_VERIFIED,
    'active',a.ACTIVE,
    'createdAt',a.CREATED_DSTAMP,
    'lastLoginAt',a.LAST_LOGIN_DSTAMP
)
FROM core.CUSTOMER_ACCOUNT a
WHERE a.CLIENT_ID=p_client_id
  AND a.ACCOUNT_ID=p_account_id
  AND a.ACTIVE=TRUE;
$$;
