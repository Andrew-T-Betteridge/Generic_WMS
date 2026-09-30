import type { FastifyInstance, FastifyReply } from "fastify";
import crypto from "node:crypto";
import { db } from "./db.js";
import { auditAdminChange, requirePermission, resolveAdminPrincipal } from "./admin-rbac.js";
import { createStripeRefund } from "./stripe.js";

function codeOf(e: unknown) { return String((e as Error)?.message ?? e).split(":")[0]; }
function sendError(reply: FastifyReply,e: unknown) {
  const c=codeOf(e);
  const s=c==="AUTHENTICATION_REQUIRED"||c.startsWith("AUTH_")?401:
          c.includes("PERMISSION")||c.includes("ADMIN_ACCESS")||c==="ADMIN_REQUIRED"?403:
          c.endsWith("_NOT_FOUND")?404:
          c.startsWith("INVALID_")||c.endsWith("_REQUIRED")?400:
          c.includes("NOT_ALLOWED")||c.includes("NOT_RETRYABLE")||c.includes("CONFLICT")?409:500;
  return reply.code(s).send({error:c});
}
function lim(v:unknown,d=50,m=250){const n=Number(v??d);return Math.max(1,Math.min(m,Number.isFinite(n)?Math.floor(n):d));}
function off(v:unknown){const n=Number(v??0);return Math.max(0,Number.isFinite(n)?Math.floor(n):0);}
function actor(p:Awaited<ReturnType<typeof resolveAdminPrincipal>>){return p.email||p.subject||"ADMIN";}
async function attempt(clientId:string,p:any,actionCode:string,entityType:string,entityId:string,permission:string,result:string,reason?:string|null,detail?:unknown){
  await db.query(`insert into audit.ADMIN_ACTION_ATTEMPT
   (CLIENT_ID,ADMIN_USER_ID,ADMIN_EMAIL,ACTION_CODE,ENTITY_TYPE,ENTITY_ID,PERMISSION_CODE,RESULT,REASON,DETAIL)
   values($1,$2::uuid,$3,$4,$5,$6,$7,$8,$9,$10::jsonb)`,
   [clientId,p.adminUserId,p.email,actionCode,entityType,entityId,permission,result,reason??null,JSON.stringify(detail??{})]);
}
export function registerAdminOperationsRoutes(app:FastifyInstance,clientId:string){


  // 0.3.18 operational context.
  // SITE is an independent master. config.CLIENT_SITE only describes
  // which client/site combinations are operationally applicable.
  app.get("/api/admin/context", async (req, reply) => {
    const principal = await requirePermission(req, clientId, "dashboard.read");

    const sites = await db.query(
      `select
          s.SITE_ID as site_id,
          s.DESCRIPTION as description,
          s.SITE_TYPE as site_type,
          s.TIME_ZONE as time_zone,
          cs.DEFAULT_FULFILMENT as default_fulfilment
         from config.CLIENT_SITE cs
         join core.SITE s
           on s.SITE_ID=cs.SITE_ID
          and s.ACTIVE=true
        where cs.CLIENT_ID=$1
          and cs.ACTIVE=true
        order by cs.DEFAULT_FULFILMENT desc, s.SITE_ID`,
      [clientId],
    );

    return {
      clientId,
      sites: sites.rows,
      principal: {
        email: principal.email,
        displayName: principal.displayName,
        permissions: principal.permissions,
      },
    };
  });

app.get("/api/admin/operations/dashboard",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"dashboard.read");
      const [s,e]=await Promise.all([
        db.query(`select
          (select count(*)::int from core.ORDER_HEADER where CLIENT_ID=$1 and STATUS not in('SHIPPED','DELIVERED','CANCELLED')) outstanding_orders,
          (select count(*)::int from core.ORDER_HEADER where CLIENT_ID=$1 and PAYMENT_STATUS='PENDING' and STATUS<>'CANCELLED') payment_attention,
          (select count(*)::int from core.ADMIN_EXCEPTION_WORKBENCH where CLIENT_ID=$1) exception_count,
          (select count(*)::int from core.PICK_TASK where CLIENT_ID=$1 and STATUS in('OPEN','PART_PICKED')) open_picks,
          (select count(*)::int from interface.NOTIFICATION_OUTBOX where CLIENT_ID=$1 and STATUS in('FAILED','ERROR')) failed_notifications,
          (select count(*)::int from core.RETURN_CASE where CLIENT_ID=$1 and STATUS not in('CLOSED','REJECTED')) open_cases`,[clientId]),
        db.query(`select * from core.ADMIN_EXCEPTION_WORKBENCH where CLIENT_ID=$1 order by AGE_MINUTES desc nulls last limit 25`,[clientId])
      ]);
      return {summary:s.rows[0],topExceptions:e.rows};
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/exceptions",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"exception.read");
      const q=req.query as any;
      const r=await db.query(`select * from core.ADMIN_EXCEPTION_WORKBENCH
       where CLIENT_ID=$1 and ($2::text is null or EXCEPTION_TYPE=$2)
       order by AGE_MINUTES desc nulls last limit $3 offset $4`,
       [clientId,q.type??null,lim(q.limit),off(q.offset)]);
      return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/orders",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"order.read");
      const q=req.query as any; const x=String(q.q??"").trim()||null;
      const r=await db.query(`select * from core.ADMIN_ORDER_CONTROL_WORKBENCH
       where CLIENT_ID=$1
       and ($2::text is null or ORDER_ID ilike '%'||$2||'%' or CUSTOMER_ID ilike '%'||$2||'%' or CONTACT_EMAIL ilike '%'||$2||'%')
       and ($3::text is null or PAYMENT_STATUS=$3)
       and ($4::text is null or FULFILMENT_STATUS=$4)
       order by ORDER_DATE desc limit $5 offset $6`,
       [clientId,x,q.paymentStatus?.toUpperCase()??null,q.fulfilmentStatus?.toUpperCase()??null,lim(q.limit),off(q.offset)]);
      return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/orders/:orderId",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"order.read");
      const {orderId}=req.params as any;
      const [h,l,a,p,c,m,pay,n,au,no]=await Promise.all([
        db.query(`select * from core.ORDER_HEADER where CLIENT_ID=$1 and ORDER_ID=$2`,[clientId,orderId]),
        db.query(`select * from core.ORDER_LINE where CLIENT_ID=$1 and ORDER_ID=$2 order by LINE_ID`,[clientId,orderId]),
        db.query(`select * from core.ALLOCATION where CLIENT_ID=$1 and ORDER_ID=$2 order by ALLOCATION_ID`,[clientId,orderId]),
        db.query(`select * from core.PICK_TASK where CLIENT_ID=$1 and ORDER_ID=$2 order by CREATED_DSTAMP`,[clientId,orderId]),
        db.query(`select * from core.ORDER_CONTAINER where CLIENT_ID=$1 and ORDER_ID=$2 order by CREATED_DSTAMP`,[clientId,orderId]),
        db.query(`select * from core.SHIPPING_MANIFEST where CLIENT_ID=$1 and ORDER_ID=$2 order by KEY`,[clientId,orderId]),
        db.query(`select * from core.PAYMENT_TRANSACTION where CLIENT_ID=$1 and REFERENCE_ID=$2 order by CREATED_DSTAMP`,[clientId,orderId]),
        db.query(`select * from core.ORDER_NOTE where CLIENT_ID=$1 and ORDER_ID=$2 order by CREATED_DSTAMP desc`,[clientId,orderId]),
        db.query(`select * from audit.AUDIT_EVENT where (CLIENT_ID=$1 or CLIENT_ID is null) and ENTITY_ID=$2 order by CREATED_DSTAMP desc limit 250`,[clientId,orderId]),
        db.query(`select * from audit.ADMIN_NOTIFICATION_EVENT where CLIENT_ID=$1 and ORDER_ID=$2 order by CREATED_DSTAMP desc`,[clientId,orderId])
      ]);
      if(!h.rowCount)throw new Error("ORDER_NOT_FOUND");
      return {order:h.rows[0],lines:l.rows,allocations:a.rows,picks:p.rows,containers:c.rows,shipmentManifest:m.rows,payments:pay.rows,notes:n.rows,audit:au.rows,notifications:no.rows};
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/orders/:orderId/actions",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"order.read");
      const {orderId}=req.params as any;
      const [o,a,p,c]=await Promise.all([
        db.query(`select * from core.ORDER_HEADER where CLIENT_ID=$1 and ORDER_ID=$2`,[clientId,orderId]),
        db.query(`select count(*)::int n,coalesce(sum(QTY_PICKED),0) picked from core.ALLOCATION where CLIENT_ID=$1 and ORDER_ID=$2 and STATUS not in('RELEASED','CANCELLED')`,[clientId,orderId]),
        db.query(`select count(*)::int open from core.PICK_TASK where CLIENT_ID=$1 and ORDER_ID=$2 and STATUS in('OPEN','STARTED')`,[clientId,orderId]),
        db.query(`select count(*)::int shipped from core.ORDER_CONTAINER where CLIENT_ID=$1 and ORDER_ID=$2 and STATUS='SHIPPED'`,[clientId,orderId])
      ]);
      if(!o.rowCount)throw new Error("ORDER_NOT_FOUND");
      const x=o.rows[0], shipped=Number(c.rows[0]?.shipped??0), picked=Number(a.rows[0]?.picked??0), alloc=Number(a.rows[0]?.n??0);
      const ps=String(x.payment_status??""), fs=String(x.fulfilment_status??"");
      return {
        amendHeader:{allowed:shipped===0&&!["CANCELLED","SHIPPED","COMPLETE"].includes(fs),permission:"order.amend"},
        amendLines:{allowed:shipped===0&&picked===0&&alloc===0&&!["PAID","AUTHORISED","PART_REFUNDED","REFUNDED"].includes(ps),permission:"order.amend"},
        allocate:{allowed:["PAID","AUTHORISED"].includes(ps)&&["UNALLOCATED","RESERVED","PART_ALLOCATED"].includes(fs),permission:"order.allocate"},
        deallocate:{allowed:alloc>0&&shipped===0,permission:"order.deallocate"},
        createPicks:{allowed:alloc>0&&shipped===0,permission:"order.pick.create"},
        cancel:{allowed:shipped===0,permission:"order.cancel",refundRecommended:["PAID","AUTHORISED","PART_REFUNDED"].includes(ps),reason:shipped?"Order contains shipped containers.":null}
      };
    }catch(e){return sendError(reply,e);}
  });

  app.patch("/api/admin/orders/:orderId",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"order.amend");
      const {orderId}=req.params as any; const b=(req.body??{}) as any;
      if(!b.reason)throw new Error("REASON_REQUIRED");
      const r=await db.query(`select core.AMEND_ORDER_HEADER($1,$2,$3::jsonb,$4,$5) data`,
       [clientId,orderId,JSON.stringify(b.patch??{}),b.reason,actor(p)]);
      return r.rows[0].data;
    }catch(e){return sendError(reply,e);}
  });

  app.patch("/api/admin/orders/:orderId/lines/:lineId",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"order.amend");
      const {orderId,lineId}=req.params as any; const b=(req.body??{}) as any;
      if(!b.reason)throw new Error("REASON_REQUIRED");
      const r=await db.query(`select core.AMEND_ORDER_LINE_PRE_FULFILMENT($1,$2,$3,$4::jsonb,$5,$6) data`,
       [clientId,orderId,lineId,JSON.stringify(b.patch??{}),b.reason,actor(p)]);
      return r.rows[0].data;
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/orders/:orderId/notes",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"order.note");const {orderId}=req.params as any;const b=(req.body??{}) as any;
      const r=await db.query(`select core.ADD_ORDER_NOTE($1,$2,$3,$4,$5,$6) id`,
       [clientId,orderId,b.type??"INTERNAL",b.text??"",b.important===true,actor(p)]);
      return reply.code(201).send({orderNoteId:r.rows[0].id});
    }catch(e){return sendError(reply,e);}
  });

  for (const [path,perm,fn,args] of [
    ["allocate","order.allocate","ALLOCATE_ORDER",(p:any,b:any,oid:string)=>[clientId,oid]],
    ["deallocate","order.deallocate","DEALLOCATE_ORDER",(p:any,b:any,oid:string)=>[clientId,oid]],
    ["create-picks","order.pick.create","CREATE_PICK_TASKS",(p:any,b:any,oid:string)=>[clientId,oid,actor(p)]],
  ] as const){
    app.post(`/api/admin/orders/:orderId/${path}`,async(req,reply)=>{
      try{
        const p=await requirePermission(req,clientId,perm);const {orderId}=req.params as any;const b=req.body??{};
        const values=args(p,b,orderId);const placeholders=values.map((_:any,i:number)=>`$${i+1}`).join(",");
        const r=await db.query(`select * from core.${fn}(${placeholders})`,values);
        await attempt(clientId,p,`ORDER_${path.toUpperCase().replace("-","_")}`,"ORDER",orderId,perm,"SUCCESS",null,r.rows[0]);
        return r.rows[0];
      }catch(e){return sendError(reply,e);}
    });
  }

  app.post("/api/admin/orders/:orderId/cancel",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"order.cancel");const {orderId}=req.params as any;const b=(req.body??{}) as any;
      if(!b.reasonCode)throw new Error("REASON_CODE_REQUIRED");
      const r=await db.query(`select * from core.CANCEL_ORDER($1,$2,$3,$4)`,[clientId,orderId,b.reasonCode,actor(p)]);
      await attempt(clientId,p,"ORDER_CANCEL","ORDER",orderId,"order.cancel","SUCCESS",b.notes??b.reasonCode,r.rows[0]);
      return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });


  // Customer operational projection derived from authoritative order history.
  app.get("/api/admin/customers", async (req, reply) => {
    await requirePermission(req, clientId, "order.read");

    const query = req.query as {
      q?: string;
      siteId?: string;
      limit?: string;
      offset?: string;
    };

    const q = String(query.q ?? "").trim();
    const siteId = String(query.siteId ?? "").trim() || null;
    const limit = Math.min(Math.max(Number(query.limit ?? 50) || 50, 1), 200);
    const offset = Math.max(Number(query.offset ?? 0) || 0, 0);

    if (siteId) {
      const allowed = await db.query(
        `select 1
           from config.CLIENT_SITE
          where CLIENT_ID=$1
            and SITE_ID=$2
            and ACTIVE=true`,
        [clientId, siteId],
      );

      if (!allowed.rowCount)
        return reply.code(403).send({ error: "SITE_NOT_AUTHORISED" });
    }

    const result = await db.query(
      `with customer_orders as (
         select
           nullif(trim(CUSTOMER_ID),'') as customer_id,
           nullif(trim(CUSTOMER_EMAIL),'') as email,
           nullif(trim(CUSTOMER_PHONE),'') as phone,
           nullif(trim(
             concat_ws(' ',
               nullif(trim(CUSTOMER_FIRST_NAME),''),
               nullif(trim(CUSTOMER_LAST_NAME),'')
             )
           ),'') as customer_name,
           ORDER_ID,
           SITE_ID,
           ORDER_TOTAL,
           CREATED_DSTAMP
         from core.ORDER_HEADER
        where CLIENT_ID=$1
          and ($2::varchar is null or SITE_ID=$2)
       ),
       grouped as (
         select
           coalesce(
             customer_id,
             lower(email),
             lower(customer_name) || ':' || coalesce(phone,'')
           ) as customer_key,
           max(customer_id) as customer_id,
           max(email) as email,
           max(phone) as phone,
           max(customer_name) as customer_name,
           count(*)::integer as order_count,
           coalesce(sum(ORDER_TOTAL),0) as lifetime_value,
           max(CREATED_DSTAMP) as last_order_at,
           (array_agg(ORDER_ID order by CREATED_DSTAMP desc))[1] as last_order_id
         from customer_orders
        where customer_id is not null
           or email is not null
           or customer_name is not null
        group by coalesce(
          customer_id,
          lower(email),
          lower(customer_name) || ':' || coalesce(phone,'')
        )
       )
       select *
         from grouped
        where $3=''
           or coalesce(customer_id,'') ilike '%' || $3 || '%'
           or coalesce(email,'') ilike '%' || $3 || '%'
           or coalesce(phone,'') ilike '%' || $3 || '%'
           or coalesce(customer_name,'') ilike '%' || $3 || '%'
        order by last_order_at desc nulls last
        limit $4 offset $5`,
      [clientId, siteId, q, limit, offset],
    );

    return {
      items: result.rows,
      limit,
      offset,
      siteId,
      query: q,
    };
  });

  app.get("/api/admin/customers/:customerKey", async (req, reply) => {
    await requirePermission(req, clientId, "order.read");

    const { customerKey } = req.params as { customerKey: string };
    const query = req.query as { siteId?: string };
    const siteId = String(query.siteId ?? "").trim() || null;

    if (siteId) {
      const allowed = await db.query(
        `select 1
           from config.CLIENT_SITE
          where CLIENT_ID=$1
            and SITE_ID=$2
            and ACTIVE=true`,
        [clientId, siteId],
      );

      if (!allowed.rowCount)
        return reply.code(403).send({ error: "SITE_NOT_AUTHORISED" });
    }

    const orders = await db.query(
      `select
          ORDER_ID,
          SITE_ID,
          ORDER_STATUS,
          PAYMENT_STATUS,
          FULFILMENT_STATUS,
          CUSTOMER_ID,
          CUSTOMER_EMAIL,
          CUSTOMER_PHONE,
          CUSTOMER_FIRST_NAME,
          CUSTOMER_LAST_NAME,
          ORDER_TOTAL,
          CREATED_DSTAMP
         from core.ORDER_HEADER
        where CLIENT_ID=$1
          and ($2::varchar is null or SITE_ID=$2)
          and (
               CUSTOMER_ID=$3
            or lower(CUSTOMER_EMAIL)=lower($3)
          )
        order by CREATED_DSTAMP desc`,
      [clientId, siteId, customerKey],
    );

    if (!orders.rowCount)
      return reply.code(404).send({ error: "CUSTOMER_NOT_FOUND" });

    const first = orders.rows[0];

    return {
      customer: {
        customerId: first.customer_id,
        email: first.customer_email,
        phone: first.customer_phone,
        firstName: first.customer_first_name,
        lastName: first.customer_last_name,
        orderCount: orders.rowCount,
      },
      orders: orders.rows,
    };
  });

