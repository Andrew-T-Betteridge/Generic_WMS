import crypto from "node:crypto";
import { db } from "./db.js";

const apiBase =
  process.env.STRIPE_API_BASE ??
  "https://api.stripe.com/v1";

function stripeKey():string{
  const key=process.env.STRIPE_SECRET_KEY;
  if(!key) throw new Error("STRIPE_NOT_CONFIGURED");
  return key;
}

async function stripePost(
  path:string,
  body:URLSearchParams,
  idempotencyKey?:string,
){
  const headers:Record<string,string>={
    authorization:`Bearer ${stripeKey()}`,
    "content-type":"application/x-www-form-urlencoded",
  };

  if(idempotencyKey){
    headers["idempotency-key"]=idempotencyKey;
  }

  const r=await fetch(
    `${apiBase}${path}`,
    {
      method:"POST",
      headers,
      body,
    },
  );

  const data=
    await r.json() as Record<string,unknown>;

  if(!r.ok){
    throw new Error(
      `STRIPE_ERROR:${JSON.stringify(data)}`
    );
  }

  return data;
}

type Payment={
  paymentId:string;
  amount:number;
  currency:string;
  referenceType:string;
  referenceId:string;
};

type CustomerContext={
  email:string;
  name:string|null;
  accountId:string|null;
};

async function getCustomerContext(
  clientId:string,
  payment:Payment,
):Promise<CustomerContext|null>{
  if(payment.referenceType==="ORDER"){
    const r=await db.query(
      `select
         CONTACT_EMAIL as EMAIL,
         COALESCE(
           NULLIF(CONTACT,''),
           NULLIF(NAME,'')
         ) as NAME,
         ACCOUNT_ID
       from core.ORDER_HEADER
       where CLIENT_ID=$1
         and ORDER_ID=$2`,
      [clientId,payment.referenceId],
    );

    if(!r.rowCount) return null;

    const row=r.rows[0];

    const email=
      String(row.email ?? "")
        .trim()
        .toLowerCase();

    if(!email) return null;

    return {
      email,
      name:
        String(row.name ?? "").trim() ||
        null,
      accountId:row.account_id
        ? String(row.account_id)
        : null,
    };
  }

  if(payment.referenceType==="RESERVATION"){
    const r=await db.query(
      `select
         EMAIL,
         CONTACT_NAME as NAME,
         ACCOUNT_ID
       from core.STOCK_RESERVATION
       where CLIENT_ID=$1
         and RESERVATION_ID=$2::uuid`,
      [clientId,payment.referenceId],
    );

    if(!r.rowCount) return null;

    const row=r.rows[0];

    const email=
      String(row.email ?? "")
        .trim()
        .toLowerCase();

    if(!email) return null;

    return {
      email,
      name:
        String(row.name ?? "").trim() ||
        null,
      accountId:row.account_id
        ? String(row.account_id)
        : null,
    };
  }

  return null;
}

function customerKey(
  clientId:string,
  email:string,
){
  return crypto
    .createHash("sha256")
    .update(`${clientId}:${email}`)
    .digest("hex")
    .slice(0,48);
}

async function getOrCreateStripeCustomer(
  clientId:string,
  context:CustomerContext,
){
  const existing=await db.query(
    `select PROVIDER_CUSTOMER_ID
       from core.PAYMENT_CUSTOMER
      where CLIENT_ID=$1
        and PROVIDER='STRIPE'
        and LOWER(EMAIL)=LOWER($2)
      limit 1`,
    [clientId,context.email],
  );

  if(existing.rowCount){
    const customerId=
      String(
        existing.rows[0].provider_customer_id
      );

    await db.query(
      `update core.PAYMENT_CUSTOMER
          set CUSTOMER_NAME=COALESCE($3,CUSTOMER_NAME),
              ACCOUNT_ID=COALESCE(ACCOUNT_ID,$4::uuid),
              LAST_UPDATE_DSTAMP=now()
        where CLIENT_ID=$1
          and PROVIDER='STRIPE'
          and LOWER(EMAIL)=LOWER($2)`,
      [
        clientId,
        context.email,
        context.name,
        context.accountId,
      ],
    );

    return customerId;
  }

  const body=new URLSearchParams();

  body.set("email",context.email);

  if(context.name){
    body.set("name",context.name);
  }

  body.set(
    "metadata[client_id]",
    clientId,
  );

  if(context.accountId){
    body.set(
      "metadata[account_id]",
      context.accountId,
    );
  }

  const created=await stripePost(
    "/customers",
    body,
    `customer-${customerKey(
      clientId,
      context.email,
    )}`,
  );

  const customerId=
    String(created.id ?? "");

  if(!customerId){
    throw new Error(
      "STRIPE_CUSTOMER_ID_MISSING"
    );
  }

  await db.query(
    `insert into core.PAYMENT_CUSTOMER(
       CLIENT_ID,
       PROVIDER,
       EMAIL,
       CUSTOMER_NAME,
       ACCOUNT_ID,
       PROVIDER_CUSTOMER_ID
     )
     values(
       $1,
       'STRIPE',
       $2,
       $3,
       $4::uuid,
       $5
     )
     on conflict do nothing`,
    [
      clientId,
      context.email,
      context.name,
      context.accountId,
      customerId,
    ],
  );

  const mapped=await db.query(
    `select PROVIDER_CUSTOMER_ID
       from core.PAYMENT_CUSTOMER
      where CLIENT_ID=$1
        and PROVIDER='STRIPE'
        and LOWER(EMAIL)=LOWER($2)
      limit 1`,
    [clientId,context.email],
  );

  return String(
    mapped.rows[0]?.provider_customer_id ??
    customerId
  );
}

