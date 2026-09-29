// Separate from vite.config.ts so tests do not require deployment environment variables.
// vite.config.ts (and its environment validation) is intentionally unchanged.
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    include: ["src/**/*.test.{ts,tsx}"],
    css: false,
  },
});
