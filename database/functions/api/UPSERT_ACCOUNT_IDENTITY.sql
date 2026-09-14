CREATE OR REPLACE FUNCTION api.UPSERT_ACCOUNT_IDENTITY(
    p_client_id VARCHAR,
    p_auth_provider VARCHAR,
    p_auth_subject VARCHAR,
    p_email VARCHAR,
    p_email_verified BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_account core.CUSTOMER_ACCOUNT%ROWTYPE;
BEGIN
    IF NULLIF(TRIM(p_auth_provider),'') IS NULL
       OR NULLIF(TRIM(p_auth_subject),'') IS NULL
       OR NULLIF(LOWER(TRIM(p_email)),'') IS NULL THEN
        RAISE EXCEPTION 'INVALID_AUTH_IDENTITY';
    END IF;

    INSERT INTO core.CUSTOMER_ACCOUNT(
        CLIENT_ID,AUTH_PROVIDER,AUTH_SUBJECT,EMAIL,EMAIL_VERIFIED,ACTIVE,LAST_LOGIN_DSTAMP
    )
    VALUES(
        p_client_id,
        UPPER(TRIM(p_auth_provider)),
        TRIM(p_auth_subject),
        LOWER(TRIM(p_email)),
        COALESCE(p_email_verified,FALSE),
        TRUE,
        now()
    )
    ON CONFLICT (CLIENT_ID,AUTH_PROVIDER,AUTH_SUBJECT)
    DO UPDATE SET
        EMAIL=EXCLUDED.EMAIL,
        EMAIL_VERIFIED=core.CUSTOMER_ACCOUNT.EMAIL_VERIFIED OR EXCLUDED.EMAIL_VERIFIED,
        ACTIVE=TRUE,
        LAST_LOGIN_DSTAMP=now()
    RETURNING * INTO v_account;

    RETURN jsonb_build_object(
        'accountId',v_account.ACCOUNT_ID,
        'clientId',v_account.CLIENT_ID,
        'customerId',v_account.CUSTOMER_ID,
        'authProvider',v_account.AUTH_PROVIDER,
        'authSubject',v_account.AUTH_SUBJECT,
        'email',v_account.EMAIL,
        'emailVerified',v_account.EMAIL_VERIFIED,
        'active',v_account.ACTIVE
    );
END;
$$;
