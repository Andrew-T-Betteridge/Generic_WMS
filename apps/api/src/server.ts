import Fastify from "fastify";
import cors from "@fastify/cors";
import crypto from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import "dotenv/config";
import { db } from "./db.js";
import { optionalIdentity, requireIdentity } from "./auth.js";
import { auditAdminChange, registerAdminAccessRoutes, requirePermission } from "./admin-rbac.js";
import { registerAdminManagementRoutes } from "./admin-management.js";
import { createStripePaymentIntent, createStripeRefund, normaliseStripeEvent, verifyStripeSignature } from "./stripe.js";
import { AddressLookupError, resolveUkAddress, searchUkAddresses } from "./address.js";

const app = Fastify({ logger: true });
const clientId = process.env.DEFAULT_CLIENT_ID ?? "FINATICS";
const allowedOrigins = [
  ...(process.env.STORE_FRONT_ORIGIN ?? "http://localhost:5173").split(","),
  ...(process.env.ADMIN_ORIGIN ?? "").split(","),
]
  .map((x) => x.trim())
  .filter(Boolean);

await app.register(cors,{
  origin: allowedOrigins,
  credentials: true
});

declare module "fastify" {
  interface FastifyRequest { rawJsonBody?: Buffer }
}

app.addContentTypeParser("application/json",{parseAs:"buffer"},(req,body,done)=>{
  try {
    req.rawJsonBody = body as Buffer;
    done(null,JSON.parse((body as Buffer).toString("utf8")));
  } catch (e) { done(e as Error,undefined); }
});

const q = async (sql:string,params:unknown[]=[]) => (await db.query(sql,params)).rows[0]?.data;

function errorCode(e: unknown) {
  return String((e as Error)?.message ?? e).split(":")[0];
}

async function auditSecurity(req:any,result:string,detail?:string,resourceType?:string,resourceId?:string) {
  try {
    await db.query(
      `insert into audit.API_SECURITY_EVENT
       (CLIENT_ID,EVENT_TYPE,ROUTE,RESOURCE_TYPE,RESOURCE_ID,RESULT,DETAIL)
       values($1,'HTTP_ACCESS',$2,$3,$4,$5,$6)`,
      [clientId,req.routeOptions?.url ?? req.url,resourceType??null,resourceId??null,result,detail??null]
    );
  } catch {}
}

function orderTokenSecret() {
  const s=process.env.ORDER_ACCESS_TOKEN_SECRET;
  if(!s) throw new Error("ORDER_ACCESS_TOKEN_SECRET_REQUIRED");
  return new TextEncoder().encode(s);
}

async function signGuestAccess(scope:string,resourceId:string,email:string) {
  return new SignJWT({resourceId,email:email.toLowerCase(),scope})
    .setProtectedHeader({alg:"HS256"})
    .setIssuedAt()
    .setExpirationTime(process.env.ORDER_ACCESS_TOKEN_TTL ?? "30d")
    .sign(orderTokenSecret());
}

async function verifyGuestAccess(token:string,scope:string,resourceId:string) {
  const v=await jwtVerify(token,orderTokenSecret(),{algorithms:["HS256"]});
  return v.payload.scope===scope && v.payload.resourceId===resourceId;
}

app.get("/health",async()=>{
  const r=await db.query("select current_database() as database_name, now() as database_time");
  const v=await q("select api.GET_SYSTEM_VERSION() as data");
  const databaseName=String(r.rows[0].database_name??"");
  const environment=
    databaseName==="fulfilment_prod" ? "PROD" :
    databaseName==="fulfilment_test" ? "TEST" :
    databaseName==="fulfilment_dev" ? "DEV" :
    "UNKNOWN";
  return{ok:true,service:"DYNETIC WMS API",version:v?.version??null,environment,databaseTime:r.rows[0].database_time};
});
app.get("/api/system/version",async()=> await q("select api.GET_SYSTEM_VERSION() as data"));

