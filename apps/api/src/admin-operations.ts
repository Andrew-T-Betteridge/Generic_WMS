import type { FastifyInstance, FastifyReply } from "fastify";
import type { PoolClient } from "pg";
import { db } from "./db.js";
import { requirePermission } from "./admin-rbac.js";

function codeOf(error: unknown) {
  return String((error as Error)?.message ?? error).split(":")[0];
}

function sendError(reply: FastifyReply, error: unknown) {
  const code = codeOf(error);
  const status =
    code === "AUTHENTICATION_REQUIRED"
      ? 401
      : code.endsWith("_NOT_FOUND")
        ? 404
        : code.includes("PERMISSION") || code.includes("ADMIN_ACCESS")
          ? 403
          : code.startsWith("INVALID_") || code.endsWith("_REQUIRED")
            ? 400
            : 409;
  return reply.code(status).send({ error: code });
}

function finiteNumber(value: unknown, code: string) {
  const n = Number(value);
  if (!Number.isFinite(n)) throw new Error(code);
  return n;
}

function reasonCode(value: unknown, fallback: string) {
  const reason = String(value ?? fallback).trim().toUpperCase();
  if (!/^[A-Z0-9_-]{2,10}$/.test(reason)) throw new Error("INVALID_REASON_CODE");
  return reason;
}

async function insertAudit(
  client: PoolClient,
  clientId: string,
  changedBy: string,
  entityType: string,
  entityId: string,
  action: string,
  reason: string | null,
  beforeData: unknown,
  afterData: unknown,
) {
  await client.query(
    `insert into audit.AUDIT_EVENT
      (CLIENT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY,REASON,BEFORE_DATA,AFTER_DATA)
     values($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb)`,
    [
      clientId,
      entityType,
      entityId,
      action,
      changedBy,
      reason,
      beforeData == null ? null : JSON.stringify(beforeData),
      afterData == null ? null : JSON.stringify(afterData),
    ],
  );
}

