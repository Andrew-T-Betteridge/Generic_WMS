import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { validateAdminConfig } from "./src/admin-config";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, ".", "");

  validateAdminConfig({
    environment: env.VITE_DYNETIC_ENVIRONMENT,
    apiBaseUrl: env.VITE_API_BASE_URL,
    auth0Domain: env.VITE_AUTH0_DOMAIN,
    auth0ClientId: env.VITE_AUTH0_CLIENT_ID,
    auth0Audience: env.VITE_AUTH0_AUDIENCE,
    adminTitle: env.VITE_ADMIN_TITLE,
  });

  return {
    plugins: [react()],
    server: {
      port: 5174,
      host: "0.0.0.0",
    },
    preview: {
      port: 4174,
      host: "0.0.0.0",
    },
  };
});