/* PUBLIC CATALOGUE */
app.get("/api/catalog/categories",async()=> (await q("select api.GET_CATEGORIES($1) as data",[clientId]))??[]);
app.get("/api/catalog/products",async(req)=>{const x=req.query as {category?:string};return (await q("select api.GET_CATALOG($1,$2) as data",[clientId,x.category??null]))??[];});
app.get("/api/catalog/search",async(req)=>{const x=req.query as {q?:string;category?:string;availability?:string;saleType?:string};return (await q("select api.SEARCH_CATALOG($1,$2,$3,$4,$5) as data",[clientId,x.q??null,x.category??null,x.availability??null,x.saleType??null]))??[];});
app.get("/api/catalog/products/:slug",async(req,reply)=>{const {slug}=req.params as {slug:string};const d=await q("select api.GET_PRODUCT($1,$2) as data",[clientId,slug]);return d?d:reply.code(404).send({error:"PRODUCT_NOT_FOUND"});});
app.get("/api/catalog/products/:slug/media",async(req,reply)=>{const {slug}=req.params as {slug:string};const p=await db.query("select PRODUCT_ID from core.PRODUCT where CLIENT_ID=$1 and SLUG=$2 and ACTIVE=true",[clientId,slug]);if(!p.rowCount)return reply.code(404).send({error:"PRODUCT_NOT_FOUND"});return (await q("select api.GET_PRODUCT_MEDIA($1,$2) as data",[clientId,p.rows[0].product_id]))??[];});
app.get("/api/catalog/products/:slug/affiliate-links",async(req)=>{const {slug}=req.params as {slug:string};return (await q("select api.GET_AFFILIATE_LINKS($1,$2) as data",[clientId,slug]))??[];});
app.get("/api/catalog/products/:slug/reviews",async(req)=>{const {slug}=req.params as {slug:string};return await q("select api.GET_PRODUCT_REVIEWS($1,$2) as data",[clientId,slug]);});
app.post("/api/catalog/products/:slug/reviews",async(req,reply)=>{const {slug}=req.params as {slug:string};try{return reply.code(202).send(await q("select api.SUBMIT_PRODUCT_REVIEW($1,$2,$3::jsonb) as data",[clientId,slug,JSON.stringify(req.body??{})]));}catch{return reply.code(400).send({error:"INVALID_REVIEW"});}});

/* PUBLIC ADDRESS LOOKUP: provider key stays server-side; manual checkout never depends on this feature. */
app.get("/api/address/search",async(req,reply)=>{
  const x=req.query as {q?:string;country?:string};
  try{
    const items=await searchUkAddresses(String(x.q??""),String(x.country??"GB"));
    return {items};
  }catch(e){
    if(e instanceof AddressLookupError){
      if(e.status>=500) req.log.warn({code:e.code},"Address lookup unavailable");
      return reply.code(e.status).send({error:e.code});
    }
    req.log.error(e);
    return reply.code(503).send({error:"ADDRESS_LOOKUP_UNAVAILABLE"});
  }
});

app.get("/api/address/resolve/:id",async(req,reply)=>{
  const {id}=req.params as {id:string};
  try{
    const address=await resolveUkAddress(id);
    return {address};
  }catch(e){
    if(e instanceof AddressLookupError){
      if(e.status>=500) req.log.warn({code:e.code},"Address lookup unavailable");
      return reply.code(e.status).send({error:e.code});
    }
    req.log.error(e);
    return reply.code(503).send({error:"ADDRESS_LOOKUP_UNAVAILABLE"});
  }
});