app.get("/api/admin/inventory",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"inventory.read");const q=req.query as any;const x=String(q.q??"").trim()||null;
      const r=await db.query(`select * from core.INVENTORY_AVAILABILITY where CLIENT_ID=$1
       and ($2::text is null or SKU_ID ilike '%'||$2||'%' or coalesce(BATCH_ID,'') ilike '%'||$2||'%')
       and ($3::text is null or LOCATION_ID=$3) order by SKU_ID,LOCATION_ID,RECEIPT_DSTAMP limit $4 offset $5`,
       [clientId,x,q.locationId??null,lim(q.limit),off(q.offset)]);
      return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/inventory/:inventoryKey/adjust",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"inventory.adjust");const {inventoryKey}=req.params as any;const b=(req.body??{}) as any;
      if(!b.reasonCode)throw new Error("REASON_CODE_REQUIRED");const qty=Number(b.adjustmentQty);
      if(!Number.isFinite(qty)||qty===0)throw new Error("INVALID_ADJUSTMENT_QTY");
      const r=await db.query(`select * from core.ADJUST_INVENTORY($1,$2::bigint,$3,$4,$5,$6,$7)`,
       [clientId,inventoryKey,qty,b.reasonCode,b.notes??null,actor(p),b.stationId??"ADMIN"]);
      return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });


  app.post("/api/admin/inventory/:inventoryKey/count", async (req, reply) => {
    const principal = await requirePermission(req, clientId, "inventory.adjust");
    const { inventoryKey } = req.params as { inventoryKey: string };

    const body = req.body as {
      newQuantity?: number;
      expectedCurrentQuantity?: number;
      reasonCode?: string;
      note?: string;
      siteId?: string;
      operationId?: string;
    };

    const newQuantity = Number(body.newQuantity);
    const expectedCurrent = Number(body.expectedCurrentQuantity);

    if (!Number.isFinite(newQuantity) || newQuantity < 0)
      return reply.code(400).send({ error: "INVALID_NEW_QUANTITY" });

    if (!Number.isFinite(expectedCurrent) || expectedCurrent < 0)
      return reply.code(400).send({ error: "EXPECTED_CURRENT_QUANTITY_REQUIRED" });

    if (!body.reasonCode)
      return reply.code(400).send({ error: "REASON_CODE_REQUIRED" });

    const cx = await db.connect();

    try {
      await cx.query("begin");

      const rowResult = await cx.query(
        `select
            KEY,
            CLIENT_ID,
            SITE_ID,
            SKU_ID,
            LOCATION_ID,
            QTY_ON_HAND
           from core.INVENTORY
          where KEY=$1
            and CLIENT_ID=$2
          for update`,
        [inventoryKey, clientId],
      );

      if (!rowResult.rowCount) {
        await cx.query("rollback");
        return reply.code(404).send({ error: "INVENTORY_NOT_FOUND" });
      }

      const row = rowResult.rows[0];

      if (body.siteId && row.site_id !== body.siteId) {
        await cx.query("rollback");
        return reply.code(409).send({ error: "INVENTORY_SITE_CHANGED" });
      }

      const allowed = await cx.query(
        `select 1
           from config.CLIENT_SITE
          where CLIENT_ID=$1
            and SITE_ID=$2
            and ACTIVE=true`,
        [clientId, row.site_id],
      );

      if (!allowed.rowCount) {
        await cx.query("rollback");
        return reply.code(403).send({ error: "SITE_NOT_AUTHORISED" });
      }

      const current = Number(row.qty_on_hand);

      if (current !== expectedCurrent) {
        await cx.query("rollback");
        return reply.code(409).send({
          error: "INVENTORY_COUNT_STALE",
          expectedCurrentQuantity: expectedCurrent,
          actualCurrentQuantity: current,
        });
      }

      const delta = newQuantity - current;

      if (delta !== 0) {
        await cx.query(
          `select api.ADJUST_INVENTORY(
             $1,
             $2,
             $3,
             $4,
             $5,
             $6
           )`,
          [
            clientId,
            row.key,
            delta,
            body.reasonCode,
            body.note ?? null,
            principal.email,
          ],
        );
      }

      await cx.query("commit");

      return {
        inventoryKey: row.key,
        clientId,
        siteId: row.site_id,
        skuId: row.sku_id,
        locationId: row.location_id,
        previousQuantity: current,
        newQuantity,
        change: delta,
        changed: delta !== 0,
      };
    } catch (error) {
      try { await cx.query("rollback"); } catch {}
      throw error;
    } finally {
      cx.release();
    }
  });

