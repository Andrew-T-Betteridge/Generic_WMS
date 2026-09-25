export type AdminEnvironment = "DEVELOPMENT" | "TEST" | "PRODUCTION";

type RawAdminConfig = {
  environment?: string;
  apiBaseUrl?: string;
  auth0Domain?: string;
  auth0ClientId?: string;
  auth0Audience?: string;
  adminTitle?: string;
};

export type AdminConfig = {
  environment: AdminEnvironment;
  apiBaseUrl: string;
  auth0Domain: string;
  auth0ClientId: string;
  auth0Audience: string;
  adminTitle: string;
};

const PROD_API = "https://api.finaticsaquatics.co.uk";
const TEST_API = "https://test-api.finaticsaquatics.co.uk";

function required(value: string | undefined, name: string) {
  const result = (value ?? "").trim();

  if (!result) {
    throw new Error(`ADMIN_CONFIG_MISSING:${name}`);
  }

  return result;
}

function normaliseUrl(value: string, name: string) {
  let parsed: URL;

  try {
    parsed = new URL(value);
  } catch {
    throw new Error(`ADMIN_CONFIG_INVALID_URL:${name}`);
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error(`ADMIN_CONFIG_INVALID_URL:${name}`);
  }

  return parsed.toString().replace(/\/$/, "");
}

export function validateAdminConfig(raw: RawAdminConfig): AdminConfig {
  const environment = required(
    raw.environment,
    "VITE_DYNETIC_ENVIRONMENT",
  ).toUpperCase() as AdminEnvironment;

  if (["DEVELOPMENT", "TEST", "PRODUCTION"].indexOf(environment) === -1) {
    throw new Error("ADMIN_CONFIG_INVALID:VITE_DYNETIC_ENVIRONMENT");
  }

  const apiBaseUrl = normaliseUrl(
    required(raw.apiBaseUrl, "VITE_API_BASE_URL"),
    "VITE_API_BASE_URL",
  );

  const auth0Audience = normaliseUrl(
    required(raw.auth0Audience, "VITE_AUTH0_AUDIENCE"),
    "VITE_AUTH0_AUDIENCE",
  );

  const auth0Domain = required(raw.auth0Domain, "VITE_AUTH0_DOMAIN");
  const auth0ClientId = required(raw.auth0ClientId, "VITE_AUTH0_CLIENT_ID");

  if (environment === "PRODUCTION") {
    if (apiBaseUrl !== PROD_API || auth0Audience !== PROD_API) {
      throw new Error("ADMIN_CONFIG_PRODUCTION_MISMATCH");
    }
  }

  if (environment === "TEST") {
    if (apiBaseUrl !== TEST_API || auth0Audience !== TEST_API) {
      throw new Error("ADMIN_CONFIG_TEST_MISMATCH");
    }
  }

  if (environment === "DEVELOPMENT") {
    const hostname = new URL(apiBaseUrl).hostname.toLowerCase();

    if (["localhost", "127.0.0.1", "::1"].indexOf(hostname) === -1) {
      throw new Error("ADMIN_CONFIG_DEVELOPMENT_API_MUST_BE_LOCAL");
    }

    if (auth0Audience === PROD_API) {
      throw new Error("ADMIN_CONFIG_DEVELOPMENT_PROD_AUDIENCE_BLOCKED");
    }
  }

  return {
    environment,
    apiBaseUrl,
    auth0Domain,
    auth0ClientId,
    auth0Audience,
    adminTitle: (raw.adminTitle ?? "FINatics Control").trim() || "FINatics Control",
  };
}

