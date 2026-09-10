CREATE TABLE IF NOT EXISTS config.merge_rule (
    rule_id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id                varchar(30) NOT NULL REFERENCES core.client(client_id),
    rule_name                varchar(100) NOT NULL,
    priority                 integer NOT NULL DEFAULT 100,
    active                   boolean NOT NULL DEFAULT true,
    same_customer_reqd       boolean NOT NULL DEFAULT true,
    same_address_reqd        boolean NOT NULL DEFAULT true,
    same_dispatch_reqd       boolean NOT NULL DEFAULT true,
    same_service_reqd        boolean NOT NULL DEFAULT false,
    same_delivery_date_reqd  boolean NOT NULL DEFAULT false,
    max_combined_weight_kg   numeric(12,3),
    max_combined_volume_cm3  numeric(18,3),
    rule_expression          jsonb,
    stop_on_match            boolean NOT NULL DEFAULT false,
    created_dstamp           timestamptz NOT NULL DEFAULT now(),
    last_updated_dstamp      timestamptz NOT NULL DEFAULT now()
);