app.post("/api/admin/inventory/:inventoryKey/move",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"inventory.move");const {inventoryKey}=req.params as any;const b=(req.body??{}) as any;
      if(!b.toLocationId)throw new Error("LOCATION_REQUIRED");if(!b.reasonCode)throw new Error("REASON_CODE_REQUIRED");
      const r=await db.query(`select * from core.MOVE_INVENTORY($1,$2::bigint,$3,$4,$5,$6,$7)`,
       [clientId,inventoryKey,b.toLocationId,b.reasonCode,b.notes??null,actor(p),b.stationId??"ADMIN"]);
      return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/picks",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"pick.read");const q=req.query as any;
      const r=await db.query(`select * from core.PICK_WORK_QUEUE where CLIENT_ID=$1
       and ($2::text is null or STATUS=$2) and ($3::text is null or ORDER_ID=$3)
       order by PRIORITY desc nulls last,SHIP_BY_DATE nulls last,CREATED_DSTAMP limit $4`,
       [clientId,q.status?.toUpperCase()??null,q.orderId??null,lim(q.limit,100,500)]);
      return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/picks/:pickTaskId/confirm",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"pick.confirm");const {pickTaskId}=req.params as any;const b=(req.body??{}) as any;
      const r=await db.query(`select * from core.CONFIRM_PICK($1::bigint,$2,$3,$4,$5,$6)`,
       [pickTaskId,Number(b.qtyPicked??0),actor(p),b.stationId??"ADMIN",b.shortClose===true,b.shortReason??null]);
      return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/shipments",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"shipment.read");const q=req.query as any;
      const r=await db.query(`select * from core.SHIPMENT_WORK_QUEUE where CLIENT_ID=$1 and ($2::text is null or ORDER_ID=$2)
       order by CREATED_DSTAMP nulls last limit $3`,[clientId,q.orderId??null,lim(q.limit,100,500)]);
      return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/containers/:containerId/ship",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"shipment.ship");const {containerId}=req.params as any;const b=(req.body??{}) as any;
      const r=await db.query(`select * from core.SHIP_CONTAINER($1,$2,$3,$4)`,[clientId,containerId,actor(p),b.stationId??"ADMIN"]);
      return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/payments",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"payment.read");const q=req.query as any;const x=String(q.q??"").trim()||null;
      const r=await db.query(`select * from core.ADMIN_PAYMENT_WORKBENCH where CLIENT_ID=$1
       and ($2::text is null or PAYMENT_ID::text ilike '%'||$2||'%' or REFERENCE_ID ilike '%'||$2||'%' or coalesce(PROVIDER_REFERENCE,'') ilike '%'||$2||'%')
       and ($3::text is null or STATUS=$3) order by CREATED_DSTAMP desc limit $4 offset $5`,
       [clientId,x,q.status?.toUpperCase()??null,lim(q.limit),off(q.offset)]);
      return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/payments/:paymentId/refund",async(req,reply)=>{
    const c=await db.connect();
    try{
      const p=await requirePermission(req,clientId,"payment.refund");const {paymentId}=req.params as any;const b=(req.body??{}) as any;
      if(!b.reasonCode)throw new Error("REASON_CODE_REQUIRED");
      await c.query("begin");
      const pr=await c.query(`select * from core.PAYMENT_TRANSACTION where CLIENT_ID=$1 and PAYMENT_ID=$2::uuid for update`,[clientId,paymentId]);
      if(!pr.rowCount)throw new Error("PAYMENT_NOT_FOUND");const x=pr.rows[0];
      if(x.provider!=="STRIPE"||!x.provider_reference)throw new Error("STRIPE_PAYMENT_REQUIRED");
      const refundable=Number(x.captured_amount??x.amount)-Number(x.refunded_amount??0);
      const amount=b.amount==null?refundable:Number(b.amount);
      if(!Number.isFinite(amount)||amount<=0||amount>refundable)throw new Error("INVALID_REFUND_AMOUNT");
      const suppliedIdempotency=String(b.operationId??req.headers["idempotency-key"]??"").trim();
       const idem=suppliedIdempotency||`admin-refund:${clientId}:${paymentId}:${crypto.randomUUID()}`;
      const ins=await c.query(`insert into core.PAYMENT_REFUND
       (CLIENT_ID,PAYMENT_ID,ORDER_ID,RETURN_CASE_ID,PROVIDER,PROVIDER_REFERENCE,IDEMPOTENCY_KEY,AMOUNT,CURRENCY,STATUS,REASON_CODE,NOTES,REQUESTED_BY)
       values($1,$2::uuid,$3,$4::uuid,$5,$6,$7,$8,$9,'REQUESTED',$10,$11,$12) returning *`,
       [clientId,paymentId,x.reference_id,b.returnCaseId??null,x.provider,x.provider_reference,idem,amount,x.currency,b.reasonCode,b.notes??null,actor(p)]);
      await c.query("commit");
      try{
        const provider=await createStripeRefund(x.provider_reference,amount);
        await db.query(`update core.PAYMENT_REFUND set STATUS='SUBMITTED',PROVIDER_REFUND_ID=coalesce($3,PROVIDER_REFUND_ID)
          where CLIENT_ID=$1 and PAYMENT_REFUND_ID=$2::uuid`,[clientId,ins.rows[0].payment_refund_id,(provider as any)?.id??null]);
        await attempt(clientId,p,"PAYMENT_REFUND","PAYMENT",paymentId,"payment.refund","SUBMITTED",b.notes??b.reasonCode,{amount,refundId:ins.rows[0].payment_refund_id});
        return reply.code(202).send({refund:ins.rows[0],provider});
      }catch(pe){
        await db.query(`update core.PAYMENT_REFUND set STATUS='FAILED',FAILURE_TEXT=$3 where CLIENT_ID=$1 and PAYMENT_REFUND_ID=$2::uuid`,
          [clientId,ins.rows[0].payment_refund_id,String((pe as Error)?.message??pe).slice(0,2000)]);
        throw pe;
      }
    }catch(e){try{await c.query("rollback");}catch{}return sendError(reply,e);}finally{c.release();}
  });

  app.get("/api/admin/returns",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"return.read");const q=req.query as any;
      const r=await db.query(`select * from core.RETURN_CASE where CLIENT_ID=$1
       and ($2::text is null or STATUS=$2) and ($3::text is null or ORDER_ID=$3)
       order by CREATED_DSTAMP desc limit $4`,[clientId,q.status?.toUpperCase()??null,q.orderId??null,lim(q.limit)]);
      return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/returns/:id",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"return.read");
      const {id}=req.params as any;

      const [header,lines]=await Promise.all([
        db.query(`select *
          from core.RETURN_CASE
          where CLIENT_ID=$1
            and RETURN_CASE_ID=$2
          limit 1`,[clientId,id]),
        db.query(`select *
          from core.RETURN_CASE_LINE
          where CLIENT_ID=$1
            and RETURN_CASE_ID=$2
          order by LINE_ID,CREATED_DSTAMP`,[clientId,id])
      ]);

      if(!header.rowCount){
        return reply.code(404).send({error:"RETURN_CASE_NOT_FOUND"});
      }

      return {case:header.rows[0],lines:lines.rows};
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/returns",async(req,reply)=>{
    const c=await db.connect();
    let transactionOpen=false;

    try{
      const p=await requirePermission(req,clientId,"return.create");
      const b=(req.body??{}) as any;

      const operationId=String(
        b.operationId ?? req.headers["idempotency-key"] ?? ""
      ).trim();

      if(!operationId){
        return reply.code(400).send({
          error:"RETURN_OPERATION_ID_REQUIRED",
          message:"A stable operationId or Idempotency-Key is required."
        });
      }

      const orderId=String(b.orderId??"").trim();

      if(!orderId){
        return reply.code(400).send({error:"RETURN_ORDER_REQUIRED"});
      }

      if(!b.caseType)throw new Error("CASE_TYPE_REQUIRED");

      const rawLines=Array.isArray(b.lines)?b.lines:[];

      if(rawLines.length>100){
        throw new Error("INVALID_RETURN_LINES");
      }

      const requestedLines=rawLines.map((x:any)=>({
        lineId:Number(x?.lineId),
        qty:Number(x?.qty),
        issueType:String(x?.issueType??b.caseType??"").trim().toUpperCase(),
        conditionCode:x?.conditionCode?String(x.conditionCode).trim().toUpperCase():null,
        resolution:x?.resolution?String(x.resolution).trim().slice(0,40):null,
        refundAmount:Number(x?.refundAmount??0),
        notes:x?.notes?String(x.notes).trim():null
      }));

      for(const line of requestedLines){
        if(!Number.isFinite(line.lineId)||line.lineId<=0){
          throw new Error("INVALID_RETURN_LINE");
        }
        if(!Number.isFinite(line.qty)||line.qty<=0){
          throw new Error("INVALID_RETURN_QTY");
        }
        if(!line.issueType){
          throw new Error("RETURN_ISSUE_TYPE_REQUIRED");
        }
        if(!Number.isFinite(line.refundAmount)||line.refundAmount<0){
          throw new Error("INVALID_RETURN_REFUND_AMOUNT");
        }
      }

      const lineIds=requestedLines.map((x:any)=>x.lineId);

      if(new Set(lineIds.map(String)).size!==lineIds.length){
        throw new Error("INVALID_RETURN_DUPLICATE_LINE");
      }

      await c.query("begin");
      transactionOpen=true;

      const existing=await c.query(`select *
        from core.RETURN_CASE
        where CLIENT_ID=$1
          and OPERATION_ID=$2
        for update`,[clientId,operationId]);

      if(existing.rowCount){
        const prior=existing.rows[0];

        if(String(prior.order_id)!==orderId){
          throw new Error("RETURN_OPERATION_CONFLICT");
        }

        const priorLines=await c.query(`select *
          from core.RETURN_CASE_LINE
          where CLIENT_ID=$1
            and RETURN_CASE_ID=$2
          order by LINE_ID,CREATED_DSTAMP`,
          [clientId,prior.return_case_id]);

        await c.query("commit");
        transactionOpen=false;

        return reply.code(200).send({
          ...prior,
          lines:priorLines.rows,
          replayed:true
        });
      }

      const order=await c.query(`select ACCOUNT_ID,CUSTOMER_ID
        from core.ORDER_HEADER
        where CLIENT_ID=$1
          and ORDER_ID=$2
        for update`,[clientId,orderId]);

      if(!order.rowCount){
        throw new Error("RETURN_ORDER_NOT_FOUND");
      }

      const orderLines=new Map<string,any>();

      if(lineIds.length){
        const lockedLines=await c.query(`select LINE_ID,SKU_ID,QTY_ORDERED
          from core.ORDER_LINE
          where CLIENT_ID=$1
            and ORDER_ID=$2
            and LINE_ID=any($3::numeric[])
          for update`,[clientId,orderId,lineIds]);

        if(lockedLines.rowCount!==lineIds.length){
          throw new Error("RETURN_ORDER_LINE_NOT_FOUND");
        }

        for(const row of lockedLines.rows){
          orderLines.set(String(row.line_id),row);
        }

        const claimed=await c.query(`select
            rcl.LINE_ID,
            coalesce(sum(rcl.QTY),0)::numeric as QTY_CLAIMED
          from core.RETURN_CASE_LINE rcl
          join core.RETURN_CASE rc
            on rc.CLIENT_ID=rcl.CLIENT_ID
           and rc.RETURN_CASE_ID=rcl.RETURN_CASE_ID
          where rcl.CLIENT_ID=$1
            and rcl.ORDER_ID=$2
            and rcl.LINE_ID=any($3::numeric[])
            and rc.STATUS<>'REJECTED'
          group by rcl.LINE_ID`,
          [clientId,orderId,lineIds]);

        const claimedByLine=new Map<string,number>();

        for(const row of claimed.rows){
          claimedByLine.set(String(row.line_id),Number(row.qty_claimed??0));
        }

        for(const line of requestedLines){
          const source=orderLines.get(String(line.lineId));
          const ordered=Number(source?.qty_ordered??0);
          const already=claimedByLine.get(String(line.lineId))??0;

          if(line.qty+already>ordered){
            throw new Error("INVALID_RETURN_QTY_EXCEEDS_ORDERED");
          }
        }
      }

      const caseNumber=`RC-${Date.now().toString(36).toUpperCase()}-${crypto.randomBytes(2).toString("hex").toUpperCase()}`;

      const created=await c.query(`insert into core.RETURN_CASE
        (CLIENT_ID,CASE_NUMBER,ORDER_ID,ACCOUNT_ID,CUSTOMER_ID,CASE_TYPE,
         REASON_CODE,CUSTOMER_MESSAGE,INTERNAL_NOTES,REFUND_REQUESTED,
         CREATED_BY,OPERATION_ID)
        values($1,$2,$3,$4::uuid,$5,$6,$7,$8,$9,$10,$11,$12)
        on conflict (CLIENT_ID,OPERATION_ID)
        where OPERATION_ID is not null
        do nothing
        returning *`,[
          clientId,
          caseNumber,
          orderId,
          order.rows[0].account_id,
          order.rows[0].customer_id,
          String(b.caseType).toUpperCase(),
          b.reasonCode??null,
          b.customerMessage??null,
          b.internalNotes??null,
          Number(b.refundRequested??0),
          actor(p),
          operationId
        ]);

      if(!created.rowCount){
        const raced=await c.query(`select *
          from core.RETURN_CASE
          where CLIENT_ID=$1
            and OPERATION_ID=$2
          limit 1`,[clientId,operationId]);

        if(!raced.rowCount){
          throw new Error("RETURN_IDEMPOTENCY_RACE");
        }

        const prior=raced.rows[0];

        if(String(prior.order_id)!==orderId){
          throw new Error("RETURN_OPERATION_CONFLICT");
        }

        const priorLines=await c.query(`select *
          from core.RETURN_CASE_LINE
          where CLIENT_ID=$1
            and RETURN_CASE_ID=$2
          order by LINE_ID,CREATED_DSTAMP`,
          [clientId,prior.return_case_id]);

        await c.query("commit");
        transactionOpen=false;

        return reply.code(200).send({
          ...prior,
          lines:priorLines.rows,
          replayed:true
        });
      }

      const result=created.rows[0];
      const insertedLines:any[]=[];

      for(const line of requestedLines){
        const source=orderLines.get(String(line.lineId));

        const inserted=await c.query(`insert into core.RETURN_CASE_LINE
          (RETURN_CASE_ID,CLIENT_ID,ORDER_ID,LINE_ID,SKU_ID,QTY,ISSUE_TYPE,
           CONDITION_CODE,RESOLUTION,REFUND_AMOUNT,NOTES)
          values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
          returning *`,[
            result.return_case_id,
            clientId,
            orderId,
            line.lineId,
            source?.sku_id??null,
            line.qty,
            line.issueType,
            line.conditionCode,
            line.resolution,
            line.refundAmount,
            line.notes
          ]);

        insertedLines.push(inserted.rows[0]);
      }

      await c.query("commit");
      transactionOpen=false;

      await auditAdminChange(
        clientId,
        p,
        "RETURN_CASE",
        result.return_case_id,
        "CREATE",
        null,
        {...result,lines:insertedLines}
      );

      return reply.code(201).send({
        ...result,
        lines:insertedLines,
        replayed:false
      });

    }catch(e){
      if(transactionOpen){
        try{await c.query("rollback")}catch{}
      }
      return sendError(reply,e);
    }finally{
      c.release();
    }
  });
  app.patch("/api/admin/returns/:id",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"return.manage");const {id}=req.params as any;const b=(req.body??{}) as any;
      const before=await db.query(`select * from core.RETURN_CASE where CLIENT_ID=$1 and RETURN_CASE_ID=$2::uuid`,[clientId,id]);
      if(!before.rowCount)throw new Error("RETURN_CASE_NOT_FOUND");
      const r=await db.query(`update core.RETURN_CASE set
       STATUS=coalesce($3,STATUS),RESOLUTION=coalesce($4,RESOLUTION),ASSIGNED_TO=coalesce($5,ASSIGNED_TO),
       INTERNAL_NOTES=coalesce($6,INTERNAL_NOTES),REFUND_APPROVED=coalesce($7,REFUND_APPROVED),
       REPLACEMENT_ORDER_ID=coalesce($8,REPLACEMENT_ORDER_ID),LAST_UPDATE_DSTAMP=now(),
       CLOSED_DSTAMP=case when coalesce($3,STATUS) in('RESOLVED','CLOSED','REJECTED') then coalesce(CLOSED_DSTAMP,now()) else CLOSED_DSTAMP end
       where CLIENT_ID=$1 and RETURN_CASE_ID=$2::uuid returning *`,
       [clientId,id,b.status?.toUpperCase()??null,b.resolution??null,b.assignedTo??null,b.internalNotes??null,b.refundApproved==null?null:Number(b.refundApproved),b.replacementOrderId??null]);
      await auditAdminChange(clientId,p,"RETURN_CASE",id,"UPDATE",before.rows[0],r.rows[0]);return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/notifications",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"notification.read");const q=req.query as any;
      const r=await db.query(`select * from interface.NOTIFICATION_OUTBOX where CLIENT_ID=$1 and ($2::text is null or STATUS=$2)
       order by CREATED_DSTAMP desc limit $3`,[clientId,q.status?.toUpperCase()??null,lim(q.limit,100,500)]);return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/notifications/:id/retry",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"notification.retry");const {id}=req.params as any;
      const r=await db.query(`select * from core.RETRY_NOTIFICATION($1,$2::uuid,$3)`,[clientId,id,actor(p)]);return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/interfaces/orders",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"interface.read");const q=req.query as any;
      const r=await db.query(`select * from interface.ORDER_HEADER_IF where CLIENT_ID=$1 and ($2::text is null or PROCESS_STATUS=$2)
       order by CREATED_DSTAMP desc limit $3`,[clientId,q.status?.toUpperCase()??null,lim(q.limit,100,500)]);return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/interfaces/orders/:id/retry",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"interface.retry");const {id}=req.params as any;
      const r=await db.query(`select * from core.RETRY_ORDER_INTERFACE($1,$2::uuid,$3)`,[clientId,id,actor(p)]);return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/suppliers",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"supplier.read");const r=await db.query(`select * from core.SUPPLIER where CLIENT_ID=$1 order by NAME`,[clientId]);return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/suppliers",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"supplier.manage");const b=(req.body??{}) as any;
      if(!b.supplierId||!b.name)throw new Error("SUPPLIER_REQUIRED");
      const r=await db.query(`insert into core.SUPPLIER(SUPPLIER_ID,CLIENT_ID,NAME,ADDRESS_ID,CONTACT,CONTACT_EMAIL,CONTACT_PHONE,ACTIVE,NOTES)
       values($1,$2,$3,$4,$5,$6,$7,$8,$9) returning *`,
       [String(b.supplierId).toUpperCase(),clientId,b.name,b.addressId??null,b.contact??null,b.contactEmail??null,b.contactPhone??null,b.active!==false,b.notes??null]);
      await auditAdminChange(clientId,p,"SUPPLIER",r.rows[0].supplier_id,"CREATE",null,r.rows[0]);return reply.code(201).send(r.rows[0]);
    }catch(e){return sendError(reply,e);}
  });

  app.patch("/api/admin/suppliers/:supplierId",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"supplier.manage");const {supplierId}=req.params as any;const b=(req.body??{}) as any;
      const before=await db.query(`select * from core.SUPPLIER where CLIENT_ID=$1 and SUPPLIER_ID=$2`,[clientId,supplierId]);if(!before.rowCount)throw new Error("SUPPLIER_NOT_FOUND");
      const r=await db.query(`update core.SUPPLIER set NAME=coalesce($3,NAME),ADDRESS_ID=coalesce($4,ADDRESS_ID),CONTACT=coalesce($5,CONTACT),
       CONTACT_EMAIL=coalesce($6,CONTACT_EMAIL),CONTACT_PHONE=coalesce($7,CONTACT_PHONE),ACTIVE=coalesce($8,ACTIVE),NOTES=coalesce($9,NOTES),LAST_UPDATED_DSTAMP=now()
       where CLIENT_ID=$1 and SUPPLIER_ID=$2 returning *`,
       [clientId,supplierId,b.name??null,b.addressId??null,b.contact??null,b.contactEmail??null,b.contactPhone??null,b.active??null,b.notes??null]);
      await auditAdminChange(clientId,p,"SUPPLIER",supplierId,"UPDATE",before.rows[0],r.rows[0]);return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/pre-advice",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"pre_advice.read");const q=req.query as any;
      const r=await db.query(`select h.*,coalesce(jsonb_agg(to_jsonb(l) order by l.LINE_ID) filter(where l.LINE_ID is not null),'[]'::jsonb) lines
       from core.PRE_ADVICE_HEADER h left join core.PRE_ADVICE_LINE l on l.CLIENT_ID=h.CLIENT_ID and l.PRE_ADVICE_ID=h.PRE_ADVICE_ID
       where h.CLIENT_ID=$1 and ($2::text is null or h.STATUS=$2) group by h.CLIENT_ID,h.PRE_ADVICE_ID order by h.DUE_DSTAMP nulls last limit $3`,
       [clientId,q.status?.toUpperCase()??null,lim(q.limit,100,500)]);return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/promotions",async(req,reply)=>{
    try{await requirePermission(req,clientId,"config.read");const r=await db.query(`select * from config.PROMOTION where CLIENT_ID=$1 order by CREATED_DSTAMP desc`,[clientId]);return r.rows;}
    catch(e){return sendError(reply,e);}
  });

  app.patch("/api/admin/promotions/:promotionId",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"promotion.manage");const {promotionId}=req.params as any;const b=(req.body??{}) as any;
      const before=await db.query(`select * from config.PROMOTION where CLIENT_ID=$1 and PROMOTION_ID=$2`,[clientId,promotionId]);if(!before.rowCount)throw new Error("PROMOTION_NOT_FOUND");
      const r=await db.query(`update config.PROMOTION set DESCRIPTION=coalesce($3,DESCRIPTION),PROMOTION_VALUE=coalesce($4,PROMOTION_VALUE),
       MIN_ORDER_VALUE=coalesce($5,MIN_ORDER_VALUE),STARTS_DSTAMP=coalesce($6,STARTS_DSTAMP),ENDS_DSTAMP=coalesce($7,ENDS_DSTAMP),
       ACTIVE=coalesce($8,ACTIVE),LAST_UPDATE_DSTAMP=now() where CLIENT_ID=$1 and PROMOTION_ID=$2 returning *`,
       [clientId,promotionId,b.description??null,b.promotionValue??null,b.minOrderValue??null,b.startsDstamp??null,b.endsDstamp??null,b.active??null]);
      await auditAdminChange(clientId,p,"PROMOTION",promotionId,"UPDATE",before.rows[0],r.rows[0]);return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/gift-cards",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"giftcard.read");const q=req.query as any;const x=String(q.q??"").trim()||null;
      const r=await db.query(`select g.*,coalesce((select jsonb_agg(to_jsonb(t) order by t.CREATED_DSTAMP desc) from core.GIFT_CARD_TRANSACTION t where t.CLIENT_ID=g.CLIENT_ID and t.GIFT_CARD_ID=g.GIFT_CARD_ID),'[]'::jsonb) transactions
       from core.GIFT_CARD g where g.CLIENT_ID=$1 and ($2::text is null or g.GIFT_CODE ilike '%'||$2||'%') order by g.CREATED_DSTAMP desc limit $3`,
       [clientId,x,lim(q.limit)]);return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.post("/api/admin/gift-cards/:giftCode/adjust",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"giftcard.manage");const {giftCode}=req.params as any;const b=(req.body??{}) as any;
      if(!b.reasonCode)throw new Error("REASON_CODE_REQUIRED");const amount=Number(b.amount);if(!Number.isFinite(amount)||amount===0)throw new Error("INVALID_GIFT_CARD_AMOUNT");
      const r=await db.query(`select * from core.ADJUST_GIFT_CARD($1,$2,$3,$4,$5,$6,$7,$8)`,
       [clientId,giftCode,amount,b.reasonCode,b.notes??null,b.referenceType??"ADMIN",b.referenceId??null,actor(p)]);return r.rows[0];
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/carriers",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"carrier.read");
      const [c,s,r,z,d]=await Promise.all([
        db.query(`select * from config.CARRIER where CLIENT_ID=$1 order by CARRIER_ID`,[clientId]),
        db.query(`select * from config.CARRIER_SERVICE where CLIENT_ID=$1 order by CARRIER_ID,SORT_SEQUENCE,SERVICE_LEVEL`,[clientId]),
        db.query(`select * from config.CARRIER_SERVICE_RATE where CLIENT_ID=$1 order by CARRIER_ID,SERVICE_LEVEL,PRIORITY`,[clientId]),
        db.query(`select * from config.DELIVERY_ZONE where CLIENT_ID=$1 order by PRIORITY,ZONE_ID`,[clientId]),
        db.query(`select * from config.DELIVERY_CLASS_CONTROL where CLIENT_ID=$1 order by DELIVERY_CLASS`,[clientId])
      ]);return {carriers:c.rows,services:s.rows,rates:r.rows,deliveryZones:z.rows,deliveryClassControls:d.rows};
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/config/reason-codes",async(req,reply)=>{
    try{await requirePermission(req,clientId,"config.read");const q=req.query as any;const r=await db.query(`select * from config.ADMIN_REASON_CODE where CLIENT_ID=$1 and ($2::text is null or REASON_DOMAIN=$2) order by REASON_DOMAIN,SORT_SEQUENCE`,[clientId,q.domain?.toUpperCase()??null]);return r.rows;}
    catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/audit/meta",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"audit.read");
      const [types,actions]=await Promise.all([
        db.query(`select distinct ENTITY_TYPE from audit.AUDIT_EVENT where (CLIENT_ID=$1 or CLIENT_ID is null) and ENTITY_TYPE is not null order by ENTITY_TYPE`,[clientId]),
        db.query(`select distinct ACTION from audit.AUDIT_EVENT where (CLIENT_ID=$1 or CLIENT_ID is null) and ACTION is not null order by ACTION`,[clientId])
      ]);
      return {
        entityTypes:types.rows.map((r:any)=>r.entity_type),
        actions:actions.rows.map((r:any)=>r.action)
      };
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/audit",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"audit.read");
      const q=req.query as any;
      const entityType=q.entityType?String(q.entityType).toUpperCase():null;
      const entityId=q.entityId?String(q.entityId).trim():null;
      const action=q.action?String(q.action).toUpperCase():null;
      const changedBy=q.changedBy?String(q.changedBy).trim():null;
      const dateFrom=q.dateFrom?String(q.dateFrom):null;
      const dateTo=q.dateTo?String(q.dateTo):null;
      const limit=Math.min(lim(q.limit,100,250),250);
      const offset=off(q.offset);
      const r=await db.query(`select * from audit.AUDIT_EVENT
       where (CLIENT_ID=$1 or CLIENT_ID is null)
         and ($2::text is null or ENTITY_TYPE=$2)
         and ($3::text is null or ENTITY_ID ilike '%' || $3 || '%')
         and ($4::text is null or ACTION=$4)
         and ($5::text is null or CHANGED_BY ilike '%' || $5 || '%')
         and ($6::date is null or CREATED_DSTAMP >= $6::date)
         and ($7::date is null or CREATED_DSTAMP < ($7::date + interval '1 day'))
       order by CREATED_DSTAMP desc
       limit $8 offset $9`,
       [clientId,entityType,entityId,action,changedBy,dateFrom,dateTo,limit,offset]);
      return r.rows;
    }catch(e){return sendError(reply,e);}
  });

  app.get("/api/admin/system/health",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"system.read");
      const [v,t,c]=await Promise.all([
        db.query(`select api.GET_SYSTEM_VERSION() data`),
        db.query(`select now() database_time`),
        db.query(`select
          (select count(*)::int from core.ADMIN_EXCEPTION_WORKBENCH where CLIENT_ID=$1) exceptions,
          (select count(*)::int from interface.NOTIFICATION_OUTBOX where CLIENT_ID=$1 and STATUS in('FAILED','ERROR')) failed_notifications,
          (select count(*)::int from audit.PROCESSING_LOG where CLIENT_ID=$1 and STATUS in('ERROR','FAILED') and CREATED_DSTAMP>now()-interval '24 hours') processing_errors_24h`,[clientId])
      ]);
      return {ok:true,version:v.rows[0]?.data,databaseTime:t.rows[0]?.database_time,operational:c.rows[0]};
    }catch(e){return sendError(reply,e);}
  });
}
