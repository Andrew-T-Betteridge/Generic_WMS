import type { FastifyInstance, FastifyReply } from "fastify";
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

function limitOf(raw: unknown, fallback=50, max=250) {
  const n=Number(raw ?? fallback);
  return Math.max(
    1,
    Math.min(max,Number.isFinite(n) ? Math.floor(n) : fallback),
  );
}

export function registerAdminMonitoringRoutes(
  app: FastifyInstance,
  clientId: string,
) {
  app.get("/api/admin/monitoring/summary",async(req,reply)=>{
    try{
      const principal=await requirePermission(
        req,clientId,"dashboard.read",
      );

      const adminId=principal.adminUserId;

      const summary=await db.query(
        `select
           (
             select count(*)::int
               from audit.ADMIN_NOTIFICATION_EVENT e
               left join config.ADMIN_NOTIFICATION_READ r
                 on r.CLIENT_ID=e.CLIENT_ID
                and r.EVENT_ID=e.EVENT_ID
                and r.ADMIN_USER_ID=$2::uuid
              where e.CLIENT_ID=$1
                and e.EVENT_TYPE='PAYMENT_CONFIRMED'
                and r.EVENT_ID is null
           ) as new_paid_orders,

           (
             select count(*)::int
               from core.ORDER_HEADER oh
              where oh.CLIENT_ID=$1
                and oh.PAYMENT_STATUS='PAID'
                and UPPER(COALESCE(oh.STATUS,''))<>'CANCELLED'
                and UPPER(COALESCE(oh.FULFILMENT_STATUS,'')) not in
                    ('CANCELLED','SHIPPED','DELIVERED')
           ) as orders_requiring_action,

           (
             select count(*)::int
               from core.ORDER_HEADER
              where CLIENT_ID=$1
                and PAYMENT_STATUS='PENDING'
           ) as pending_payment,

           (
             select count(*)::int
               from core.ORDER_HEADER
              where CLIENT_ID=$1
                and UPPER(COALESCE(FULFILMENT_STATUS,'')) in
                    ('READY_TO_PACK','PACKED','READY_TO_DISPATCH')
           ) as ready_to_dispatch,

           (
             select count(*)::int
               from core.ORDER_HEADER
              where CLIENT_ID=$1
                and ORDER_DATE>=CURRENT_DATE
           ) as orders_today,

           (
             select COALESCE(sum(ORDER_VALUE),0)
               from core.ORDER_HEADER
              where CLIENT_ID=$1
                and PAYMENT_STATUS='PAID'
                and ORDER_DATE>=CURRENT_DATE
           ) as paid_sales_today,

           (
             select count(*)::int
               from core.ORDER_HEADER oh
              where oh.CLIENT_ID=$1
                and (
                    oh.PAYMENT_STATUS='FAILED'
                    or (
                      oh.PAYMENT_STATUS='PAID'
                      and EXISTS (
                        select 1
                          from core.ORDER_LINE ol
                         where ol.CLIENT_ID=oh.CLIENT_ID
                           and ol.ORDER_ID=oh.ORDER_ID
                           and ol.BACK_ORDERED='Y'
                      )
                    )
                )
           ) as exception_count`,
        [clientId,adminId],
      );

      const recentPaid=await db.query(
        `select
           oh.ORDER_ID,
           oh.ORDER_DATE,
           oh.ORDER_VALUE,
           oh.INV_CURRENCY,
           oh.NAME,
           oh.CONTACT_EMAIL,
           oh.POSTCODE,
           oh.PAYMENT_STATUS,
           oh.FULFILMENT_STATUS
         from core.ORDER_HEADER oh
        where oh.CLIENT_ID=$1
          and oh.PAYMENT_STATUS='PAID'
        order by COALESCE(oh.PAYMENT_DSTAMP,oh.ORDER_DATE) desc
        limit 8`,
        [clientId],
      );

      const exceptions=await db.query(
        `select
           oh.ORDER_ID,
           oh.ORDER_DATE,
           oh.PAYMENT_STATUS,
           oh.FULFILMENT_STATUS,
           oh.CONTACT_EMAIL,
           case
             when oh.PAYMENT_STATUS='FAILED'
               then 'PAYMENT_FAILED'
             when EXISTS (
               select 1
                 from core.ORDER_LINE ol
                where ol.CLIENT_ID=oh.CLIENT_ID
                  and ol.ORDER_ID=oh.ORDER_ID
                  and ol.BACK_ORDERED='Y'
             )
               then 'BACK_ORDERED'
             else 'REQUIRES_REVIEW'
           end as EXCEPTION_TYPE
         from core.ORDER_HEADER oh
        where oh.CLIENT_ID=$1
          and (
              oh.PAYMENT_STATUS='FAILED'
              or (
                oh.PAYMENT_STATUS='PAID'
                and EXISTS (
                  select 1
                    from core.ORDER_LINE ol
                   where ol.CLIENT_ID=oh.CLIENT_ID
                     and ol.ORDER_ID=oh.ORDER_ID
                     and ol.BACK_ORDERED='Y'
                )
              )
          )
        order by oh.ORDER_DATE desc
        limit 12`,
        [clientId],
      );

      return {
        ...summary.rows[0],
        recentPaid:recentPaid.rows,
        exceptions:exceptions.rows,
      };
    }catch(e){
      return sendError(reply,e);
    }
  });

  app.get("/api/admin/monitoring/orders",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"order.read");

      const query=req.query as {
        q?:string;
        workflow?:string;
        limit?:string;
      };

      const search=String(query.q ?? "").trim() || null;
      const workflow=String(query.workflow ?? "ALL").toUpperCase();
      const limit=limitOf(query.limit,250,500);

      const result=await db.query(
        `with orders as (
          select
            oh.ORDER_ID,
            oh.ORDER_REFERENCE,
            oh.ORDER_DATE,
            oh.PAYMENT_DSTAMP,
            oh.STATUS,
            oh.PAYMENT_STATUS,
            oh.FULFILMENT_STATUS,
            oh.SHIPPED_DATE,
            oh.DELIVERED_DSTAMP,
            oh.DISPATCH_METHOD,
            oh.CARRIER_ID,
            oh.SERVICE_LEVEL,
            oh.ORDER_VALUE,
            oh.FREIGHT_COST,
            oh.INV_CURRENCY,
            oh.CUSTOMER_ID,
            oh.NAME,
            oh.CONTACT_EMAIL,
            oh.CONTACT_PHONE,
            oh.POSTCODE,
            oh.TOWN,
            case
              when UPPER(COALESCE(oh.STATUS,''))='CANCELLED'
                or UPPER(COALESCE(oh.FULFILMENT_STATUS,''))='CANCELLED'
                then 'CANCELLED'
              when oh.DELIVERED_DSTAMP is not null
                or UPPER(COALESCE(oh.FULFILMENT_STATUS,''))='DELIVERED'
                then 'DELIVERED'
              when oh.SHIPPED_DATE is not null
                or UPPER(COALESCE(oh.FULFILMENT_STATUS,''))='SHIPPED'
                then 'DISPATCHED'
              when UPPER(COALESCE(oh.FULFILMENT_STATUS,'')) in
                ('READY_TO_PACK','PACKED','READY_TO_DISPATCH')
                then 'READY'
              when UPPER(COALESCE(oh.FULFILMENT_STATUS,'')) in
                ('PICKING','PART_PICKED')
                then 'PICKING'
              when oh.PAYMENT_STATUS='PAID'
                then 'NEW_PAID'
              else 'PENDING_PAYMENT'
            end as WORKFLOW_BUCKET
          from core.ORDER_HEADER oh
          where oh.CLIENT_ID=$1
            and (
              $2::text is null
              or oh.ORDER_ID ilike '%'||$2||'%'
              or COALESCE(oh.ORDER_REFERENCE,'') ilike '%'||$2||'%'
              or COALESCE(oh.NAME,'') ilike '%'||$2||'%'
              or COALESCE(oh.CONTACT_EMAIL,'') ilike '%'||$2||'%'
              or COALESCE(oh.POSTCODE,'') ilike '%'||$2||'%'
            )
        )
        select *
          from orders
         where ($3='ALL' or WORKFLOW_BUCKET=$3)
         order by ORDER_DATE desc,ORDER_ID desc
         limit $4`,
        [clientId,search,workflow,limit],
      );

      return result.rows;
    }catch(e){
      return sendError(reply,e);
    }
  });

  app.get("/api/admin/notifications",async(req,reply)=>{
    try{
      const principal=await requirePermission(
        req,clientId,"order.read",
      );

      const query=req.query as {
        limit?:string;
        unreadOnly?:string;
      };

      const limit=limitOf(query.limit,40,100);
      const unreadOnly=["1","true","yes"].includes(
        String(query.unreadOnly ?? "").toLowerCase(),
      );

      const result=await db.query(
        `select
           e.EVENT_ID,
           e.ORDER_ID,
           e.EVENT_TYPE,
           e.SEVERITY,
           e.TITLE,
           e.MESSAGE,
           e.PAYLOAD,
           e.CREATED_DSTAMP,
           (r.EVENT_ID is not null) as IS_READ
         from audit.ADMIN_NOTIFICATION_EVENT e
         left join config.ADMIN_NOTIFICATION_READ r
           on r.CLIENT_ID=e.CLIENT_ID
          and r.EVENT_ID=e.EVENT_ID
          and r.ADMIN_USER_ID=$2::uuid
        where e.CLIENT_ID=$1
          and ($3::boolean=false or r.EVENT_ID is null)
        order by e.CREATED_DSTAMP desc
        limit $4`,
        [clientId,principal.adminUserId,unreadOnly,limit],
      );

      const unread=await db.query(
        `select count(*)::int as count
           from audit.ADMIN_NOTIFICATION_EVENT e
           left join config.ADMIN_NOTIFICATION_READ r
             on r.CLIENT_ID=e.CLIENT_ID
            and r.EVENT_ID=e.EVENT_ID
            and r.ADMIN_USER_ID=$2::uuid
          where e.CLIENT_ID=$1
            and r.EVENT_ID is null`,
        [clientId,principal.adminUserId],
      );

      return {
        unread:unread.rows[0]?.count ?? 0,
        items:result.rows,
      };
    }catch(e){
      return sendError(reply,e);
    }
  });

  app.post("/api/admin/notifications/:eventId/read",async(req,reply)=>{
    try{
      const principal=await requirePermission(
        req,clientId,"order.read",
      );

      if(!principal.adminUserId){
        throw new Error("ADMIN_USER_REQUIRED");
      }

      const {eventId}=req.params as {eventId:string};

      const exists=await db.query(
        `select 1
           from audit.ADMIN_NOTIFICATION_EVENT
          where CLIENT_ID=$1 and EVENT_ID=$2::uuid`,
        [clientId,eventId],
      );

      if(!exists.rowCount){
        throw new Error("NOTIFICATION_NOT_FOUND");
      }

      await db.query(
        `insert into config.ADMIN_NOTIFICATION_READ
           (CLIENT_ID,ADMIN_USER_ID,EVENT_ID,READ_DSTAMP,ACKNOWLEDGED)
         values($1,$2::uuid,$3::uuid,now(),true)
         on conflict (CLIENT_ID,ADMIN_USER_ID,EVENT_ID)
         do update set READ_DSTAMP=now(),ACKNOWLEDGED=true`,
        [clientId,principal.adminUserId,eventId],
      );

      return {ok:true,eventId};
    }catch(e){
      return sendError(reply,e);
    }
  });

  app.post("/api/admin/notifications/read-all",async(req,reply)=>{
    try{
      const principal=await requirePermission(
        req,clientId,"order.read",
      );

      if(!principal.adminUserId){
        throw new Error("ADMIN_USER_REQUIRED");
      }

      await db.query(
        `insert into config.ADMIN_NOTIFICATION_READ
           (CLIENT_ID,ADMIN_USER_ID,EVENT_ID,READ_DSTAMP,ACKNOWLEDGED)
         select
           e.CLIENT_ID,
           $2::uuid,
           e.EVENT_ID,
           now(),
           true
         from audit.ADMIN_NOTIFICATION_EVENT e
         where e.CLIENT_ID=$1
         on conflict (CLIENT_ID,ADMIN_USER_ID,EVENT_ID)
         do update set READ_DSTAMP=now(),ACKNOWLEDGED=true`,
        [clientId,principal.adminUserId],
      );

      return {ok:true};
    }catch(e){
      return sendError(reply,e);
    }
  });

  app.post("/api/admin/orders/:orderId/acknowledge",async(req,reply)=>{
    try{
      const principal=await requirePermission(
        req,clientId,"order.read",
      );

      if(!principal.adminUserId){
        throw new Error("ADMIN_USER_REQUIRED");
      }

      const {orderId}=req.params as {orderId:string};

      await db.query(
        `insert into config.ADMIN_NOTIFICATION_READ
           (CLIENT_ID,ADMIN_USER_ID,EVENT_ID,READ_DSTAMP,ACKNOWLEDGED)
         select
           e.CLIENT_ID,
           $2::uuid,
           e.EVENT_ID,
           now(),
           true
         from audit.ADMIN_NOTIFICATION_EVENT e
         where e.CLIENT_ID=$1
           and e.ORDER_ID=$3
         on conflict (CLIENT_ID,ADMIN_USER_ID,EVENT_ID)
         do update set READ_DSTAMP=now(),ACKNOWLEDGED=true`,
        [clientId,principal.adminUserId,orderId],
      );

      return {ok:true,orderId};
    }catch(e){
      return sendError(reply,e);
    }
  });

  app.get("/api/admin/orders/:orderId/timeline",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"order.read");

      const {orderId}=req.params as {orderId:string};

      const order=await db.query(
        `select
           ORDER_ID,
           ORDER_DATE,
           PAYMENT_DSTAMP,
           PAYMENT_STATUS,
           FULFILMENT_STATUS,
           SHIPPED_DATE,
           DELIVERED_DSTAMP
         from core.ORDER_HEADER
         where CLIENT_ID=$1 and ORDER_ID=$2`,
        [clientId,orderId],
      );

      if(!order.rowCount){
        throw new Error("ORDER_NOT_FOUND");
      }

      const events=await db.query(
        `select
           EVENT_ID,
           EVENT_TYPE,
           SEVERITY,
           TITLE,
           MESSAGE,
           PAYLOAD,
           CREATED_DSTAMP
         from audit.ADMIN_NOTIFICATION_EVENT
         where CLIENT_ID=$1
           and ORDER_ID=$2
         order by CREATED_DSTAMP asc`,
        [clientId,orderId],
      );

      const audit=await db.query(
        `select
           ACTION,
           CHANGED_BY,
           REASON,
           CREATED_DSTAMP
         from audit.AUDIT_EVENT
         where CLIENT_ID=$1
           and ENTITY_TYPE='ORDER'
           and ENTITY_ID=$2
         order by CREATED_DSTAMP asc`,
        [clientId,orderId],
      );

      return {
        order:order.rows[0],
        events:events.rows,
        audit:audit.rows,
      };
    }catch(e){
      return sendError(reply,e);
    }
  });

  app.get("/api/admin/monitoring/config",async(req,reply)=>{
    try{
      await requirePermission(req,clientId,"dashboard.read");

      return {
        browserNotifications:true,
        audioAlerts:true,
        emailConfigured:Boolean(
          process.env.RESEND_API_KEY &&
          process.env.ADMIN_ALERT_EMAIL &&
          process.env.ADMIN_ALERT_FROM
        ),
        emailRecipientConfigured:Boolean(
          process.env.ADMIN_ALERT_EMAIL
        ),
      };
    }catch(e){
      return sendError(reply,e);
    }
  });
}
