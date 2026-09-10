CREATE TABLE IF NOT EXISTS config.carrier (
    client_id            varchar(30) NOT NULL REFERENCES core.client(client_id),
    carrier_id           varchar(30) NOT NULL,
    description          varchar(100) NOT NULL,
    active               boolean NOT NULL DEFAULT true,
    api_enabled          boolean NOT NULL DEFAULT false,
    account_reference    varchar(100),
    tracking_url_pattern text,
    created_dstamp       timestamptz NOT NULL DEFAULT now(),
    last_updated_dstamp  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (client_id, carrier_id)
);