/* PUBLIC CHECKOUT PRE-FLIGHT */
app.post("/api/checkout/validate",async(req,reply)=>{const b=req.body as {items?:unknown[]};const d=await q("select api.VALIDATE_BASKET($1,$2::jsonb) as data",[clientId,JSON.stringify(b.items??[])]);return reply.code(d?.valid?200:400).send(d);});
app.post("/api/delivery/options",async(req,reply)=>{const d=await q("select api.GET_DELIVERY_OPTIONS($1,$2::jsonb) as data",[clientId,JSON.stringify(req.body??{})]);return reply.code(d?.valid?200:400).send(d);});
app.post("/api/checkout/quote",async(req,reply)=>{const d=await q("select api.QUOTE_CHECKOUT($1,$2::jsonb) as data",[clientId,JSON.stringify(req.body??{})]);return reply.code(d?.valid?200:400).send(d);});
app.post("/api/promotions/validate",async(req)=>{const b=req.body as {code:string;orderValue:number;deliveryClass?:string};return await q("select api.VALIDATE_PROMOTION($1,$2,$3,$4) as data",[clientId,b.code,b.orderValue,b.deliveryClass??null]);});
app.post("/api/gift-cards/balance",async(req,reply)=>{const b=req.body as {code?:string};if(!b.code)return reply.code(400).send({error:"CODE_REQUIRED"});const d=await q("select api.GET_GIFT_CARD_BALANCE($1,$2) as data",[clientId,b.code]);return d??reply.code(404).send({error:"GIFT_CARD_NOT_FOUND"});});
app.post("/api/affiliate/click",async(req,reply)=>{const b=req.body as {linkId?:string;sessionId?:string;source?:string;referrer?:string};if(!b.linkId)return reply.code(400).send({error:"LINK_ID_REQUIRED"});try{return await q("select api.RECORD_AFFILIATE_CLICK($1,$2::uuid,$3::jsonb) as data",[clientId,b.linkId,JSON.stringify({...b,userAgent:req.headers["user-agent"]??null})]);}catch{return reply.code(404).send({error:"AFFILIATE_LINK_NOT_FOUND"});}});
app.post("/api/preferences",async(req,reply)=>{try{return await q("select api.SET_CONTACT_PREFERENCE($1,$2::jsonb) as data",[clientId,JSON.stringify(req.body??{})]);}catch{return reply.code(400).send({error:"INVALID_PREFERENCE"});}});

/* INTEREST / RESERVATION: guest permitted, account is attached when authenticated */
app.post("/api/interests",async(req,reply)=>{
  try {
    const id=await optionalIdentity(req,clientId);
    const payload={...(req.body as any??{}),accountId:id?.accountId??null};
    const d=await q("select api.CREATE_CUSTOMER_INTEREST($1,$2::jsonb) as data",[clientId,JSON.stringify(payload)]);
    if(id?.accountId && d?.interestId) await db.query("update core.CUSTOMER_INTEREST set ACCOUNT_ID=$1 where CLIENT_ID=$2 and INTEREST_ID=$3::uuid",[id.accountId,clientId,d.interestId]);
    return reply.code(201).send(d);
  } catch(e){return reply.code(400).send({error:errorCode(e)});}
});
app.post("/api/reservations",async(req,reply)=>{
  try {
    const id=await optionalIdentity(req,clientId);
    const body=req.body as any ?? {};
    const d=await q("select api.CREATE_STOCK_RESERVATION($1,$2::jsonb) as data",[clientId,JSON.stringify(body)]);
    if(id?.accountId && d?.reservationId) {
      await db.query("update core.STOCK_RESERVATION set ACCOUNT_ID=$1 where CLIENT_ID=$2 and RESERVATION_ID=$3::uuid",[id.accountId,clientId,d.reservationId]);
      return reply.code(201).send({...d,accountReservation:true});
    }
    const email=String(body?.email??body?.customer?.email??"");
    const reservationAccessToken=await signGuestAccess("reservation:manage",String(d.reservationId),email);
    return reply.code(201).send({...d,accountReservation:false,reservationAccessToken});
  } catch(e){req.log.error(e);return reply.code(409).send({error:errorCode(e)});}
});

