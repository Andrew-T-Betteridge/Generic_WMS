import { db } from "./db.js";

let started=false;

function configured(){
  return Boolean(
    process.env.RESEND_API_KEY &&
    process.env.ADMIN_ALERT_EMAIL &&
    process.env.ADMIN_ALERT_FROM
  );
}

async function claimOne(){
  const client=await db.connect();

  try{
    await client.query("begin");

    const selected=await client.query(
      `select
         o.OUTBOX_ID,
         o.EVENT_ID,
         o.CLIENT_ID,
         o.CHANNEL,
         e.ORDER_ID,
         e.EVENT_TYPE,
         e.TITLE,
         e.MESSAGE,
         e.PAYLOAD
       from interface.NOTIFICATION_OUTBOX o
       join audit.ADMIN_NOTIFICATION_EVENT e
         on e.EVENT_ID=o.EVENT_ID
       where o.STATUS='PENDING'
         and o.NEXT_ATTEMPT_DSTAMP<=now()
         and o.CHANNEL='EMAIL'
       order by o.CREATED_DSTAMP
       limit 1
       for update of o skip locked`,
    );

    if(!selected.rowCount){
      await client.query("commit");
      return null;
    }

    const row=selected.rows[0];

    await client.query(
      `update interface.NOTIFICATION_OUTBOX
          set STATUS='PROCESSING',
              ATTEMPT_COUNT=ATTEMPT_COUNT+1
        where OUTBOX_ID=$1`,
      [row.outbox_id],
    );

    await client.query("commit");
    return row;
  }catch(e){
    try{await client.query("rollback")}catch{}
    throw e;
  }finally{
    client.release();
  }
}

async function sendEmail(row:Record<string,unknown>){
  const apiKey=process.env.RESEND_API_KEY!;
  const to=process.env.ADMIN_ALERT_EMAIL!;
  const from=process.env.ADMIN_ALERT_FROM!;

  const payload=row.payload as Record<string,unknown> ?? {};
  const value=payload.orderValue ?? payload.ordervalue;

  const response=await fetch("https://api.resend.com/emails",{
    method:"POST",
    headers:{
      "Authorization":`Bearer ${apiKey}`,
      "Content-Type":"application/json",
    },
    body:JSON.stringify({
      from,
      to:[to],
      subject:String(row.title ?? "FINatics order alert"),
      html:
        `<div style="font-family:Arial,sans-serif;max-width:600px">`+
        `<h2>${String(row.title ?? "FINatics order alert")}</h2>`+
        `<p>${String(row.message ?? "")}</p>`+
        `<p><strong>Order:</strong> ${String(row.order_id ?? "-")}</p>`+
        (value!=null
          ? `<p><strong>Order value:</strong> £${String(value)}</p>`
          : "")+
        `<p style="color:#666">DYNETIC WMS automatic notification</p>`+
        `</div>`,
    }),
  });

  if(!response.ok){
    const body=await response.text();
    throw new Error(
      `RESEND_${response.status}:${body.slice(0,400)}`
    );
  }
}

async function complete(
  outboxId:string,
  error?:unknown,
){
  if(!error){
    await db.query(
      `update interface.NOTIFICATION_OUTBOX
          set STATUS='SENT',
              SENT_DSTAMP=now(),
              LAST_ERROR=null
        where OUTBOX_ID=$1`,
      [outboxId],
    );
    return;
  }

  const message=String(
    (error as Error)?.message ?? error
  ).slice(0,2000);

  await db.query(
    `update interface.NOTIFICATION_OUTBOX
        set STATUS=case
              when ATTEMPT_COUNT>=5 then 'FAILED'
              else 'PENDING'
            end,
            NEXT_ATTEMPT_DSTAMP=
              now()+(
                least(ATTEMPT_COUNT,5) * interval '2 minutes'
              ),
            LAST_ERROR=$2
      where OUTBOX_ID=$1`,
    [outboxId,message],
  );
}

async function cycle(){
  if(!configured()) return;

  for(let i=0;i<10;i++){
    const row=await claimOne();
    if(!row) break;

    try{
      await sendEmail(row);
      await complete(String(row.outbox_id));
    }catch(e){
      await complete(String(row.outbox_id),e);
    }
  }
}

export function startNotificationDispatcher(){
  if(started) return;
  started=true;

  setTimeout(()=>{
    void cycle().catch(console.error);
  },5000);

  setInterval(()=>{
    void cycle().catch(console.error);
  },30000);
}