export function registerAdminOperationRoutes(
  app: FastifyInstance,
  clientId: string,
) {
  app.get("/api/admin/inventory/rows", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "inventory.read");
      const query = req.query as { q?: string; limit?: string; offset?: string };
      const q = String(query.q ?? "").trim() || null;
      const limit = Math.max(1, Math.min(500, Number(query.limit ?? 250) || 250));
      const offset = Math.max(0, Number(query.offset ?? 0) || 0);

      const result = await db.query(
        `select
            i.KEY as inventory_key,
            i.SKU_ID,
            p.PRODUCT_ID,
            p.PRODUCT_NAME,
            pv.VARIANT_NAME,
            i.SITE_ID,
            i.LOCATION_ID,
            i.TAG_ID,
            i.BATCH_ID,
            i.CONDITION_ID,
            i.LOCK_STATUS,
            i.LOCK_CODE,
            i.QTY_ON_HAND,
            i.QTY_ALLOCATED,
            (i.QTY_ON_HAND-i.QTY_ALLOCATED) as QTY_AVAILABLE,
            i.MOVE_DSTAMP,
            i.COUNT_DSTAMP
           from core.INVENTORY i
           left join core.PRODUCT_VARIANT pv
             on pv.CLIENT_ID=i.CLIENT_ID and pv.SKU_ID=i.SKU_ID
           left join core.PRODUCT p
             on p.CLIENT_ID=pv.CLIENT_ID and p.PRODUCT_ID=pv.PRODUCT_ID
          where i.CLIENT_ID=$1
            and (
              $2::text is null
              or i.SKU_ID ilike '%'||$2||'%'
              or i.LOCATION_ID ilike '%'||$2||'%'
              or COALESCE(p.PRODUCT_NAME,'') ilike '%'||$2||'%'
              or COALESCE(pv.VARIANT_NAME,'') ilike '%'||$2||'%'
              or COALESCE(i.TAG_ID,'') ilike '%'||$2||'%'
              or COALESCE(i.BATCH_ID,'') ilike '%'||$2||'%'
            )
          order by p.PRODUCT_NAME nulls last,i.SKU_ID,i.LOCATION_ID,i.KEY
          limit $3 offset $4`,
        [clientId, q, limit, offset],
      );
      return result.rows;
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.post("/api/admin/inventory/:inventoryKey/adjust", async (req, reply) => {
    const client = await db.connect();
    try {
      const principal = await requirePermission(req, clientId, "inventory.adjust");
      const { inventoryKey } = req.params as { inventoryKey: string };
      const key = Number(inventoryKey);
      if (!Number.isSafeInteger(key) || key <= 0) throw new Error("INVALID_INVENTORY_KEY");

      const body = (req.body ?? {}) as {
        adjustmentQty?: unknown;
        reasonCode?: unknown;
        notes?: unknown;
      };
      const adjustmentQty = finiteNumber(body.adjustmentQty, "INVALID_ADJUSTMENT_QTY");
      if (adjustmentQty === 0) throw new Error("INVALID_ADJUSTMENT_QTY");
      const reason = reasonCode(body.reasonCode, "ADJUST");
      const notes = String(body.notes ?? "").trim();
      if (notes.length > 400) throw new Error("INVALID_NOTES");

      await client.query("begin");

      const before = await client.query(
        `select KEY,CLIENT_ID,SKU_ID,LOCATION_ID,TAG_ID,BATCH_ID,CONDITION_ID,
                LOCK_STATUS,LOCK_CODE,QTY_ON_HAND,QTY_ALLOCATED,
                (QTY_ON_HAND-QTY_ALLOCATED) as QTY_AVAILABLE
           from core.INVENTORY
          where CLIENT_ID=$1 and KEY=$2
          for update`,
        [clientId, key],
      );
      if (!before.rowCount) throw new Error("INVENTORY_NOT_FOUND");

      const operation = await client.query(
        `select *
           from core.ADJUST_INVENTORY($1,$2,$3,$4,$5,$6,$7)`,
        [
          clientId,
          key,
          adjustmentQty,
          reason,
          notes || null,
          principal.email,
          "FINATICS_ADMIN",
        ],
      );

      const after = await client.query(
        `select KEY,CLIENT_ID,SKU_ID,LOCATION_ID,TAG_ID,BATCH_ID,CONDITION_ID,
                LOCK_STATUS,LOCK_CODE,QTY_ON_HAND,QTY_ALLOCATED,
                (QTY_ON_HAND-QTY_ALLOCATED) as QTY_AVAILABLE
           from core.INVENTORY
          where CLIENT_ID=$1 and KEY=$2`,
        [clientId, key],
      );

      await insertAudit(
        client,
        clientId,
        principal.email,
        "INVENTORY",
        String(key),
        "ADJUST",
        [reason, notes].filter(Boolean).join(": "),
        before.rows[0],
        after.rows[0],
      );

      await client.query("commit");
      return {
        operation: operation.rows[0],
        inventory: after.rows[0],
      };
    } catch (e) {
      try {
        await client.query("rollback");
      } catch {}
      return sendError(reply, e);
    } finally {
      client.release();
    }
  });

  app.post("/api/admin/orders/:orderId/cancel", async (req, reply) => {
    const client = await db.connect();
    try {
      const principal = await requirePermission(req, clientId, "order.cancel");
      const { orderId } = req.params as { orderId: string };
      const body = (req.body ?? {}) as { reasonCode?: unknown; notes?: unknown };
      const reason = reasonCode(body.reasonCode, "CANCEL");
      const notes = String(body.notes ?? "").trim();
      if (notes.length > 400) throw new Error("INVALID_NOTES");

      await client.query("begin");

      const before = await client.query(
        `select CLIENT_ID,ORDER_ID,ORDER_REFERENCE,STATUS,PAYMENT_STATUS,
                FULFILMENT_STATUS,ORDER_CLOSED,CLOSURE_DATE,SHIPPED_DATE,
                DELIVERED_DSTAMP,ORDER_VALUE,INV_CURRENCY,LAST_UPDATED_BY,
                LAST_UPDATE_DATE
           from core.ORDER_HEADER
          where CLIENT_ID=$1 and ORDER_ID=$2
          for update`,
        [clientId, orderId],
      );
      if (!before.rowCount) throw new Error("ORDER_NOT_FOUND");

      const operation = await client.query(
        `select * from core.CANCEL_ORDER($1,$2,$3,$4)`,
        [clientId, orderId, reason, principal.email],
      );

      const after = await client.query(
        `select CLIENT_ID,ORDER_ID,ORDER_REFERENCE,STATUS,PAYMENT_STATUS,
                FULFILMENT_STATUS,ORDER_CLOSED,CLOSURE_DATE,SHIPPED_DATE,
                DELIVERED_DSTAMP,ORDER_VALUE,INV_CURRENCY,LAST_UPDATED_BY,
                LAST_UPDATE_DATE
           from core.ORDER_HEADER
          where CLIENT_ID=$1 and ORDER_ID=$2`,
        [clientId, orderId],
      );

      await insertAudit(
        client,
        clientId,
        principal.email,
        "ORDER",
        orderId,
        "CANCEL",
        [reason, notes].filter(Boolean).join(": "),
        before.rows[0],
        after.rows[0],
      );

      await client.query("commit");
      return {
        operation: operation.rows[0],
        order: after.rows[0],
      };
    } catch (e) {
      try {
        await client.query("rollback");
      } catch {}
      return sendError(reply, e);
    } finally {
      client.release();
    }
  });
}