/* CUSTOMER ACCOUNT */
app.get("/api/account",async(req,reply)=>{
  try{const id=await requireIdentity(req,clientId);return await q("select api.GET_ACCOUNT($1,$2::uuid) as data",[clientId,id.accountId]);}
  catch(e){return reply.code(401).send({error:errorCode(e)});}
});
app.get("/api/account/addresses",async(req,reply)=>{
  try{const id=await requireIdentity(req,clientId);return await q("select api.GET_ACCOUNT_ADDRESSES($1,$2::uuid) as data",[clientId,id.accountId]);}
  catch(e){return reply.code(401).send({error:errorCode(e)});}
});
app.post("/api/account/addresses",async(req,reply)=>{
  try{const id=await requireIdentity(req,clientId);return reply.code(201).send(await q("select api.SAVE_ACCOUNT_ADDRESS($1,$2::uuid,$3::jsonb) as data",[clientId,id.accountId,JSON.stringify(req.body??{})]));}
  catch(e){return reply.code(400).send({error:errorCode(e)});}
});
app.get("/api/account/favourites",async(req,reply)=>{
  try{const id=await requireIdentity(req,clientId);return await q("select api.GET_PRODUCT_FAVOURITES($1,$2::uuid) as data",[clientId,id.accountId]);}
  catch(e){return reply.code(401).send({error:errorCode(e)});}
});
app.put("/api/account/favourites/:slug",async(req,reply)=>{
  try{const id=await requireIdentity(req,clientId);const {slug}=req.params as {slug:string};return await q("select api.SET_PRODUCT_FAVOURITE($1,$2::uuid,$3,true) as data",[clientId,id.accountId,slug]);}
  catch(e){return reply.code(400).send({error:errorCode(e)});}
});
app.delete("/api/account/favourites/:slug",async(req,reply)=>{
  try{const id=await requireIdentity(req,clientId);const {slug}=req.params as {slug:string};return await q("select api.SET_PRODUCT_FAVOURITE($1,$2::uuid,$3,false) as data",[clientId,id.accountId,slug]);}
  catch(e){return reply.code(400).send({error:errorCode(e)});}
});
app.get("/api/account/orders",async(req,reply)=>{
  try{const id=await requireIdentity(req,clientId);return await q("select api.GET_ACCOUNT_ORDERS($1,$2::uuid) as data",[clientId,id.accountId]);}
  catch(e){return reply.code(401).send({error:errorCode(e)});}
});
app.get("/api/account/interests",async(req,reply)=>{
  try{const id=await requireIdentity(req,clientId);return await q("select api.GET_ACCOUNT_INTERESTS($1,$2::uuid) as data",[clientId,id.accountId]);}
  catch(e){return reply.code(401).send({error:errorCode(e)});}
});
app.get("/api/account/reservations",async(req,reply)=>{
  try{const id=await requireIdentity(req,clientId);return await q("select api.GET_ACCOUNT_RESERVATIONS($1,$2::uuid) as data",[clientId,id.accountId]);}
  catch(e){return reply.code(401).send({error:errorCode(e)});}
});


app.get("/api/reservations/:reservationId",async(req,reply)=>{
  const {reservationId}=req.params as {reservationId:string};
  try{
    const id=await optionalIdentity(req,clientId);
    if(id){
      const own=await db.query("select 1 from core.STOCK_RESERVATION where CLIENT_ID=$1 and RESERVATION_ID=$2::uuid and ACCOUNT_ID=$3::uuid",[clientId,reservationId,id.accountId]);
      if(!own.rowCount)return reply.code(403).send({error:"RESERVATION_NOT_OWNED"});
    }else{
      const token=String(req.headers["x-reservation-access-token"]??"");
      if(!token || !(await verifyGuestAccess(token,"reservation:manage",reservationId))) return reply.code(401).send({error:"RESERVATION_ACCESS_TOKEN_REQUIRED"});
    }
    return (await q("select api.GET_STOCK_RESERVATION($1,$2::uuid) as data",[clientId,reservationId]))??reply.code(404).send({error:"RESERVATION_NOT_FOUND"});
  }catch(e){return reply.code(401).send({error:errorCode(e)});}
});
app.delete("/api/reservations/:reservationId",async(req,reply)=>{
  const {reservationId}=req.params as {reservationId:string};
  try{
    const id=await optionalIdentity(req,clientId);
    if(id){
      const own=await db.query("select 1 from core.STOCK_RESERVATION where CLIENT_ID=$1 and RESERVATION_ID=$2::uuid and ACCOUNT_ID=$3::uuid",[clientId,reservationId,id.accountId]);
      if(!own.rowCount)return reply.code(403).send({error:"RESERVATION_NOT_OWNED"});
    }else{
      const token=String(req.headers["x-reservation-access-token"]??"");
      if(!token || !(await verifyGuestAccess(token,"reservation:manage",reservationId))) return reply.code(401).send({error:"RESERVATION_ACCESS_TOKEN_REQUIRED"});
    }
    return await q("select api.RELEASE_STOCK_RESERVATION($1,$2::uuid,'CANCELLED') as data",[clientId,reservationId]);
  }catch(e){return reply.code(401).send({error:errorCode(e)});}
});

