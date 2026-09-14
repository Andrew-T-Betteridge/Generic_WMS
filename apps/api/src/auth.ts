import { createRemoteJWKSet, jwtVerify } from "jose";
import type { FastifyRequest } from "fastify";
import { db } from "./db.js";

export type AuthIdentity = {
  accountId: string;
  provider: string;
  subject: string;
  email: string;
  emailVerified: boolean;
  roles: string[];
};

const mode = (process.env.AUTH_MODE ?? "OIDC").toUpperCase();
const issuer = process.env.AUTH_ISSUER;
const audience = process.env.AUTH_AUDIENCE;
const jwksUrl = process.env.AUTH_JWKS_URL;
const devSecret = process.env.AUTH_DEV_HS256_SECRET;
const providerName = process.env.AUTH_PROVIDER_NAME ?? "OIDC";

let jwks: ReturnType<typeof createRemoteJWKSet> | undefined;

function bearer(req: FastifyRequest): string | null {
  const h = req.headers.authorization;
  if (!h?.startsWith("Bearer ")) return null;
  return h.slice(7).trim() || null;
}

function rolesFrom(payload: Record<string, unknown>): string[] {
  const raw = payload.roles ?? payload.role ?? [];
  if (Array.isArray(raw)) return raw.map(String);
  if (typeof raw === "string") return raw.split(/[ ,]+/).filter(Boolean);
  return [];
}

export async function optionalIdentity(req: FastifyRequest, clientId: string): Promise<AuthIdentity | null> {
  const token = bearer(req);
  if (!token) return null;

  let verified;
  if (mode === "DEV_HS256") {
    if (!devSecret) throw new Error("AUTH_DEV_HS256_SECRET_REQUIRED");
    verified = await jwtVerify(token, new TextEncoder().encode(devSecret), {
      algorithms: ["HS256"],
      issuer: issuer || undefined,
      audience: audience || undefined
    });
  } else {
    if (!jwksUrl || !issuer || !audience) throw new Error("OIDC_AUTH_CONFIGURATION_REQUIRED");
    jwks ??= createRemoteJWKSet(new URL(jwksUrl));
    verified = await jwtVerify(token, jwks, { issuer, audience });
  }

  const p = verified.payload as Record<string, unknown>;
  const subject = String(p.sub ?? "");
const email = String(
  p["https://dyneticwms.com/email"] ?? p.email ?? ""
).toLowerCase();

const emailVerified =
  p["https://dyneticwms.com/email_verified"] === true ||
  p.email_verified === true;

  if (!subject || !email) throw new Error("AUTH_REQUIRED_CLAIMS_MISSING");

  const r = await db.query(
    "select api.UPSERT_ACCOUNT_IDENTITY($1,$2,$3,$4,$5) as data",
    [clientId,providerName,subject,email,emailVerified]
  );
  const account = r.rows[0]?.data;
  if (!account?.accountId) throw new Error("ACCOUNT_RESOLUTION_FAILED");

  return {
    accountId: account.accountId,
    provider: providerName,
    subject,
    email,
    emailVerified,
    roles: rolesFrom(p)
  };
}

export async function requireIdentity(req: FastifyRequest, clientId: string): Promise<AuthIdentity> {
  const id = await optionalIdentity(req,clientId);
  if (!id) throw new Error("AUTHENTICATION_REQUIRED");
  return id;
}

export async function requireAdmin(req: FastifyRequest, clientId: string): Promise<AuthIdentity> {
  const id = await requireIdentity(req,clientId);
  const adminRole = (process.env.ADMIN_ROLE ?? "admin").toLowerCase();
  if (!id.roles.some(r=>r.toLowerCase()===adminRole)) throw new Error("ADMIN_REQUIRED");
  return id;
}
