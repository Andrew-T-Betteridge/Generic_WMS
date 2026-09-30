CREATE TABLE IF NOT EXISTS config.CLIENT_SITE (
    CLIENT_ID           varchar(30) NOT NULL REFERENCES core.CLIENT(CLIENT_ID),
    SITE_ID             varchar(30) NOT NULL REFERENCES core.SITE(SITE_ID),
    ACTIVE              boolean NOT NULL DEFAULT true,
    DEFAULT_FULFILMENT  boolean NOT NULL DEFAULT false,
    CREATED_DSTAMP      timestamptz NOT NULL DEFAULT now(),
    LAST_UPDATE_DSTAMP  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (CLIENT_ID, SITE_ID)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_client_site_default_fulfilment
    ON config.CLIENT_SITE (CLIENT_ID)
    WHERE ACTIVE=true
      AND DEFAULT_FULFILMENT=true;

COMMENT ON TABLE config.CLIENT_SITE IS
'Operational applicability between independent CLIENT and SITE masters.';

COMMENT ON COLUMN config.CLIENT_SITE.DEFAULT_FULFILMENT IS
'Default fulfilment site used when an inbound channel does not explicitly resolve a site.';