export async function createStripePaymentIntent(
  clientId:string,
  payment:Payment,
  idempotencyKey:string,
){
  const customer=
    await getCustomerContext(
      clientId,
      payment,
    );

  let stripeCustomerId:string|null=null;

  if(customer){
    stripeCustomerId=
      await getOrCreateStripeCustomer(
        clientId,
        customer,
      );
  }

  const p=new URLSearchParams();

  p.set(
    "amount",
    String(
      Math.round(
        Number(payment.amount)*100
      )
    ),
  );

  p.set(
    "currency",
    String(payment.currency)
      .toLowerCase(),
  );

  p.set(
    "automatic_payment_methods[enabled]",
    "true",
  );

  p.set(
    "metadata[client_id]",
    clientId,
  );

  p.set(
    "metadata[payment_id]",
    payment.paymentId,
  );

  p.set(
    "metadata[reference_type]",
    payment.referenceType,
  );

  p.set(
    "metadata[reference_id]",
    payment.referenceId,
  );

  if(payment.referenceType==="ORDER"){
    p.set(
      "metadata[order_id]",
      payment.referenceId,
    );

    p.set(
      "description",
      `FINatics Aquatics order ${payment.referenceId}`,
    );
  }

  if(customer){
    p.set(
      "receipt_email",
      customer.email,
    );

    p.set(
      "metadata[customer_email]",
      customer.email,
    );

    if(customer.name){
      p.set(
        "metadata[customer_name]",
        customer.name,
      );
    }

    if(customer.accountId){
      p.set(
        "metadata[account_id]",
        customer.accountId,
      );
    }
  }

  if(stripeCustomerId){
    p.set(
      "customer",
      stripeCustomerId,
    );
  }

  const intent=await stripePost(
    "/payment_intents",
    p,
    idempotencyKey,
  );

  await db.query(
    "select api.SET_PAYMENT_PROVIDER_REFERENCE($1,$2::uuid,$3,$4)",
    [
      clientId,
      payment.paymentId,
      String(intent.id),
      String(intent.status ?? ""),
    ],
  );

  return {
    paymentId:payment.paymentId,
    provider:"STRIPE",
    providerReference:intent.id,
    customerId:stripeCustomerId,
    clientSecret:intent.client_secret,
    status:intent.status,
    amount:payment.amount,
    currency:payment.currency,
  };
}

export async function createStripeRefund(
  providerReference:string,
  amount?:number,
){
  const p=new URLSearchParams();

  p.set(
    "payment_intent",
    providerReference,
  );

  if(amount!=null){
    p.set(
      "amount",
      String(
        Math.round(amount*100)
      ),
    );
  }

  return stripePost(
    "/refunds",
    p,
  );
}

export function verifyStripeSignature(
  rawBody:Buffer,
  signatureHeader:string,
){
  const secret=
    process.env.STRIPE_WEBHOOK_SECRET;

  if(!secret){
    throw new Error(
      "STRIPE_WEBHOOK_SECRET_REQUIRED"
    );
  }

  const parts=
    signatureHeader
      .split(",")
      .map(v=>v.split("="));

  const timestamp=
    parts.find(([k])=>k==="t")?.[1];

  const signatures=
    parts
      .filter(([k])=>k==="v1")
      .map(([,v])=>v);

  if(
    !timestamp ||
    !signatures.length
  ){
    throw new Error(
      "INVALID_STRIPE_SIGNATURE"
    );
  }

  const tolerance=
    Number(
      process.env
        .STRIPE_WEBHOOK_TOLERANCE_SECONDS ??
      300
    );

  if(
    Math.abs(
      Date.now()/1000-
      Number(timestamp)
    )>tolerance
  ){
    throw new Error(
      "STRIPE_SIGNATURE_EXPIRED"
    );
  }

  const expected=
    crypto
      .createHmac(
        "sha256",
        secret,
      )
      .update(
        `${timestamp}.${rawBody.toString("utf8")}`
      )
      .digest("hex");

  const expectedBuffer=
    Buffer.from(
      expected,
      "hex",
    );

  const ok=signatures.some(s=>{
    try{
      const got=
        Buffer.from(
          s,
          "hex",
        );

      return (
        got.length===
        expectedBuffer.length &&
        crypto.timingSafeEqual(
          got,
          expectedBuffer,
        )
      );
    }catch{
      return false;
    }
  });

  if(!ok){
    throw new Error(
      "INVALID_STRIPE_SIGNATURE"
    );
  }
}

export function normaliseStripeEvent(
  event:any,
){
  const obj=
    event?.data?.object ?? {};

  const type=
    String(event?.type ?? "");

  let providerReference=
    String(obj.id ?? "");

  if(type==="charge.refunded"){
    providerReference=
      String(
        obj.payment_intent ?? ""
      );
  }

  return {
    providerEventId:
      String(event?.id ?? ""),

    eventType:type,

    providerReference,

    payload:{
      providerStatus:
        obj.status ?? null,

      amountReceived:
        obj.amount_received!=null
          ? Number(obj.amount_received)/100
          : undefined,

      amountRefunded:
        obj.amount_refunded!=null
          ? Number(obj.amount_refunded)/100
          : undefined,

      failureCode:
        obj.last_payment_error?.code ??
        null,

      failureText:
        obj.last_payment_error?.message ??
        null,
    },
  };
}
