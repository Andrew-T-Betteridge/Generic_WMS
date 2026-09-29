import type { Me } from "./control-plane";
import { createHasPermission } from "./lib/permissions";
import { AdminShell } from "./routing/AdminShell";
import type { Token } from "./admin-api";

const previewMe: Me = {
  adminUserId: "00000000-0000-0000-0000-000000000000",
  email: "operator@dynetic.example",
  displayName: "Alex Morgan",
  roles: ["Operations administrator"],
  permissions: ["*"],
  bootstrap: false,
};

const previewToken: Token = async () => "preview-only";

/** Visual QA only. Production always renders the Auth0-protected application. */
export function PreviewApp() {
  return (
    <AdminShell
      me={previewMe}
      token={previewToken}
      has={createHasPermission(previewMe.permissions)}
      title="DYNETIC WMS Admin"
      environment="TEST"
      onSignOut={() => undefined}
    />
  );
}