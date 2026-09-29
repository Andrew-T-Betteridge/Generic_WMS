import { Auth0Provider, useAuth0 } from "@auth0/auth0-react";
import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { MemoryRouter, useLocation, useNavigate } from "react-router";

import "./styles.css";
import "./control-plane.css";
import "./ui/ui.css";

import { api, type Token } from "./admin-api";
import type { Me } from "./control-plane";
import { ADMIN_CONFIG } from "./env";
import { describeError } from "./lib/api-errors";
import { createHasPermission } from "./lib/permissions";
import { AdminShell } from "./routing/AdminShell";
import dyneticLogo from "../assets/Dynetic_Logo.png";

function Button({ children, onClick, kind = "" }: { children: ReactNode; onClick?: () => void; kind?: string }) {
  return <button className={`btn ${kind}`} onClick={onClick}>{children}</button>;
}

function Load() {
  return <div className="load"><i />Loading...</div>;
}

function ErrorBox({ error }: { error: unknown }) {
  const detail = describeError(error);
  return (
    <div className="error" role="alert">
      <strong>{detail.title}</strong>
      <span>{detail.kind === "forbidden" ? "This account is not registered for Admin access. Ask an Admin administrator to grant access." : detail.message}</span>
      <details className="ui-technical"><summary>Technical details</summary><code>{detail.technical}</code></details>
    </div>
  );
}

function SignedInApp() {
  const { isLoading, isAuthenticated, loginWithRedirect, logout, getAccessTokenSilently } = useAuth0();
  const [me, setMe] = useState<Me | null>(null);
  const [error, setError] = useState<unknown>(null);
  const token = useCallback<Token>(async () => {
    const value = await getAccessTokenSilently({ authorizationParams: { audience: ADMIN_CONFIG.auth0Audience } });
    if (!value) throw new Error("AUTH_TOKEN_MISSING");
    return value;
  }, [getAccessTokenSilently]);

  useEffect(() => {
    if (!isAuthenticated) {
      setMe(null);
      return;
    }
    api<Me>(token, "/api/admin/me").then(setMe).catch(setError);
  }, [isAuthenticated, token]);

  const has = useMemo(() => createHasPermission(me?.permissions), [me]);
  if (isLoading) return <div className="splash"><Load /></div>;
  if (!isAuthenticated) {
    return (
      <div className="splash">
        <div className="login">
          <img className="login-logo" src={dyneticLogo} alt="DYNETIC" />
          <h1>{ADMIN_CONFIG.adminTitle}</h1>
          <p>Internal operations portal powered by DYNETIC WMS.</p>
          <Button onClick={() => loginWithRedirect()}>Sign in with Auth0</Button>
        </div>
      </div>
    );
  }
  if (error) {
    return (
      <div className="splash">
        <div className="login">
          <h1>Admin access unavailable</h1>
          <ErrorBox error={error} />
          <Button kind="ghost" onClick={() => logout({ logoutParams: { returnTo: location.origin } })}>Sign out</Button>
        </div>
      </div>
    );
  }
  if (!me) return <div className="splash"><Load /></div>;

  return <AdminShell me={me} token={token} has={has} title={ADMIN_CONFIG.adminTitle} environment={ADMIN_CONFIG.environment} onSignOut={() => logout({ logoutParams: { returnTo: location.origin } })} />;
}

/** Keeps the Admin's URL-addressable screens without nesting two browser-history owners. */
function BrowserUrlBridge() {
  const adminLocation = useLocation();
  const navigate = useNavigate();
  useEffect(() => {
    const next = `${adminLocation.pathname}${adminLocation.search}${adminLocation.hash}`;
    const current = `${location.pathname}${location.search}${location.hash}`;
    if (next !== current) history.pushState(null, "", next);
  }, [adminLocation]);
  useEffect(() => {
    const followBrowser = () => navigate(`${location.pathname}${location.search}${location.hash}`, { replace: true });
    addEventListener("popstate", followBrowser);
    return () => removeEventListener("popstate", followBrowser);
  }, [navigate]);
  return null;
}

export function AdminApp({ children }: { children?: ReactNode }) {
  const { auth0Domain: domain, auth0ClientId: clientId, auth0Audience: audience } = ADMIN_CONFIG;
  const initialEntry = `${location.pathname}${location.search}${location.hash}`;
  return (
    <Auth0Provider domain={domain} clientId={clientId} cacheLocation="localstorage" useRefreshTokens authorizationParams={{ redirect_uri: location.origin, audience, scope: "openid profile email" }}>
      <MemoryRouter initialEntries={[initialEntry]}>
        <BrowserUrlBridge />
        {children ?? <SignedInApp />}
      </MemoryRouter>
    </Auth0Provider>
  );
}