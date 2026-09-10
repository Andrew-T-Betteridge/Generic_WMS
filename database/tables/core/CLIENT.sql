CREATE TABLE IF NOT EXISTS core.client (
    client_id            varchar(30) PRIMARY KEY,
    description          varchar(100) NOT NULL,
    active               boolean NOT NULL DEFAULT true,
    created_dstamp       timestamptz NOT NULL DEFAULT now(),
    last_updated_dstamp  timestamptz NOT NULL DEFAULT now()
);
