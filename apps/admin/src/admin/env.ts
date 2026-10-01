import { validateAdminConfig } from "./admin-config";

export const ADMIN_CONFIG = validateAdminConfig({
  environment: import.meta.env.VITE_DYNETIC_ENVIRONMENT ?? (import.meta.env.DEV ? "DEVELOPMENT" : undefined),
  apiBaseUrl: import.meta.env.VITE_API_BASE_URL ?? (import.meta.env.DEV ? "http://localhost:3000" : undefined),
  auth0Domain: import.meta.env.VITE_AUTH0_DOMAIN ?? (import.meta.env.DEV ? "configure-auth0.invalid" : undefined),
  auth0ClientId: import.meta.env.VITE_AUTH0_CLIENT_ID ?? (import.meta.env.DEV ? "configure-auth0" : undefined),
  auth0Audience: import.meta.env.VITE_AUTH0_AUDIENCE ?? (import.meta.env.DEV ? "http://localhost:3000" : undefined),
  adminTitle: import.meta.env.VITE_ADMIN_TITLE ?? "DYNETIC WMS Admin",
});
