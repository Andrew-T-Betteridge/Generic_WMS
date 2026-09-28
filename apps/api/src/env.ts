import "dotenv/config";

export type DyneticEnvironment =
  | "DEVELOPMENT"
  | "TEST"
  | "PRODUCTION";

export type AuthMode =
  | "OIDC"
  | "DEV_HS256";

export type StripeMode =
  | "TEST"
  | "LIVE";

const TEST_AUTH_AUDIENCE =
  "https://test-api.finaticsaquatics.co.uk";

const PRODUCTION_AUTH_AUDIENCE =
  "https://api.finaticsaquatics.co.uk";

function fail(message: string): never {
  throw new Error(
    `ENVIRONMENT_CONFIGURATION_INVALID: ${message}`
  );
}

function raw(name: string): string {
  return String(process.env[name] ?? "").trim();
}

function required(name: string): string {
  const value = raw(name);

  if (!value) {
    fail(`${name} is required`);
  }

  return value;
}

function integer(
  name: string,
  fallback?: number
): number {
  const value = raw(name);

  if (!value) {
    if (fallback !== undefined) {
      return fallback;
    }

    fail(`${name} is required`);
  }

  if (!/^\d+$/.test(value)) {
    fail(`${name} must be an integer`);
  }

  const parsed = Number(value);

  if (
    !Number.isSafeInteger(parsed) ||
    parsed < 1 ||
    parsed > 65535
  ) {
    fail(`${name} is outside the permitted range`);
  }

  return parsed;
}

function httpsUrl(
  name: string,
  value: string
): URL {
  let parsed: URL;

  try {
    parsed = new URL(value);
  } catch {
    fail(`${name} must be a valid URL`);
  }

  if (parsed.protocol !== "https:") {
    fail(`${name} must use HTTPS`);
  }

  return parsed;
}

const environmentValue =
  required("DYNETIC_ENVIRONMENT").toUpperCase();

if (
  environmentValue !== "DEVELOPMENT" &&
  environmentValue !== "TEST" &&
  environmentValue !== "PRODUCTION"
) {
  fail(
    "DYNETIC_ENVIRONMENT must be DEVELOPMENT, TEST or PRODUCTION"
  );
}

const environment =
  environmentValue as DyneticEnvironment;

const expectedPort =
  environment === "TEST" ? 3101 : 3001;

const port =
  integer("PORT", expectedPort);

const dbHost =
  raw("DB_HOST") || "localhost";

const dbPort =
  integer("DB_PORT", 5432);

const dbName =
  required("DB_NAME");

const dbUser =
  raw("DB_USER") || "postgres";

const stripeModeValue =
  required("STRIPE_MODE").toUpperCase();

if (
  stripeModeValue !== "TEST" &&
  stripeModeValue !== "LIVE"
) {
  fail("STRIPE_MODE must be TEST or LIVE");
}

const stripeMode =
  stripeModeValue as StripeMode;

const authModeValue =
  required("AUTH_MODE").toUpperCase();

if (
  authModeValue !== "OIDC" &&
  authModeValue !== "DEV_HS256"
) {
  fail("AUTH_MODE must be OIDC or DEV_HS256");
}

const authMode =
  authModeValue as AuthMode;

const authIssuer =
  raw("AUTH_ISSUER") || undefined;

const authAudience =
  raw("AUTH_AUDIENCE") || undefined;

const authJwksUrl =
  raw("AUTH_JWKS_URL") || undefined;

const authDevHs256Secret =
  raw("AUTH_DEV_HS256_SECRET") || undefined;

const authProviderName =
  raw("AUTH_PROVIDER_NAME") ||
  (authMode === "DEV_HS256" ? "DEV" : "OIDC");

if (environment === "DEVELOPMENT") {
  if (dbName !== "fulfilment_dev") {
    fail(
      "DEVELOPMENT must use DB_NAME=fulfilment_dev"
    );
  }

  if (port !== 3001) {
    fail(
      "DEVELOPMENT must use PORT=3001"
    );
  }

  if (stripeMode !== "TEST") {
    fail(
      "DEVELOPMENT must use STRIPE_MODE=TEST"
    );
  }
}

