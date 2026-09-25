import { validateAdminConfig } from "./admin-config";

export const ADMIN_CONFIG = validateAdminConfig({
  environment: import.meta.env.VITE_DYNETIC_ENVIRONMENT,
  apiBaseUrl: import.meta.env.VITE_API_BASE_URL,
  auth0Domain: import.meta.env.VITE_AUTH0_DOMAIN,
  auth0ClientId: import.meta.env.VITE_AUTH0_CLIENT_ID,
  auth0Audience: import.meta.env.VITE_AUTH0_AUDIENCE,
  adminTitle: import.meta.env.VITE_ADMIN_TITLE,
});