/* ORDER CREATION: guest or account. Account id is injected server-side, never trusted from body. */
app.post("/api/orders",async(req,reply)=>{
  try {
    const id=await optionalIdentity(req,clientId);
    const body={...(req.body as any??{})};
    if(id?.email && !body?.customer?.email) body.customer={...(body.customer??{}),email:id.email};
    const d=await q(
      "select api.CREATE_PENDING_WEB_ORDER($1,$2::jsonb,$3::uuid,$4) as data",
      [clientId,JSON.stringify(body),id?.accountId??null,Number(process.env.PAYMENT_TIMEOUT_MINUTES??30)]
    );
    if(d?.status==='REJECTED')return reply.code(400).send(d);
    if(d?.status!=='PENDING_PAYMENT')return reply.code(500).send(d);

    if(id?.accountId){
      return reply.code(201).send({...d,accountOrder:true});
    }

    const email=String(body?.customer?.email??"");
    const orderAccessToken=await signGuestAccess("order:read",d.orderId,email);
    return reply.code(201).send({...d,accountOrder:false,orderAccessToken});
  } catch(e){req.log.error(e);return reply.code(400).send({error:errorCode(e)});}
});

app.post("/api/reservations/:reservationId/convert",async(req,reply)=>{
  const {reservationId}=req.params as {reservationId:string};
  try {
    const id=await optionalIdentity(req,clientId);
    if(id){
      const own=await db.query("select 1 from core.STOCK_RESERVATION where CLIENT_ID=$1 and RESERVATION_ID=$2::uuid and ACCOUNT_ID=$3::uuid",[clientId,reservationId,id.accountId]);
      if(!own.rowCount)return reply.code(403).send({error:"RESERVATION_NOT_OWNED"});
    }else{
      const token=String(req.headers["x-reservation-access-token"]??"");
      if(!token || !(await verifyGuestAccess(token,"reservation:manage",reservationId))) return reply.code(401).send({error:"RESERVATION_ACCESS_TOKEN_REQUIRED"});
    }
    const body={...(req.body as any??{})};
    if(id?.email && !body?.customer?.email) body.customer={...(body.customer??{}),email:id.email};
    const d=await q("select api.SUBMIT_RESERVED_WEB_ORDER($1,$2::uuid,$3::jsonb) as data",[clientId,reservationId,JSON.stringify(body)]);
    if(id?.accountId){
      await q("select api.CLAIM_ORDER_ACCOUNT($1,$2,$3::uuid,$4) as data",[clientId,d.orderId,id.accountId,id.email]);
      await db.query("update core.STOCK_RESERVATION set ACCOUNT_ID=$1 where CLIENT_ID=$2 and RESERVATION_ID=$3::uuid",[id.accountId,clientId,reservationId]);
    }
    return reply.code(201).send(d);
  } catch(e){req.log.error(e);return reply.code(409).send({error:errorCode(e)});}
});

/* SECURE ORDER LOOKUP */
app.get("/api/orders/:orderId",async(req,reply)=>{
  const {orderId}=req.params as {orderId:string};
  try {
    const id=await optionalIdentity(req,clientId);
    if(id){
      const own=await db.query("select 1 from core.ORDER_HEADER where CLIENT_ID=$1 and ORDER_ID=$2 and ACCOUNT_ID=$3::uuid",[clientId,orderId,id.accountId]);
      if(!own.rowCount){await auditSecurity(req,"DENIED","ORDER_NOT_OWNED","ORDER",orderId);return reply.code(403).send({error:"ORDER_NOT_OWNED"});}
    } else {
      const token=String(req.headers["x-order-access-token"]??"");
      if(!token || !(await verifyGuestAccess(token,"order:read",orderId))){
        await auditSecurity(req,"DENIED","GUEST_ORDER_TOKEN_REQUIRED","ORDER",orderId);
        return reply.code(401).send({error:"ORDER_ACCESS_TOKEN_REQUIRED"});
      }
    }
    return (await q("select api.GET_ORDER_STATUS($1,$2) as data",[clientId,orderId]))??reply.code(404).send({error:"ORDER_NOT_FOUND"});
  } catch(e){return reply.code(401).send({error:errorCode(e)});}
});

