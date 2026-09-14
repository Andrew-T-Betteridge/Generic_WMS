CREATE OR REPLACE FUNCTION api.GET_SYSTEM_VERSION()
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
    SELECT jsonb_build_object(
        'productCode', sv.PRODUCT_CODE,
        'productName', sv.PRODUCT_NAME,
        'version', sv.VERSION_NUMBER,
        'major', sv.VERSION_MAJOR,
        'minor', sv.VERSION_MINOR,
        'patch', sv.VERSION_PATCH,
        'build', sv.BUILD_NUMBER,
        'releaseChannel', sv.RELEASE_CHANNEL,
        'releaseDate', sv.RELEASE_DATE,
        'description', sv.DESCRIPTION,
        'installedAt', sv.INSTALLED_DSTAMP
    )
    FROM config.SYSTEM_VERSION sv
    WHERE sv.PRODUCT_CODE='DYNETIC_WMS'
      AND sv.IS_CURRENT=TRUE
    ORDER BY sv.VERSION_KEY DESC
    LIMIT 1;
$$;
