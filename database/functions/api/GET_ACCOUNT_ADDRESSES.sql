CREATE OR REPLACE FUNCTION api.GET_ACCOUNT_ADDRESSES(p_client_id VARCHAR,p_account_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'addressId',m.ADDRESS_ID,
    'label',m.ADDRESS_LABEL,
    'defaultDelivery',m.DEFAULT_DELIVERY,
    'defaultBilling',m.DEFAULT_BILLING,
    'name',a.NAME,
    'contact',a.CONTACT,
    'phone',COALESCE(a.CONTACT_MOBILE,a.CONTACT_PHONE),
    'email',a.CONTACT_EMAIL,
    'address1',a.ADDRESS1,
    'address2',a.ADDRESS2,
    'town',a.TOWN,
    'county',a.COUNTY,
    'postcode',a.POSTCODE,
    'country',a.COUNTRY
) ORDER BY m.DEFAULT_DELIVERY DESC,m.DEFAULT_BILLING DESC,m.CREATED_DSTAMP DESC),'[]'::jsonb)
FROM core.CUSTOMER_ACCOUNT_ADDRESS m
JOIN core.ADDRESS a
  ON a.CLIENT_ID=m.CLIENT_ID AND a.ADDRESS_ID=m.ADDRESS_ID
WHERE m.CLIENT_ID=p_client_id
  AND m.ACCOUNT_ID=p_account_id
  AND m.ACTIVE=TRUE;
$$;