/* PAYMENT: amount is always loaded from DYNETIC WMS order/reservation; browser cannot set it. */
app.post("/api/payments/prepare",async(req,reply)=>{
  try{
    const id=await optionalIdentity(req,clientId);
    const b=req.body as {referenceType:string;referenceId:string;provider?:string;idempotencyKey:string};
    const referenceType=String(b.referenceType??"").toUpperCase();

    if(!id){
      if(referenceType==="ORDER"){
        const token=String(req.headers["x-order-access-token"]??"");
        if(!token || !(await verifyGuestAccess(token,"order:read",b.referenceId))) return reply.code(401).send({error:"ORDER_ACCESS_TOKEN_REQUIRED"});
      }else if(referenceType==="RESERVATION"){
        const token=String(req.headers["x-reservation-access-token"]??"");
        if(!token || !(await verifyGuestAccess(token,"reservation:manage",b.referenceId))) return reply.code(401).send({error:"RESERVATION_ACCESS_TOKEN_REQUIRED"});
      }else return reply.code(400).send({error:"UNSUPPORTED_PAYMENT_REFERENCE"});
    }

    const p=await q(
      "select api.CREATE_PAYMENT_REQUEST($1,$2::uuid,$3,$4,$5,$6) as data",
      [clientId,id?.accountId??null,referenceType,b.referenceId,b.provider??"STRIPE",b.idempotencyKey]
    );
    if((p.provider??"").toUpperCase()!=="STRIPE")
      return reply.code(501).send({error:"PAYMENT_PROVIDER_NOT_INTEGRATED",payment:p});
    const result=await createStripePaymentIntent(clientId,p,b.idempotencyKey);
    return reply.code(201).send(result);
  }catch(e){req.log.error(e);return reply.code(400).send({error:errorCode(e)});}
});

app.get("/api/payments/:paymentId",async(req,reply)=>{
  try{
    const id=await optionalIdentity(req,clientId);
    const {paymentId}=req.params as {paymentId:string};
    const r=await db.query(
      "select REFERENCE_TYPE,REFERENCE_ID,ACCOUNT_ID from core.PAYMENT_TRANSACTION where CLIENT_ID=$1 and PAYMENT_ID=$2::uuid",
      [clientId,paymentId]
    );
    if(!r.rowCount)return reply.code(404).send({error:"PAYMENT_NOT_FOUND"});
    const p=r.rows[0];

    if(id){
      if(p.account_id && p.account_id!==id.accountId)return reply.code(403).send({error:"PAYMENT_NOT_OWNED"});
    }else if(p.reference_type==="ORDER"){
      const token=String(req.headers["x-order-access-token"]??"");
      if(!token || !(await verifyGuestAccess(token,"order:read",p.reference_id)))return reply.code(401).send({error:"ORDER_ACCESS_TOKEN_REQUIRED"});
    }else if(p.reference_type==="RESERVATION"){
      const token=String(req.headers["x-reservation-access-token"]??"");
      if(!token || !(await verifyGuestAccess(token,"reservation:manage",p.reference_id)))return reply.code(401).send({error:"RESERVATION_ACCESS_TOKEN_REQUIRED"});
    }else return reply.code(401).send({error:"PAYMENT_ACCESS_DENIED"});

    return await q("select api.GET_PAYMENT_STATUS($1,$2::uuid,NULL) as data",[clientId,paymentId]);
  }catch(e){return reply.code(401).send({error:errorCode(e)});}
});

/* Stripe webhook: raw request signature is authoritative; browser callbacks never mark an order paid. */
app.post("/api/webhooks/stripe",async(req,reply)=>{
  try{
    const sig=String(req.headers["stripe-signature"]??"");
    const raw=req.rawJsonBody;
    if(!raw || !sig) return reply.code(400).send({error:"STRIPE_SIGNATURE_REQUIRED"});
    verifyStripeSignature(raw,sig);
    const evt=normaliseStripeEvent(req.body);
    if(!evt.providerEventId || !evt.providerReference) return reply.code(200).send({received:true,ignored:true});
    const d=await q(
      "select api.PROCESS_PAYMENT_EVENT($1,'STRIPE',$2,$3,$4,$5::jsonb) as data",
      [clientId,evt.providerEventId,evt.eventType,evt.providerReference,JSON.stringify(evt.payload)]
    );
    return reply.code(200).send({received:true,result:d});
  }catch(e){req.log.error(e);return reply.code(400).send({error:errorCode(e)});}
});

