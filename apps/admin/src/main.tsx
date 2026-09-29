import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import "./styles.css";
import { AdminApp } from "./admin/AdminApp";

const root = document.getElementById("root");

if (!root) {
  throw new Error("ADMIN_ROOT_MISSING");
}

createRoot(root).render(
  <StrictMode>
    <AdminApp />
  </StrictMode>,
);
