\set ON_ERROR_STOP on

BEGIN;

-------------------------------------------------------------------------------
-- DYNETIC admin portal RBAC foundation.
-- Local permissions are authoritative once an admin user exists.
-- Existing OIDC ADMIN_ROLE remains a bootstrap/break-glass path.
-------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS config.ADMIN_PERMISSION (
    PERMISSION_CODE VARCHAR(80) PRIMARY KEY,
    CATEGORY VARCHAR(40) NOT NULL,
    DESCRIPTION VARCHAR(250) NOT NULL,
    DANGEROUS BOOLEAN NOT NULL DEFAULT FALSE,
    CREATED_DSTAMP TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS config.ADMIN_ROLE (
    CLIENT_ID VARCHAR(30) NOT NULL,
    ROLE_CODE VARCHAR(30) NOT NULL,
    ROLE_NAME VARCHAR(80) NOT NULL,
    DESCRIPTION VARCHAR(250),
    SYSTEM_ROLE BOOLEAN NOT NULL DEFAULT FALSE,
    ACTIVE BOOLEAN NOT NULL DEFAULT TRUE,
    CREATED_DSTAMP TIMESTAMPTZ NOT NULL DEFAULT now(),
    LAST_UPDATE_DSTAMP TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (CLIENT_ID,ROLE_CODE),
    CONSTRAINT FK_ADMIN_ROLE_CLIENT
        FOREIGN KEY (CLIENT_ID) REFERENCES core.CLIENT(CLIENT_ID)
);

CREATE TABLE IF NOT EXISTS config.ADMIN_ROLE_PERMISSION (
    CLIENT_ID VARCHAR(30) NOT NULL,
    ROLE_CODE VARCHAR(30) NOT NULL,
    PERMISSION_CODE VARCHAR(80) NOT NULL,
    CREATED_DSTAMP TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (CLIENT_ID,ROLE_CODE,PERMISSION_CODE),
    CONSTRAINT FK_ADMIN_ROLE_PERMISSION_ROLE
        FOREIGN KEY (CLIENT_ID,ROLE_CODE)
        REFERENCES config.ADMIN_ROLE(CLIENT_ID,ROLE_CODE)
        ON DELETE CASCADE,
    CONSTRAINT FK_ADMIN_ROLE_PERMISSION_PERMISSION
        FOREIGN KEY (PERMISSION_CODE)
        REFERENCES config.ADMIN_PERMISSION(PERMISSION_CODE)
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS config.ADMIN_USER (
    ADMIN_USER_ID UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID VARCHAR(30) NOT NULL,
    ACCOUNT_ID UUID,
    EMAIL VARCHAR(254) NOT NULL,
    DISPLAY_NAME VARCHAR(120),
    AUTH_PROVIDER VARCHAR(50),
    AUTH_SUBJECT VARCHAR(200),
    ACTIVE BOOLEAN NOT NULL DEFAULT TRUE,
    IS_OWNER BOOLEAN NOT NULL DEFAULT FALSE,
    LAST_LOGIN_DSTAMP TIMESTAMPTZ,
    CREATED_BY VARCHAR(120),
    CREATED_DSTAMP TIMESTAMPTZ NOT NULL DEFAULT now(),
    LAST_UPDATE_DSTAMP TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT FK_ADMIN_USER_CLIENT
        FOREIGN KEY (CLIENT_ID) REFERENCES core.CLIENT(CLIENT_ID),
    CONSTRAINT FK_ADMIN_USER_ACCOUNT
        FOREIGN KEY (ACCOUNT_ID) REFERENCES core.CUSTOMER_ACCOUNT(ACCOUNT_ID)
);

CREATE UNIQUE INDEX IF NOT EXISTS UQ_ADMIN_USER_CLIENT_EMAIL
    ON config.ADMIN_USER (CLIENT_ID,LOWER(EMAIL));

CREATE UNIQUE INDEX IF NOT EXISTS UQ_ADMIN_USER_CLIENT_IDENTITY
    ON config.ADMIN_USER (CLIENT_ID,AUTH_PROVIDER,AUTH_SUBJECT)
    WHERE AUTH_SUBJECT IS NOT NULL;

CREATE INDEX IF NOT EXISTS IX_ADMIN_USER_CLIENT_ACTIVE
    ON config.ADMIN_USER (CLIENT_ID,ACTIVE,LOWER(EMAIL));

CREATE TABLE IF NOT EXISTS config.ADMIN_USER_ROLE (
    CLIENT_ID VARCHAR(30) NOT NULL,
    ADMIN_USER_ID UUID NOT NULL,
    ROLE_CODE VARCHAR(30) NOT NULL,
    CREATED_DSTAMP TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (CLIENT_ID,ADMIN_USER_ID,ROLE_CODE),
    CONSTRAINT FK_ADMIN_USER_ROLE_USER
        FOREIGN KEY (ADMIN_USER_ID)
        REFERENCES config.ADMIN_USER(ADMIN_USER_ID)
        ON DELETE CASCADE,
    CONSTRAINT FK_ADMIN_USER_ROLE_ROLE
        FOREIGN KEY (CLIENT_ID,ROLE_CODE)
        REFERENCES config.ADMIN_ROLE(CLIENT_ID,ROLE_CODE)
        ON DELETE CASCADE
);

INSERT INTO config.ADMIN_PERMISSION
    (PERMISSION_CODE,CATEGORY,DESCRIPTION,DANGEROUS)
VALUES
    ('admin.access','ADMIN','Access the admin portal',FALSE),
    ('dashboard.read','DASHBOARD','View admin dashboard metrics',FALSE),

    ('product.read','CATALOGUE','View products and variants',FALSE),
    ('product.create','CATALOGUE','Create products',FALSE),
    ('product.update','CATALOGUE','Update products, variants and SKU presentation data',FALSE),
    ('product.deactivate','CATALOGUE','Deactivate products and variants',TRUE),

    ('pricing.read','PRICING','View selling prices',FALSE),
    ('pricing.update','PRICING','Change selling prices',TRUE),

    ('inventory.read','INVENTORY','View inventory and availability',FALSE),
    ('inventory.adjust','INVENTORY','Adjust physical inventory quantities',TRUE),

    ('order.read','ORDERS','View customer orders',FALSE),
    ('order.update','ORDERS','Update operational order fields',TRUE),
    ('order.cancel','ORDERS','Cancel eligible orders',TRUE),

    ('payment.read','PAYMENTS','View payment status',FALSE),
    ('payment.refund','PAYMENTS','Issue refunds',TRUE),

    ('customer.read','CUSTOMERS','View customer details and interests',FALSE),
    ('review.moderate','CATALOGUE','Moderate product reviews',TRUE),
    ('affiliate.read','MARKETING','View affiliate demand',FALSE),
    ('reservation.expire','OPERATIONS','Run reservation expiry cleanup',TRUE),

    ('user.read','SECURITY','View admin users',FALSE),
    ('user.create','SECURITY','Create admin users',TRUE),
    ('user.update','SECURITY','Update admin users',TRUE),
    ('user.disable','SECURITY','Disable admin users',TRUE),
    ('user.role.assign','SECURITY','Assign roles to admin users',TRUE),

    ('role.read','SECURITY','View admin roles and permissions',FALSE),
    ('role.create','SECURITY','Create admin roles',TRUE),
    ('role.update','SECURITY','Update admin roles',TRUE),
    ('role.permission.assign','SECURITY','Change permissions assigned to roles',TRUE),

    ('config.read','CONFIG','View operational configuration',FALSE),
    ('config.update','CONFIG','Change operational configuration',TRUE),
    ('audit.read','AUDIT','View admin audit history',FALSE)
ON CONFLICT (PERMISSION_CODE)
DO UPDATE SET
    CATEGORY=EXCLUDED.CATEGORY,
    DESCRIPTION=EXCLUDED.DESCRIPTION,
    DANGEROUS=EXCLUDED.DANGEROUS;

INSERT INTO config.ADMIN_ROLE
    (CLIENT_ID,ROLE_CODE,ROLE_NAME,DESCRIPTION,SYSTEM_ROLE,ACTIVE)
VALUES
    ('FINATICS','OWNER','Owner','Full access to every admin capability.',TRUE,TRUE),
    ('FINATICS','MANAGER','Manager','Day-to-day management without security administration.',TRUE,TRUE),
    ('FINATICS','CATALOGUE','Catalogue','Manage catalogue content, variants and pricing.',TRUE,TRUE),
    ('FINATICS','WAREHOUSE','Warehouse','Manage stock and operational order work.',TRUE,TRUE),
    ('FINATICS','VIEWER','Viewer','Read-only operational access.',TRUE,TRUE)
ON CONFLICT (CLIENT_ID,ROLE_CODE)
DO UPDATE SET
    ROLE_NAME=EXCLUDED.ROLE_NAME,
    DESCRIPTION=EXCLUDED.DESCRIPTION,
    SYSTEM_ROLE=TRUE,
    ACTIVE=TRUE,
    LAST_UPDATE_DSTAMP=now();

INSERT INTO config.ADMIN_ROLE_PERMISSION (CLIENT_ID,ROLE_CODE,PERMISSION_CODE)
SELECT 'FINATICS','OWNER',p.PERMISSION_CODE
FROM config.ADMIN_PERMISSION p
ON CONFLICT DO NOTHING;

INSERT INTO config.ADMIN_ROLE_PERMISSION (CLIENT_ID,ROLE_CODE,PERMISSION_CODE)
SELECT 'FINATICS','MANAGER',x.permission_code
FROM (VALUES
    ('admin.access'),('dashboard.read'),
    ('product.read'),('product.create'),('product.update'),('product.deactivate'),
    ('pricing.read'),('pricing.update'),
    ('inventory.read'),('inventory.adjust'),
    ('order.read'),('order.update'),('order.cancel'),
    ('payment.read'),('payment.refund'),
    ('customer.read'),('review.moderate'),('affiliate.read'),('reservation.expire'),
    ('config.read'),('audit.read')
) x(permission_code)
ON CONFLICT DO NOTHING;

INSERT INTO config.ADMIN_ROLE_PERMISSION (CLIENT_ID,ROLE_CODE,PERMISSION_CODE)
SELECT 'FINATICS','CATALOGUE',x.permission_code
FROM (VALUES
    ('admin.access'),('dashboard.read'),
    ('product.read'),('product.create'),('product.update'),('product.deactivate'),
    ('pricing.read'),('pricing.update'),
    ('inventory.read'),('order.read')
) x(permission_code)
ON CONFLICT DO NOTHING;

INSERT INTO config.ADMIN_ROLE_PERMISSION (CLIENT_ID,ROLE_CODE,PERMISSION_CODE)
SELECT 'FINATICS','WAREHOUSE',x.permission_code
FROM (VALUES
    ('admin.access'),('dashboard.read'),
    ('product.read'),('inventory.read'),('inventory.adjust'),
    ('order.read'),('order.update'),('customer.read')
) x(permission_code)
ON CONFLICT DO NOTHING;

INSERT INTO config.ADMIN_ROLE_PERMISSION (CLIENT_ID,ROLE_CODE,PERMISSION_CODE)
SELECT 'FINATICS','VIEWER',x.permission_code
FROM (VALUES
    ('admin.access'),('dashboard.read'),
    ('product.read'),('pricing.read'),('inventory.read'),
    ('order.read'),('payment.read'),('customer.read')
) x(permission_code)
ON CONFLICT DO NOTHING;

COMMIT;