registerAdminAccessRoutes(app, clientId);
registerAdminManagementRoutes(app, clientId);

/* ADMIN ONLY */
app.get("/api/admin/interests/summary",async(req,reply)=>{
  try{await requirePermission(req,clientId,"customer.read");const x=req.query as {skuId:string};return await q("select api.GET_INTEREST_SUMMARY($1,$2) as data",[clientId,x.skuId]);}
  catch(e){return reply.code(errorCode(e)==="AUTHENTICATION_REQUIRED"?401:403).send({error:errorCode(e)});}
});
app.post("/api/admin/reviews/:reviewId/moderate",async(req,reply)=>{
  try{
    const principal=await requirePermission(req,clientId,"review.moderate");
    const {reviewId}=req.params as {reviewId:string};
    const requestBody=req.body??{};
    const result=await q("select api.MODERATE_PRODUCT_REVIEW($1,$2::uuid,$3::jsonb) as data",[clientId,reviewId,JSON.stringify(requestBody)]);
    await auditAdminChange(clientId,principal,"PRODUCT_REVIEW",reviewId,"MODERATE",null,{request:requestBody,result});
    return result;
  }
  catch(e){return reply.code(errorCode(e)==="AUTHENTICATION_REQUIRED"?401:403).send({error:errorCode(e)});}
});
app.get("/api/admin/affiliate/demand",async(req,reply)=>{
  try{await requirePermission(req,clientId,"affiliate.read");return await q("select api.GET_AFFILIATE_DEMAND($1) as data",[clientId]);}
  catch(e){return reply.code(errorCode(e)==="AUTHENTICATION_REQUIRED"?401:403).send({error:errorCode(e)});}
});
app.post("/api/admin/reservations/expire",async(req,reply)=>{
  try{
    const principal=await requirePermission(req,clientId,"reservation.expire");
    const reservations=await q("select api.EXPIRE_STOCK_RESERVATIONS($1) as data",[clientId]);
    const orders=await q("select api.EXPIRE_PENDING_PAYMENT_ORDERS($1) as data",[clientId]);
    const result={reservations,orders};
    await auditAdminChange(clientId,principal,"RESERVATION_EXPIRY","MANUAL","RUN",null,result);
    return result;
  } catch(e){return reply.code(errorCode(e)==="AUTHENTICATION_REQUIRED"?401:403).send({error:errorCode(e)});}
});
app.post("/api/admin/payments/:paymentId/refund",async(req,reply)=>{
  try{
    const principal=await requirePermission(req,clientId,"payment.refund");
    const {paymentId}=req.params as {paymentId:string};
    const b=req.body as {amount?:number};
    const r=await db.query("select PROVIDER,PROVIDER_REFERENCE,AMOUNT,REFUNDED_AMOUNT from core.PAYMENT_TRANSACTION where CLIENT_ID=$1 and PAYMENT_ID=$2::uuid",[clientId,paymentId]);
    if(!r.rowCount)return reply.code(404).send({error:"PAYMENT_NOT_FOUND"});
    const p=r.rows[0];
    if(p.provider!=="STRIPE" || !p.provider_reference)return reply.code(400).send({error:"STRIPE_PAYMENT_REQUIRED"});
    const max=Number(p.amount)-Number(p.refunded_amount);
    const amount=b.amount==null?undefined:Number(b.amount);
    if(amount!=null && (amount<=0 || amount>max))return reply.code(400).send({error:"INVALID_REFUND_AMOUNT"});
    const result=await createStripeRefund(p.provider_reference,amount);
    await auditAdminChange(clientId,principal,"PAYMENT_TRANSACTION",paymentId,"REFUND_REQUESTED",p,{requestedAmount:amount??max,result});
    return reply.code(202).send(result);
  }catch(e){
    req.log.error(e);
    return reply.code(errorCode(e)==="AUTHENTICATION_REQUIRED"?401:403).send({error:errorCode(e)});
  }
});

const port=Number(process.env.PORT??3001);
app.listen({port,host:"0.0.0.0"}).catch((e)=>{app.log.error(e);process.exit(1);});
