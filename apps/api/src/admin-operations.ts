import type { FastifyInstance, FastifyReply } from "fastify";
import crypto from "node:crypto";
import { db } from "./db.js";
import { auditAdminChange, requirePermission, resolveAdminPrincipal } from "./admin-rbac.js";
import { createStripeRefund } from "./stripe.js";

function codeOf(e: unknown) { return String((e as Error)?.message ?? e).split(":")[0]; }
function sendError(reply: FastifyReply,e: unknown) {
  const c=codeOf(e);
  const s=c.endsWith("_NOT_FOUND")?404:
          c.startsWith("INVALID_")||c.endsWith("_REQUIRED")?400:
          c.includes("PERMISSION")||c.includes("ADMIN_ACCESS")?403:
          c.includes("NOT_ALLOWED")||c.includes("NOT_RETRYABLE")?409:500;
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

  app.get("/api/admin/operations/dashboard",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"dashboard.read");
      const [s,e]=await Promise.all([
        db.query(`select
          (select count(*)::int from core.ORDER_HEADER where CLIENT_ID=$1 and ORDER_DATE>=CURRENT_DATE) orders_today,
          (select coalesce(sum(ORDER_VALUE),0) from core.ORDER_HEADER where CLIENT_ID=$1 and PAYMENT_STATUS='PAID' and ORDER_DATE>=CURRENT_DATE) revenue_today,
          (select count(*)::int from core.ADMIN_EXCEPTION_WORKBENCH where CLIENT_ID=$1) exception_count,
          (select count(*)::int from core.PICK_TASK where CLIENT_ID=$1 and STATUS in('OPEN','STARTED')) open_picks,
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
      const idem=`admin-refund:${clientId}:${paymentId}:${crypto.randomUUID()}`;
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

  app.post("/api/admin/returns",async(req,reply)=>{
    try{
      const p=await requirePermission(req,clientId,"return.create");const b=(req.body??{}) as any;
      if(!b.orderId)throw new Error("ORDER_ID_REQUIRED");if(!b.caseType)throw new Error("CASE_TYPE_REQUIRED");
      const o=await db.query(`select ACCOUNT_ID,CUSTOMER_ID from core.ORDER_HEADER where CLIENT_ID=$1 and ORDER_ID=$2`,[clientId,b.orderId]);
      if(!o.rowCount)throw new Error("ORDER_NOT_FOUND");
      const num=`RC-${Date.now().toString(36).toUpperCase()}-${crypto.randomBytes(2).toString("hex").toUpperCase()}`;
      const r=await db.query(`insert into core.RETURN_CASE
       (CLIENT_ID,CASE_NUMBER,ORDER_ID,ACCOUNT_ID,CUSTOMER_ID,CASE_TYPE,REASON_CODE,CUSTOMER_MESSAGE,INTERNAL_NOTES,REFUND_REQUESTED,CREATED_BY)
       values($1,$2,$3,$4::uuid,$5,$6,$7,$8,$9,$10,$11) returning *`,
       [clientId,num,b.orderId,o.rows[0].account_id,o.rows[0].customer_id,String(b.caseType).toUpperCase(),b.reasonCode??null,b.customerMessage??null,b.internalNotes??null,Number(b.refundRequested??0),actor(p)]);
      await auditAdminChange(clientId,p,"RETURN_CASE",r.rows[0].return_case_id,"CREATE",null,r.rows[0]);
      return reply.code(201).send(r.rows[0]);
    }catch(e){return sendError(reply,e);}
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

  app.get("/api/admin/audit",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"audit.read");const q=req.query as any;
      const r=await db.query(`select * from audit.AUDIT_EVENT where (CLIENT_ID=$1 or CLIENT_ID is null)
       and ($2::text is null or ENTITY_TYPE=$2) and ($3::text is null or ENTITY_ID=$3)
       order by CREATED_DSTAMP desc limit $4`,[clientId,q.entityType?.toUpperCase()??null,q.entityId??null,lim(q.limit,100,500)]);return r.rows;
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
