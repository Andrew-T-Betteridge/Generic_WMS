import type { FastifyInstance, FastifyReply } from "fastify";
import { db } from "./db.js";
import {
  auditAdminChange,
  requirePermission,
} from "./admin-rbac.js";

function codeOf(error: unknown) {
  return String((error as Error)?.message ?? error).split(":")[0];
}

function sendError(reply: FastifyReply, error: unknown) {
  const code = codeOf(error);
  const status =
    code.endsWith("_NOT_FOUND")
      ? 404
      : code.startsWith("INVALID_") || code.endsWith("_REQUIRED")
        ? 400
        : code.includes("PERMISSION") || code.includes("ADMIN_")
          ? 403
          : 409;
  return reply.code(status).send({ error: code });
}

function boundedLimit(raw: unknown, fallback = 50, max = 200) {
  const n = Number(raw ?? fallback);
  return Math.max(1, Math.min(max, Number.isFinite(n) ? Math.floor(n) : fallback));
}

function nonNegativeNumber(value: unknown, field: string) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) throw new Error(`INVALID_${field}`);
  return n;
}

export function registerAdminManagementRoutes(
  app: FastifyInstance,
  clientId: string,
) {
  app.get("/api/admin/dashboard", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "dashboard.read");
      const result = await db.query(
        `select
           (select count(*)::int
              from core.PRODUCT
             where CLIENT_ID=$1 and ACTIVE=true) as active_products,
           (select count(*)::int
              from core.PRODUCT_VARIANT
             where CLIENT_ID=$1 and ACTIVE=true) as active_variants,
           (select count(*)::int
              from core.ORDER_HEADER
             where CLIENT_ID=$1
               and ORDER_DATE >= CURRENT_DATE) as orders_today,
           (select count(*)::int
              from core.ORDER_HEADER
             where CLIENT_ID=$1
               and PAYMENT_STATUS='PAID'
               and ORDER_DATE >= CURRENT_DATE) as paid_orders_today,
           (select COALESCE(sum(ORDER_VALUE),0)
              from core.ORDER_HEADER
             where CLIENT_ID=$1
               and PAYMENT_STATUS='PAID'
               and ORDER_DATE >= CURRENT_DATE) as paid_value_today,
           (select count(*)::int
              from core.INVENTORY
             where CLIENT_ID=$1
               and (QTY_ON_HAND-QTY_ALLOCATED) <= 2) as low_stock_rows,
           (select count(*)::int
              from core.ORDER_HEADER
             where CLIENT_ID=$1
               and PAYMENT_STATUS='PENDING') as pending_payment_orders`,
        [clientId],
      );
      return result.rows[0];
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.get("/api/admin/products", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "product.read");
      const query = req.query as {
        q?: string;
        active?: string;
        limit?: string;
        offset?: string;
      };
      const limit = boundedLimit(query.limit);
      const offset = Math.max(0, Number(query.offset ?? 0) || 0);
      const active =
        query.active == null
          ? null
          : ["1", "true", "yes"].includes(query.active.toLowerCase());
      const search = String(query.q ?? "").trim() || null;

      const result = await db.query(
        `select
            p.PRODUCT_ID,
            p.PRODUCT_NAME,
            p.SLUG,
            p.BRAND_NAME,
            p.CATEGORY_CODE,
            pc.CATEGORY_NAME,
            p.DELIVERY_CLASS,
            p.CURRENCY,
            p.ACTIVE,
            p.FEATURED,
            p.SORT_SEQUENCE,
            p.LAST_UPDATE_DSTAMP,
            count(distinct pv.SKU_ID)::int as variant_count,
            min(pv.WEB_PRICE) as min_price,
            max(pv.WEB_PRICE) as max_price,
            COALESCE(sum(i.QTY_ON_HAND),0) as qty_on_hand,
            COALESCE(sum(i.QTY_ALLOCATED),0) as qty_allocated,
            COALESCE(sum(i.QTY_ON_HAND-i.QTY_ALLOCATED),0) as qty_available
           from core.PRODUCT p
           left join core.PRODUCT_CATEGORY pc
             on pc.CLIENT_ID=p.CLIENT_ID
            and pc.CATEGORY_CODE=p.CATEGORY_CODE
           left join core.PRODUCT_VARIANT pv
             on pv.CLIENT_ID=p.CLIENT_ID
            and pv.PRODUCT_ID=p.PRODUCT_ID
           left join core.INVENTORY i
             on i.CLIENT_ID=pv.CLIENT_ID
            and i.SKU_ID=pv.SKU_ID
          where p.CLIENT_ID=$1
            and ($2::boolean is null or p.ACTIVE=$2)
            and (
              $3::text is null
              or p.PRODUCT_ID ilike '%'||$3||'%'
              or p.PRODUCT_NAME ilike '%'||$3||'%'
              or p.SLUG ilike '%'||$3||'%'
              or pv.SKU_ID ilike '%'||$3||'%'
            )
          group by
            p.PRODUCT_ID,p.PRODUCT_NAME,p.SLUG,p.BRAND_NAME,p.CATEGORY_CODE,
            pc.CATEGORY_NAME,p.DELIVERY_CLASS,p.CURRENCY,p.ACTIVE,p.FEATURED,
            p.SORT_SEQUENCE,p.LAST_UPDATE_DSTAMP
          order by p.SORT_SEQUENCE,p.PRODUCT_NAME
          limit $4 offset $5`,
        [clientId, active, search, limit, offset],
      );
      return result.rows;
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.get("/api/admin/products/:productId", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "product.read");
      const { productId } = req.params as { productId: string };

      const product = await db.query(
        `select p.*,pc.CATEGORY_NAME
           from core.PRODUCT p
           left join core.PRODUCT_CATEGORY pc
             on pc.CLIENT_ID=p.CLIENT_ID
            and pc.CATEGORY_CODE=p.CATEGORY_CODE
          where p.CLIENT_ID=$1 and p.PRODUCT_ID=$2`,
        [clientId, productId],
      );
      if (!product.rowCount) throw new Error("PRODUCT_NOT_FOUND");

      const variants = await db.query(
        `select
            pv.*,
            s.WEB_ACTIVE,
            s.WEB_FEATURED,
            s.EACH_WEIGHT,
            s.EACH_HEIGHT,
            s.EACH_WIDTH,
            s.EACH_DEPTH,
            COALESCE(sum(i.QTY_ON_HAND),0) as QTY_ON_HAND,
            COALESCE(sum(i.QTY_ALLOCATED),0) as QTY_ALLOCATED,
            COALESCE(sum(i.QTY_ON_HAND-i.QTY_ALLOCATED),0) as QTY_AVAILABLE
           from core.PRODUCT_VARIANT pv
           join core.SKU s
             on s.CLIENT_ID=pv.CLIENT_ID and s.SKU_ID=pv.SKU_ID
           left join core.INVENTORY i
             on i.CLIENT_ID=pv.CLIENT_ID and i.SKU_ID=pv.SKU_ID
          where pv.CLIENT_ID=$1 and pv.PRODUCT_ID=$2
          group by
            pv.CLIENT_ID,pv.PRODUCT_ID,pv.SKU_ID,pv.VARIANT_NAME,pv.OPTION_VALUES,
            pv.WEB_PRICE,pv.ACTIVE,pv.SORT_SEQUENCE,pv.CREATED_DSTAMP,
            pv.LAST_UPDATE_DSTAMP,pv.SALE_TYPE,pv.AVAILABILITY_STATE,
            pv.EXPECTED_AVAILABLE_FROM,pv.EXPECTED_AVAILABLE_TO,pv.MIN_ORDER_QTY,
            pv.MAX_ORDER_QTY,pv.QTY_INCREMENT,
            s.WEB_ACTIVE,s.WEB_FEATURED,s.EACH_WEIGHT,s.EACH_HEIGHT,s.EACH_WIDTH,s.EACH_DEPTH
          order by pv.SORT_SEQUENCE,pv.SKU_ID`,
        [clientId, productId],
      );

      return { ...product.rows[0], variants: variants.rows };
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.post("/api/admin/products", async (req, reply) => {
    try {
      const principal = await requirePermission(req, clientId, "product.create");
      const body = (req.body ?? {}) as Record<string, unknown>;
      const productId = String(body.productId ?? "").trim().toUpperCase();
      const productName = String(body.productName ?? "").trim();
      const slug = String(body.slug ?? "").trim().toLowerCase();
      const categoryCode = String(body.categoryCode ?? "").trim().toUpperCase();
      const deliveryClass = String(body.deliveryClass ?? "STANDARD")
        .trim()
        .toUpperCase();
      const currency = String(body.currency ?? "GBP").trim().toUpperCase();

      if (!/^[A-Z0-9_-]{2,50}$/.test(productId))
        throw new Error("INVALID_PRODUCT_ID");
      if (!productName || productName.length > 150)
        throw new Error("INVALID_PRODUCT_NAME");
      if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug))
        throw new Error("INVALID_SLUG");
      if (!categoryCode) throw new Error("CATEGORY_REQUIRED");

      const created = await db.query(
        `insert into core.PRODUCT
          (CLIENT_ID,PRODUCT_ID,PRODUCT_NAME,SLUG,BRAND_NAME,CATEGORY_CODE,
           SHORT_DESCRIPTION,DESCRIPTION,DELIVERY_CLASS,CURRENCY,MEDIA,SPECIFICATION,
           ACTIVE,FEATURED,SORT_SEQUENCE)
         values
          ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb,$12::jsonb,$13,$14,$15)
         returning *`,
        [
          clientId,
          productId,
          productName,
          slug,
          body.brandName ?? null,
          categoryCode,
          body.shortDescription ?? null,
          body.description ?? null,
          deliveryClass,
          currency,
          JSON.stringify(body.media ?? []),
          JSON.stringify(body.specification ?? {}),
          body.active !== false,
          body.featured === true,
          Number(body.sortSequence ?? 100),
        ],
      );

      await auditAdminChange(
        clientId,
        principal,
        "PRODUCT",
        productId,
        "CREATE",
        null,
        created.rows[0],
      );
      return reply.code(201).send(created.rows[0]);
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.patch("/api/admin/products/:productId", async (req, reply) => {
    try {
      const principal = await requirePermission(req, clientId, "product.update");
      const { productId } = req.params as { productId: string };
      const body = (req.body ?? {}) as Record<string, unknown>;

      if (body.active === false) {
        await requirePermission(req, clientId, "product.deactivate");
      }

      const before = await db.query(
        "select * from core.PRODUCT where CLIENT_ID=$1 and PRODUCT_ID=$2",
        [clientId, productId],
      );
      if (!before.rowCount) throw new Error("PRODUCT_NOT_FOUND");

      const map: Record<string, string> = {
        productName: "PRODUCT_NAME",
        slug: "SLUG",
        brandName: "BRAND_NAME",
        categoryCode: "CATEGORY_CODE",
        shortDescription: "SHORT_DESCRIPTION",
        description: "DESCRIPTION",
        deliveryClass: "DELIVERY_CLASS",
        media: "MEDIA",
        specification: "SPECIFICATION",
        active: "ACTIVE",
        featured: "FEATURED",
        sortSequence: "SORT_SEQUENCE",
      };

      const sets: string[] = [];
      const values: unknown[] = [clientId, productId];
      for (const [field, column] of Object.entries(map)) {
        if (!(field in body)) continue;
        let value = body[field];
        if (field === "media" || field === "specification") {
          value = JSON.stringify(value ?? (field === "media" ? [] : {}));
          sets.push(`${column}=$${values.length + 1}::jsonb`);
        } else {
          sets.push(`${column}=$${values.length + 1}`);
        }
        values.push(value);
      }

      if (!sets.length) return before.rows[0];
      sets.push("LAST_UPDATE_DSTAMP=now()");

      const updated = await db.query(
        `update core.PRODUCT
            set ${sets.join(",")}
          where CLIENT_ID=$1 and PRODUCT_ID=$2
          returning *`,
        values,
      );

      await auditAdminChange(
        clientId,
        principal,
        "PRODUCT",
        productId,
        "UPDATE",
        before.rows[0],
        updated.rows[0],
      );
      return updated.rows[0];
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.patch("/api/admin/variants/:skuId", async (req, reply) => {
    const client = await db.connect();
    try {
      const principal = await requirePermission(req, clientId, "product.update");
      const { skuId } = req.params as { skuId: string };
      const body = (req.body ?? {}) as Record<string, unknown>;

      if ("webPrice" in body) {
        await requirePermission(req, clientId, "pricing.update");
      }
      if (body.active === false || body.webActive === "N") {
        await requirePermission(req, clientId, "product.deactivate");
      }

      const before = await db.query(
        `select row_to_json(x) as data
           from (
             select pv.*,s.WEB_ACTIVE,s.WEB_FEATURED,s.EACH_WEIGHT,s.EACH_HEIGHT,
                    s.EACH_WIDTH,s.EACH_DEPTH
               from core.PRODUCT_VARIANT pv
               join core.SKU s
                 on s.CLIENT_ID=pv.CLIENT_ID and s.SKU_ID=pv.SKU_ID
              where pv.CLIENT_ID=$1 and pv.SKU_ID=$2
           ) x`,
        [clientId, skuId],
      );
      if (!before.rowCount) throw new Error("VARIANT_NOT_FOUND");

      const variantMap: Record<string, string> = {
        variantName: "VARIANT_NAME",
        optionValues: "OPTION_VALUES",
        webPrice: "WEB_PRICE",
        active: "ACTIVE",
        sortSequence: "SORT_SEQUENCE",
        saleType: "SALE_TYPE",
        availabilityState: "AVAILABILITY_STATE",
        expectedAvailableFrom: "EXPECTED_AVAILABLE_FROM",
        expectedAvailableTo: "EXPECTED_AVAILABLE_TO",
        minOrderQty: "MIN_ORDER_QTY",
        maxOrderQty: "MAX_ORDER_QTY",
        qtyIncrement: "QTY_INCREMENT",
      };
      const skuMap: Record<string, string> = {
        webActive: "WEB_ACTIVE",
        webFeatured: "WEB_FEATURED",
        eachWeight: "EACH_WEIGHT",
        eachHeight: "EACH_HEIGHT",
        eachWidth: "EACH_WIDTH",
        eachDepth: "EACH_DEPTH",
      };

      await client.query("begin");

      const vSets: string[] = [];
      const vValues: unknown[] = [clientId, skuId];
      for (const [field, column] of Object.entries(variantMap)) {
        if (!(field in body)) continue;
        let value = body[field];
        if (field === "optionValues") {
          value = JSON.stringify(value ?? {});
          vSets.push(`${column}=$${vValues.length + 1}::jsonb`);
        } else {
          if (
            ["webPrice", "minOrderQty", "maxOrderQty", "qtyIncrement"].includes(field) &&
            value != null
          ) {
            value = nonNegativeNumber(value, field.toUpperCase());
          }
          vSets.push(`${column}=$${vValues.length + 1}`);
        }
        vValues.push(value);
      }
      if (vSets.length) {
        vSets.push("LAST_UPDATE_DSTAMP=now()");
        await client.query(
          `update core.PRODUCT_VARIANT
              set ${vSets.join(",")}
            where CLIENT_ID=$1 and SKU_ID=$2`,
          vValues,
        );
      }

      const sSets: string[] = [];
      const sValues: unknown[] = [clientId, skuId];
      for (const [field, column] of Object.entries(skuMap)) {
        if (!(field in body)) continue;
        let value = body[field];
        if (
          ["eachWeight", "eachHeight", "eachWidth", "eachDepth"].includes(field) &&
          value != null
        ) {
          value = nonNegativeNumber(value, field.toUpperCase());
        }
        sSets.push(`${column}=$${sValues.length + 1}`);
        sValues.push(value);
      }
      if (sSets.length) {
        await client.query(
          `update core.SKU
              set ${sSets.join(",")}
            where CLIENT_ID=$1 and SKU_ID=$2`,
          sValues,
        );
      }

      const after = await client.query(
        `select row_to_json(x) as data
           from (
             select pv.*,s.WEB_ACTIVE,s.WEB_FEATURED,s.EACH_WEIGHT,s.EACH_HEIGHT,
                    s.EACH_WIDTH,s.EACH_DEPTH
               from core.PRODUCT_VARIANT pv
               join core.SKU s
                 on s.CLIENT_ID=pv.CLIENT_ID and s.SKU_ID=pv.SKU_ID
              where pv.CLIENT_ID=$1 and pv.SKU_ID=$2
           ) x`,
        [clientId, skuId],
      );
      await client.query("commit");

      await auditAdminChange(
        clientId,
        principal,
        "PRODUCT_VARIANT",
        skuId,
        "UPDATE",
        before.rows[0].data,
        after.rows[0].data,
      );
      return after.rows[0].data;
    } catch (e) {
      try {
        await client.query("rollback");
      } catch {}
      return sendError(reply, e);
    } finally {
      client.release();
    }
  });

  app.get("/api/admin/inventory", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "inventory.read");
      const query = req.query as {
        q?: string;
        locationId?: string;
        limit?: string;
        offset?: string;
      };
      const limit = boundedLimit(query.limit, 100, 500);
      const offset = Math.max(0, Number(query.offset ?? 0) || 0);
      const search = String(query.q ?? "").trim() || null;
      const locationId = String(query.locationId ?? "").trim() || null;

      const result = await db.query(
        `select
            i.KEY as INVENTORY_KEY,
            i.SKU_ID,
            p.PRODUCT_ID,
            p.PRODUCT_NAME,
            pv.VARIANT_NAME,
            i.SITE_ID,
            i.LOCATION_ID,
            i.QTY_ON_HAND,
            i.QTY_ALLOCATED,
            (i.QTY_ON_HAND-i.QTY_ALLOCATED) as QTY_AVAILABLE,
            i.LOCK_STATUS,
            i.LOCK_CODE,
            i.DISALLOW_ALLOC,
            i.BATCH_ID,
            i.EXPIRY_DSTAMP,
            i.RECEIPT_DSTAMP,
            i.MOVE_DSTAMP
           from core.INVENTORY i
           left join core.PRODUCT_VARIANT pv
             on pv.CLIENT_ID=i.CLIENT_ID and pv.SKU_ID=i.SKU_ID
           left join core.PRODUCT p
             on p.CLIENT_ID=pv.CLIENT_ID and p.PRODUCT_ID=pv.PRODUCT_ID
          where i.CLIENT_ID=$1
            and ($2::text is null
              or i.SKU_ID ilike '%'||$2||'%'
              or p.PRODUCT_NAME ilike '%'||$2||'%')
            and ($3::varchar is null or i.LOCATION_ID=$3)
          order by i.SKU_ID,i.LOCATION_ID,i.KEY
          limit $4 offset $5`,
        [clientId, search, locationId, limit, offset],
      );
      return result.rows;
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.get("/api/admin/orders", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "order.read");
      const query = req.query as {
        q?: string;
        status?: string;
        paymentStatus?: string;
        limit?: string;
        offset?: string;
      };
      const limit = boundedLimit(query.limit);
      const offset = Math.max(0, Number(query.offset ?? 0) || 0);
      const search = String(query.q ?? "").trim() || null;

      const result = await db.query(
        `select
            oh.ORDER_ID,
            oh.ORDER_REFERENCE,
            oh.ORDER_DATE,
            oh.STATUS,
            oh.PAYMENT_STATUS,
            oh.FULFILMENT_STATUS,
            oh.DISPATCH_METHOD,
            oh.CARRIER_ID,
            oh.SERVICE_LEVEL,
            oh.ORDER_VALUE,
            oh.FREIGHT_COST,
            oh.INV_CURRENCY as CURRENCY,
            oh.CUSTOMER_ID,
            oh.NAME,
            oh.CONTACT,
            oh.CONTACT_EMAIL,
            oh.CONTACT_PHONE,
            oh.CONTACT_MOBILE,
            oh.POSTCODE,
            oh.TOWN,
            oh.COUNTY,
            oh.COUNTRY,
            oh.LAST_UPDATE_DATE
           from core.ORDER_HEADER oh
          where oh.CLIENT_ID=$1
            and ($2::text is null
              or oh.ORDER_ID ilike '%'||$2||'%'
              or COALESCE(oh.ORDER_REFERENCE,'') ilike '%'||$2||'%'
              or COALESCE(oh.NAME,'') ilike '%'||$2||'%'
              or COALESCE(oh.CONTACT,'') ilike '%'||$2||'%'
              or COALESCE(oh.CONTACT_EMAIL,'') ilike '%'||$2||'%'
              or COALESCE(oh.POSTCODE,'') ilike '%'||$2||'%')
            and ($3::varchar is null or oh.STATUS=$3)
            and ($4::varchar is null or oh.PAYMENT_STATUS=$4)
          order by oh.ORDER_DATE desc,oh.ORDER_ID desc
          limit $5 offset $6`,
        [
          clientId,
          search,
          query.status ?? null,
          query.paymentStatus ?? null,
          limit,
          offset,
        ],
      );
      return result.rows;
    } catch (e) {
      return sendError(reply, e);
    }
  });

  app.get("/api/admin/orders/:orderId", async (req, reply) => {
    try {
      await requirePermission(req, clientId, "order.read");
      const { orderId } = req.params as { orderId: string };
      const order = await db.query(
        `select
            oh.*,
            jsonb_build_object(
              'name',oh.NAME,
              'contact',oh.CONTACT,
              'contactPhone',oh.CONTACT_PHONE,
              'contactMobile',oh.CONTACT_MOBILE,
              'contactEmail',oh.CONTACT_EMAIL,
              'address1',oh.ADDRESS1,
              'address2',oh.ADDRESS2,
              'town',oh.TOWN,
              'county',oh.COUNTY,
              'postcode',oh.POSTCODE,
              'country',oh.COUNTRY
            ) as DELIVERY_ADDRESS
           from core.ORDER_HEADER oh
          where oh.CLIENT_ID=$1 and oh.ORDER_ID=$2`,
        [clientId, orderId],
      );
      if (!order.rowCount) throw new Error("ORDER_NOT_FOUND");

      const lines = await db.query(
        `select ol.*,p.PRODUCT_ID,p.PRODUCT_NAME,pv.VARIANT_NAME
           from core.ORDER_LINE ol
           left join core.PRODUCT_VARIANT pv
             on pv.CLIENT_ID=ol.CLIENT_ID and pv.SKU_ID=ol.SKU_ID
           left join core.PRODUCT p
             on p.CLIENT_ID=pv.CLIENT_ID and p.PRODUCT_ID=pv.PRODUCT_ID
          where ol.CLIENT_ID=$1 and ol.ORDER_ID=$2
          order by ol.LINE_ID`,
        [clientId, orderId],
      );

      const payments = await db.query(
        `select PAYMENT_ID,PROVIDER,PROVIDER_REFERENCE,AMOUNT,CAPTURED_AMOUNT,
                REFUNDED_AMOUNT,CURRENCY,STATUS,PROVIDER_STATUS,IDEMPOTENCY_KEY,
                LAST_EVENT_TYPE,LAST_EVENT_DSTAMP,CREATED_DSTAMP,LAST_UPDATE_DSTAMP
           from core.PAYMENT_TRANSACTION
          where CLIENT_ID=$1
            and REFERENCE_TYPE='ORDER'
            and REFERENCE_ID=$2
          order by CREATED_DSTAMP desc`,
        [clientId, orderId],
      );

      return {
        ...order.rows[0],
        lines: lines.rows,
        payments: payments.rows,
      };
    } catch (e) {
      return sendError(reply, e);
    }
  });
}
