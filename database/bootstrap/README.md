# DYNETIC WMS fresh-install bootstrap

This bootstrap exists because the historical migration chain was not originally
designed to build a brand-new database from zero.

`001_dynetic_schema_v0_3_4.sql` is a PostgreSQL 18 schema-only snapshot of the
verified v0.3.4 TEST schema. Static review confirmed:

- no COPY data sections;
- no database/user ownership statements;
- no GRANT/REVOKE statements;
- no CREATE DATABASE/ROLE statements;
- no extension installation;
- no TEST/E2E/fixture object names;
- five application schemas: api, audit, config, core, interface.

The fresh-install manifest then applies the approved FINatics fry-tray catalogue
seed, media seed, production-safe base configuration, postcode directory schema, and the v0.3.10 version
marker.

Delivery-zone rows are deliberately not included. The TEST-only LOCAL-CV13
fixture must not be silently promoted into production.

Never use the fresh-install manifest against a non-empty database.
