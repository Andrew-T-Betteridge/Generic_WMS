# DYNETIC WMS + Auth0 TEST setup

Auth0 is being used as the external identity provider. DYNETIC WMS remains the owner of customer, order, address, preference and fulfilment data.

The browser receives an Auth0 access token. The API verifies the token's issuer, audience and signature against Auth0's JWKS endpoint. The API then resolves the external identity into `core.CUSTOMER_ACCOUNT`.

## Why Auth0

The current DYNETIC WMS API already supports standards-based OIDC/JWT validation. Auth0 exposes a standard issuer and JWKS endpoint, so no Auth0-specific authentication logic needs to be placed into the WMS database.

TEST and PROD should have different API audiences.

TEST audience:

`https://test-api.finaticsaquatics.co.uk`

Future PROD audience:

`https://api.finaticsaquatics.co.uk`

The identifier is an OAuth audience; it does not need to be a live URL.

## Auth0 dashboard - one-time TEST setup

### 1. Create the TEST API

Auth0 Dashboard -> Applications -> APIs -> Create API

Name:

`DYNETIC WMS TEST API`

Identifier:

`https://test-api.finaticsaquatics.co.uk`

Signing algorithm:

`RS256`

The Identifier becomes `AUTH_AUDIENCE`.

### 2. Create the TEST storefront application

Auth0 Dashboard -> Applications -> Applications -> Create Application

Name:

`FINatics Storefront TEST`

Application type:

`Single Page Application`

For the current local frontend set:

Allowed Callback URLs:

`http://localhost:5173`

Allowed Logout URLs:

`http://localhost:5173`

Allowed Web Origins:

`http://localhost:5173`

Later add Lovable's preview/deployment URL rather than replacing the localhost entry.

### 3. Record the two browser-safe values

From the Auth0 application:

- Auth0 Domain
- Client ID

Client ID is for the browser/storefront and is not a server secret.

The API itself needs the Domain plus the API Identifier/Audience.

For a domain such as:

`example.uk.auth0.com`

DYNETIC WMS uses:

Issuer:

`https://example.uk.auth0.com/`

JWKS:

`https://example.uk.auth0.com/.well-known/jwks.json`

### 4. Generate the DYNETIC WMS TEST environment

From repository root:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\configure-auth0-test.ps1 -Auth0Domain "YOUR-AUTH0-DOMAIN"
```

This writes:

`config\environments\test.auth0.env`

It does not overwrite `apps/api/.env`.

### 5. Start the API in OIDC/Auth0 mode

```powershell
.\scripts\start-auth0-test-api.ps1
```

The script refuses to run unless it targets `fulfilment_test`.

### 6. Browser configuration

For the future Lovable/browser client, use:

- Domain = the Auth0 Domain
- Client ID = the Auth0 SPA Client ID
- Audience = `https://test-api.finaticsaquatics.co.uk`
- Scope = `openid profile email`

The browser must request an **access token for the DYNETIC WMS TEST API audience**. An Auth0 ID token should not be sent to the WMS API as its API bearer token.

### 7. Prove the complete identity path

After logging in as a real TEST customer and obtaining that user's Auth0 access token, from repository root run:

```powershell
.\scripts\test-auth0-account.ps1
```

Paste the USER access token when prompted.

Success proves:

Auth0 login -> signed access token -> DYNETIC WMS OIDC validation -> `core.CUSTOMER_ACCOUNT` identity resolution -> authenticated `/api/account`.

Do not paste tokens into chat or commit them.

## Production

Do not reuse the TEST API registration/audience as the production resource server.

When the storefront is accepted, create/configure the production API audience:

`https://api.finaticsaquatics.co.uk`

and production frontend URLs. Then fill `config/environments/production.api.env` using the production Auth0 issuer/audience/JWKS values.
