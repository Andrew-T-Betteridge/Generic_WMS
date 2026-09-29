import { Link, NavLink, Navigate, Route, Routes, useLocation } from "react-router";
import { useEffect, useState, type ReactNode } from "react";
import type { Token } from "../admin-api";
import type { Me } from "../control-plane";
import { NotificationBell } from "../monitoring";
import {
  ADMIN_ROUTES, canAccessRoute, firstAccessibleRoute, matchRoute, routeById, visibleNavSections,
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

/** Two-letter mark derived from the configured deployment title. */
export function brandInitials(title: string) {
  const words = title.trim().split(/\s+/).filter(Boolean);
  const letters = words.length > 1 ? words[0][0] + words[1][0] : (words[0] ?? "A").slice(0, 2);
  return letters.toUpperCase();
}

type Crumb = { label: string; to?: string };

export function Breadcrumbs() {
  const { pathname } = useLocation();
  const match = matchRoute(pathname);
  let trail: Crumb[];
  if (!match) trail = [{ label: "Not found" }];
  else if (match.route.id === "dashboard") trail = [{ label: match.route.label }];
  else if (match.route.parent) {
    const parent = routeById(match.route.parent);
    const record = Object.values(match.params)[0] ?? "";
    trail = [{ label: parent.section }, { label: parent.label, to: parent.path }, { label: `${match.route.label} ${record}` }];
  } else trail = [{ label: match.route.section }, { label: match.route.label }];
  return (
    <nav aria-label="Breadcrumb" className="cp-breadcrumbs">
      <ol>
        {trail.map((c, i) => (
          <li key={`${c.label}-${i}`} aria-current={i === trail.length - 1 ? "page" : undefined}>
            {c.to ? <Link to={c.to}>{c.label}</Link> : c.label}
          </li>
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
  const home = routeById("dashboard");
  if (canAccessRoute(home, has)) return <>{dashboard}</>;
  const first = firstAccessibleRoute(has);
  return first ? <Navigate to={first.path} replace /> : <ForbiddenPage />;
}

export function AdminRoutes({ me, token, has, environment }: Pick<ShellProps, "me" | "token" | "has" | "environment">) {
  const ctx = { me, token, has, environment };
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
  const { pathname } = useLocation();
  const [menuOpen, setMenuOpen] = useState(false);
  const current = matchRoute(pathname)?.route;
  const activeSection = current ? (current.parent ? routeById(current.parent).section : current.section) : undefined;

  useEffect(() => setMenuOpen(false), [pathname]);

  return (
    <div className={`cp-shell ${menuOpen ? "cp-menu-open" : ""}`}>
      <a className="cp-skip" href="#cp-main">Skip to content</a>
      <aside className="cp-sidebar">
        <div className="cp-brand">
          <div className="cp-mark" aria-hidden="true">{brandInitials(title)}</div>
          <div><strong>{title}</strong><span>DYNETIC WMS</span></div>
          <span className={`cp-env cp-env-${environment.toLowerCase()}`}>{environment}</span>
        </div>
        <nav className="cp-nav" aria-label="Admin sections" id="cp-nav">
          {sections.map((section) => (
            <div className={`cp-nav-section ${section.label === activeSection ? "current" : ""}`} key={section.label}>
              <span className="cp-nav-label">{section.label}</span>
              {section.routes.map((route) => (
                <NavLink key={route.id} to={route.path} end={route.path === "/"}>
                  {route.label}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>
        <div className="cp-user">
          <strong>{me.displayName || me.email}</strong>
          <span>{me.roles.join(", ") || "No roles"}</span>
          <button type="button" onClick={onSignOut}>Sign out</button>
        </div>
      </aside>
      <div className="cp-content">
        <header className="cp-topbar">
          <button type="button" className="cp-menu-btn" aria-expanded={menuOpen} aria-controls="cp-nav" onClick={() => setMenuOpen((o) => !o)}>
            Menu
          </button>
          <Breadcrumbs />
          <div className="cp-topbar-tools"><NotificationBell token={token} /></div>
        </header>
        <main id="cp-main" className="cp-main">
          <AdminRoutes me={me} token={token} has={has} environment={environment} />
        </main>
      </div>
    </div>
  );
}
