// Characterisation tests: lock in the existing, deployed environment validation.
// admin-config.ts itself is not changed in this phase.
import { describe, expect, it } from "vitest";
import { validateAdminConfig } from "./admin-config";

const PROD = "https://api.finaticsaquatics.co.uk";
const TEST = "https://test-api.finaticsaquatics.co.uk";
const base = { auth0Domain: "tenant.example.auth0.com", auth0ClientId: "client-id" };

describe("validateAdminConfig", () => {
  it("accepts a valid PRODUCTION config and normalises values", () => {
    const c = validateAdminConfig({ ...base, environment: "production", apiBaseUrl: PROD + "/", auth0Audience: PROD, adminTitle: "  Ops  " });
    expect(c).toEqual({ ...base, environment: "PRODUCTION", apiBaseUrl: PROD, auth0Audience: PROD, adminTitle: "Ops" });
  });

  it("keeps the existing title fallback", () => {
    expect(validateAdminConfig({ ...base, environment: "TEST", apiBaseUrl: TEST, auth0Audience: TEST }).adminTitle).toBe("FINatics Control");
  });

  it("reports missing required settings by name", () => {
    expect(() => validateAdminConfig({})).toThrow("ADMIN_CONFIG_MISSING:VITE_DYNETIC_ENVIRONMENT");
    expect(() => validateAdminConfig({ environment: "TEST" })).toThrow("ADMIN_CONFIG_MISSING:VITE_API_BASE_URL");
    expect(() => validateAdminConfig({ environment: "TEST", apiBaseUrl: TEST, auth0Audience: TEST })).toThrow("ADMIN_CONFIG_MISSING:VITE_AUTH0_DOMAIN");
  });

  it("rejects unknown environments and invalid URLs", () => {
    expect(() => validateAdminConfig({ ...base, environment: "STAGING", apiBaseUrl: TEST, auth0Audience: TEST })).toThrow("ADMIN_CONFIG_INVALID:VITE_DYNETIC_ENVIRONMENT");
    expect(() => validateAdminConfig({ ...base, environment: "TEST", apiBaseUrl: "not a url", auth0Audience: TEST })).toThrow("ADMIN_CONFIG_INVALID_URL:VITE_API_BASE_URL");
    expect(() => validateAdminConfig({ ...base, environment: "TEST", apiBaseUrl: "ftp://x.test", auth0Audience: TEST })).toThrow("ADMIN_CONFIG_INVALID_URL:VITE_API_BASE_URL");
  });

  it("blocks PRODUCTION and TEST pointing at the wrong API or audience", () => {
    expect(() => validateAdminConfig({ ...base, environment: "PRODUCTION", apiBaseUrl: TEST, auth0Audience: PROD })).toThrow("ADMIN_CONFIG_PRODUCTION_MISMATCH");
    expect(() => validateAdminConfig({ ...base, environment: "PRODUCTION", apiBaseUrl: PROD, auth0Audience: TEST })).toThrow("ADMIN_CONFIG_PRODUCTION_MISMATCH");
    expect(() => validateAdminConfig({ ...base, environment: "TEST", apiBaseUrl: PROD, auth0Audience: TEST })).toThrow("ADMIN_CONFIG_TEST_MISMATCH");
  });

  it("requires DEVELOPMENT to use a local API and never the production audience", () => {
    expect(validateAdminConfig({ ...base, environment: "DEVELOPMENT", apiBaseUrl: "http://localhost:3001", auth0Audience: TEST }).environment).toBe("DEVELOPMENT");
    expect(() => validateAdminConfig({ ...base, environment: "DEVELOPMENT", apiBaseUrl: TEST, auth0Audience: TEST })).toThrow("ADMIN_CONFIG_DEVELOPMENT_API_MUST_BE_LOCAL");
    expect(() => validateAdminConfig({ ...base, environment: "DEVELOPMENT", apiBaseUrl: "http://127.0.0.1:3001", auth0Audience: PROD })).toThrow("ADMIN_CONFIG_DEVELOPMENT_PROD_AUDIENCE_BLOCKED");
  });
});