if (environment === "TEST") {
  if (dbHost.toLowerCase() !== "localhost") {
    fail(
      "TEST must use DB_HOST=localhost"
    );
  }

  if (dbPort !== 5432) {
    fail(
      "TEST must use DB_PORT=5432"
    );
  }

  if (dbName !== "fulfilment_test") {
    fail(
      "TEST must use DB_NAME=fulfilment_test"
    );
  }

  if (port !== 3101) {
    fail(
      "TEST must use PORT=3101"
    );
  }

  if (stripeMode !== "TEST") {
    fail(
      "TEST must use STRIPE_MODE=TEST"
    );
  }

  if (authMode !== "OIDC") {
    fail(
      "TEST must use AUTH_MODE=OIDC"
    );
  }

  if (authProviderName.toUpperCase() !== "AUTH0") {
    fail(
      "TEST must use AUTH_PROVIDER_NAME=AUTH0"
    );
  }

  if (authAudience !== TEST_AUTH_AUDIENCE) {
    fail(
      `TEST must use AUTH_AUDIENCE=${TEST_AUTH_AUDIENCE}`
    );
  }
}

if (environment === "PRODUCTION") {
  if (dbName !== "fulfilment_prod") {
    fail(
      "PRODUCTION must use DB_NAME=fulfilment_prod"
    );
  }

  if (port !== 3001) {
    fail(
      "PRODUCTION must use PORT=3001"
    );
  }

  if (authMode !== "OIDC") {
    fail(
      "PRODUCTION must use AUTH_MODE=OIDC"
    );
  }

  if (authAudience !== PRODUCTION_AUTH_AUDIENCE) {
    fail(
      `PRODUCTION must use AUTH_AUDIENCE=${PRODUCTION_AUTH_AUDIENCE}`
    );
  }
}

if (authMode === "DEV_HS256") {
  if (environment !== "DEVELOPMENT") {
    fail(
      "DEV_HS256 is permitted only in DEVELOPMENT"
    );
  }

  if (!authDevHs256Secret) {
    fail(
      "AUTH_DEV_HS256_SECRET is required for DEV_HS256"
    );
  }
}

if (authMode === "OIDC") {
  if (
    !authIssuer ||
    !authAudience ||
    !authJwksUrl
  ) {
    fail(
      "OIDC requires AUTH_ISSUER, AUTH_AUDIENCE and AUTH_JWKS_URL"
    );
  }

  const issuerUrl =
    httpsUrl("AUTH_ISSUER", authIssuer);

  const jwksUrl =
    httpsUrl("AUTH_JWKS_URL", authJwksUrl);

  httpsUrl("AUTH_AUDIENCE", authAudience);

  if (
    issuerUrl.hostname.toLowerCase() !==
    jwksUrl.hostname.toLowerCase()
  ) {
    fail(
      "AUTH_ISSUER and AUTH_JWKS_URL must use the same host"
    );
  }
}

const stripeSecretKey =
  raw("STRIPE_SECRET_KEY") || undefined;

if (
  stripeMode === "TEST" &&
  stripeSecretKey?.startsWith("sk_live_")
) {
  fail(
    "STRIPE_MODE=TEST cannot use a live Stripe secret key"
  );
}

if (stripeMode === "LIVE") {
  if (
    !stripeSecretKey ||
    !stripeSecretKey.startsWith("sk_live_")
  ) {
    fail(
      "STRIPE_MODE=LIVE requires a live Stripe secret key"
    );
  }
}

export const env = Object.freeze({
  environment,

  port,

  defaultClientId:
    raw("DEFAULT_CLIENT_ID") || "FINATICS",

  storeFrontOrigin:
    raw("STORE_FRONT_ORIGIN") ||
    "http://localhost:5173",

  adminOrigin:
    raw("ADMIN_ORIGIN"),

  dbHost,
  dbPort,
  dbName,
  dbUser,
  dbPassword:
    raw("DB_PASSWORD") || undefined,

  authMode,
  authProviderName,
  authIssuer,
  authAudience,
  authJwksUrl,
  authDevHs256Secret,

  stripeMode,

  orderAccessTokenSecret:
    raw("ORDER_ACCESS_TOKEN_SECRET") || undefined,

  orderAccessTokenTtl:
    raw("ORDER_ACCESS_TOKEN_TTL") || "30d",
});
