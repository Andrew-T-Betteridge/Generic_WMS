import crypto from "node:crypto";
import { db } from "./db.js";

const apiBase = process.env.STRIPE_API_BASE ?? "https://api.stripe.com/v1";

function stripeKey(): string {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new Error("STRIPE_NOT_CONFIGURED");
  return key;
}

async function stripePost(path: string, body: URLSearchParams, idempotencyKey?: string) {
  const headers: Record<string,string> = {
    authorization: `Bearer ${stripeKey()}`,
    "content-type": "application/x-www-form-urlencoded"
  };
  if (idempotencyKey) headers["idempotency-key"] = idempotencyKey;

  const r = await fetch(`${apiBase}${path}`,{method:"POST",headers,body});
  const data = await r.json() as Record<string,unknown>;
  if (!r.ok) throw new Error(`STRIPE_ERROR:${JSON.stringify(data)}`);
  return data;
}

export async function createStripePaymentIntent(
  clientId: string,
  payment: {paymentId:string;amount:number;currency:string;referenceType:string;referenceId:string},
  idempotencyKey: string
) {
  const p = new URLSearchParams();
  p.set("amount",String(Math.round(Number(payment.amount)*100)));
  p.set("currency",String(payment.currency).toLowerCase());
  p.set("automatic_payment_methods[enabled]","true");
  p.set("metadata[client_id]",clientId);
  p.set("metadata[payment_id]",payment.paymentId);
  p.set("metadata[reference_type]",payment.referenceType);
  p.set("metadata[reference_id]",payment.referenceId);

  const intent = await stripePost("/payment_intents",p,idempotencyKey);
  await db.query(
    "select api.SET_PAYMENT_PROVIDER_REFERENCE($1,$2::uuid,$3,$4)",
    [clientId,payment.paymentId,String(intent.id),String(intent.status ?? "")]
  );
  return {
    paymentId: payment.paymentId,
    provider: "STRIPE",
    providerReference: intent.id,
    clientSecret: intent.client_secret,
    status: intent.status,
    amount: payment.amount,
    currency: payment.currency
  };
}

export async function createStripeRefund(providerReference: string, amount?: number) {
  const p = new URLSearchParams();
  p.set("payment_intent",providerReference);
  if (amount != null) p.set("amount",String(Math.round(amount*100)));
  return stripePost("/refunds",p);
}

export function verifyStripeSignature(rawBody: Buffer, signatureHeader: string) {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) throw new Error("STRIPE_WEBHOOK_SECRET_REQUIRED");

  const parts = signatureHeader.split(",").map(v=>v.split("="));
  const timestamp = parts.find(([k])=>k==="t")?.[1];
  const signatures = parts.filter(([k])=>k==="v1").map(([,v])=>v);
  if (!timestamp || !signatures.length) throw new Error("INVALID_STRIPE_SIGNATURE");

  const tolerance = Number(process.env.STRIPE_WEBHOOK_TOLERANCE_SECONDS ?? 300);
  if (Math.abs(Date.now()/1000-Number(timestamp))>tolerance) throw new Error("STRIPE_SIGNATURE_EXPIRED");

  const expected = crypto.createHmac("sha256",secret)
    .update(`${timestamp}.${rawBody.toString("utf8")}`)
    .digest("hex");

  const expectedBuffer = Buffer.from(expected,"hex");
  const ok = signatures.some(s=>{
    try {
      const got = Buffer.from(s,"hex");
      return got.length===expectedBuffer.length && crypto.timingSafeEqual(got,expectedBuffer);
    } catch { return false; }
  });
  if (!ok) throw new Error("INVALID_STRIPE_SIGNATURE");
}

export function normaliseStripeEvent(event: any) {
  const obj = event?.data?.object ?? {};
  const type = String(event?.type ?? "");
  let providerReference = String(obj.id ?? "");

  if (type==="charge.refunded") {
    providerReference = String(obj.payment_intent ?? "");
  }

  return {
    providerEventId: String(event?.id ?? ""),
    eventType: type,
    providerReference,
    payload: {
      providerStatus: obj.status ?? null,
      amountReceived: obj.amount_received != null ? Number(obj.amount_received)/100 : undefined,
      amountRefunded: obj.amount_refunded != null ? Number(obj.amount_refunded)/100 : undefined,
      failureCode: obj.last_payment_error?.code ?? null,
      failureText: obj.last_payment_error?.message ?? null
    }
  };
}
