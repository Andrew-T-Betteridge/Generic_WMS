import { Link, NavLink, Navigate, Route, Routes, useLocation } from "react-router";
import type { ReactNode } from "react";
import type { Token } from "../admin-api";
import type { Me } from "../control-plane";
import { NotificationBell } from "../monitoring";
import {
  ADMIN_ROUTES, canAccessRoute, findRouteByPath, firstAccessibleRoute, visibleNavSections,
  type AdminRoute, type HasPermission,
} from "./admin-routes";
import { ROUTE_PAGES } from "./route-pages";
import "./admin-shell.css";

type ShellProps = {
  me: Me;
  token: Token;
  has: HasPermission;
  title: string;
  environment: string;
  onSignOut: () => void;
};

export function Breadcrumbs() {
  const { pathname } = useLocation();
  const route = findRouteByPath(pathname);
  const trail: string[] = route ? (route.id === "dashboard" ? [route.label] : [route.section, route.label]) : ["Not found"];
  return (
    <nav aria-label="Breadcrumb" className="cp-breadcrumbs">
      <ol>
        {trail.map((label, i) => (
          <li key={label} aria-current={i === trail.length - 1 ? "page" : undefined}>{label}</li>
        ))}
      </ol>
    </nav>
  );
}

export function ForbiddenPage() {
  return (
    <section className="cp-state" role="alert">
      <h1>Access not available</h1>
      <p>The account you are signed in with does not have access to this area of the Admin.</p>
      <p>If you need it for your work, ask an Admin administrator to review your access.</p>
      <Link className="btn ghost" to="/">Go to start</Link>
    </section>
  );
}

export function NotFoundPage() {
  return (
    <section className="cp-state">
      <h1>Page not found</h1>
      <p>There is no Admin page at this address. Check the link or use the navigation.</p>
      <Link className="btn ghost" to="/">Go to start</Link>
    </section>
  );
}

function Guarded({ route, has, children }: { route: AdminRoute; has: HasPermission; children: ReactNode }) {
  return canAccessRoute(route, has) ? <>{children}</> : <ForbiddenPage />;
}

/** "/" shows the Control centre when permitted, otherwise the first screen the user can open. */
function StartRoute({ has, dashboard }: { has: HasPermission; dashboard: ReactNode }) {
  const home = ADMIN_ROUTES[0];
  if (canAccessRoute(home, has)) return <>{dashboard}</>;
  const first = firstAccessibleRoute(has);
  return first ? <Navigate to={first.path} replace /> : <ForbiddenPage />;
}

export function AdminRoutes({ me, token, has }: Pick<ShellProps, "me" | "token" | "has">) {
  const ctx = { me, token, has };
  return (
    <Routes>
      {ADMIN_ROUTES.map((route) =>
        route.path === "/" ? (
          <Route key={route.id} path="/" element={<StartRoute has={has} dashboard={ROUTE_PAGES[route.id](ctx)} />} />
        ) : (
          <Route key={route.id} path={route.path} element={<Guarded route={route} has={has}>{ROUTE_PAGES[route.id](ctx)}</Guarded>} />
        ),
      )}
      <Route path="*" element={<NotFoundPage />} />
    </Routes>
  );
}

export function AdminShell({ me, token, has, title, environment, onSignOut }: ShellProps) {
  const sections = visibleNavSections(has);
  return (
    <div className="shell cp-shell">
      <aside>
        <div className="brand">
          <div className="logo small">FA</div>
          <div><strong>{title}</strong><span>DYNETIC WMS · {environment}</span></div>
        </div>
        <nav className="cp-nav" aria-label="Admin sections">
          {sections.map((section) => (
            <div className="cp-nav-section" key={section.label}>
              <span className="cp-nav-label">{section.label}</span>
              {section.routes.map((route) => (
                <NavLink key={route.id} to={route.path} end className={({ isActive }) => (isActive ? "active" : "")}>
                  {route.label}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>
        <div className="foot">
          <strong>{me.displayName || me.email}</strong>
          <span>{me.roles.join(", ")}</span>
          <small>{me.permissions.length} permissions</small>
          <button onClick={onSignOut}>Sign out</button>
        </div>
      </aside>
      <main>
        <Breadcrumbs />
        <AdminRoutes me={me} token={token} has={has} />
        <NotificationBell token={token} />
      </main>
    </div>
  );
}
