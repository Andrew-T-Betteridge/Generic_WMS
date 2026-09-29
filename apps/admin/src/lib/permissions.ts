// One frontend interpretation of the backend permission model.
//
// The WMS API (admin-rbac.ts → requirePermission) grants an operation when the
// principal's permission list contains the exact code OR the wildcard "*".
// The Admin must interpret /api/admin/me the same way, otherwise a wildcard
// administrator is hidden from screens the API would let them use.
// This only controls presentation; the API still enforces every request.

export type HasPermission = (permission: string) => boolean;

export const WILDCARD_PERMISSION = "*";

export function createHasPermission(permissions: readonly string[] | null | undefined): HasPermission {
  const granted = new Set(permissions ?? []);
  const wildcard = granted.has(WILDCARD_PERMISSION);
  return (permission: string) => !!permission && (wildcard || granted.has(permission));
}
