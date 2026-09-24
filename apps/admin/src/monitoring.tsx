import {
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

type Obj=Record<string,unknown>;
type Token=()=>Promise<string>;

const BASE=(
  import.meta.env.VITE_API_BASE_URL ||
  "https://api.finaticsaquatics.co.uk"
).replace(/\/$/,"");

const get=(r:Obj,...keys:string[])=>{
  for(const key of keys){
    if(r[key]!==undefined) return r[key];
  }
};

const txt=(v:unknown,f="-")=>
  v===null||v===undefined||v==="" ? f : String(v);

const num=(v:unknown)=>
  Number.isFinite(Number(v)) ? Number(v) : 0;

const money=(v:unknown,c="GBP")=>
  Number.isFinite(Number(v))
    ? new Intl.NumberFormat("en-GB",{
        style:"currency",
        currency:c,
      }).format(Number(v))
    : "-";

const dt=(v:unknown)=>{
  if(!v) return "-";
  const d=new Date(String(v));
  return Number.isNaN(d.getTime())
    ? String(v)
    : d.toLocaleString("en-GB");
};

const query=(o:Obj)=>{
  const p=new URLSearchParams();
  Object.entries(o).forEach(([k,v])=>{
    if(v!==undefined&&v!==null&&v!==""){
      p.set(k,String(v));
    }
  });
  return p.size ? `?${p}` : "";
};

async function api<T>(
  token:Token,
  path:string,
  init:RequestInit={},
):Promise<T>{
  const h=new Headers(init.headers);
  h.set("Accept","application/json");
  h.set("Authorization",`Bearer ${await token()}`);

  if(init.body){
    h.set("Content-Type","application/json");
  }

  const r=await fetch(BASE+path,{
    ...init,
    headers:h,
  });

  const raw=await r.text();

  let body:any=null;
  try{
    body=raw ? JSON.parse(raw) : null;
  }catch{
    body=raw;
  }

  if(!r.ok){
    throw new Error(
      String(body?.error || body?.message || `HTTP_${r.status}`)
    );
  }

  return body as T;
}

function Btn({
  children,
  onClick,
  disabled,
  kind="",
}:{
  children:React.ReactNode;
  onClick?:()=>void;
  disabled?:boolean;
  kind?:string;
}){
  return (
    <button
      className={`btn ${kind}`}
      onClick={onClick}
      disabled={disabled}
    >
      {children}
    </button>
  );
}

function Pill({
  children,
  tone="",
}:{
  children:React.ReactNode;
  tone?:string;
}){
  return <span className={`pill ${tone}`}>{children}</span>;
}

function ErrorBox({error}:{error:unknown}){
  return (
    <div className="error">
      <strong>Could not load this area</strong>
      <span>
        {error instanceof Error ? error.message : String(error)}
      </span>
    </div>
  );
}

function Loader(){
  return <div className="load"><i/>Loading...</div>;
}

function Modal({
  title,
  onClose,
  children,
}:{
  title:string;
  onClose:()=>void;
  children:React.ReactNode;
}){
  return (
    <div
      className="shade"
      onMouseDown={e=>{
        if(e.target===e.currentTarget) onClose();
      }}
    >
      <div className="modal monitor-modal">
        <div className="modalhead">
          <h2>{title}</h2>
          <Btn kind="ghost" onClick={onClose}>Close</Btn>
        </div>
        <div className="modalbody">{children}</div>
      </div>
    </div>
  );
}

function playAlert(){
  try{
    const Ctx=
      window.AudioContext ||
      (window as any).webkitAudioContext;

    const ctx=new Ctx();
    const osc=ctx.createOscillator();
    const gain=ctx.createGain();

    osc.connect(gain);
    gain.connect(ctx.destination);

    osc.frequency.value=880;
    gain.gain.setValueAtTime(0.08,ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(
      0.001,
      ctx.currentTime+0.35,
    );

    osc.start();
    osc.stop(ctx.currentTime+0.35);
  }catch{}
}

export function NotificationBell({
  token,
}:{
  token:Token;
}){
  const[data,setData]=useState<{
    unread:number;
    items:Obj[];
  }>({unread:0,items:[]});

  const[open,setOpen]=useState(false);
  const[enabled,setEnabled]=useState(
    localStorage.getItem("finatics-alerts-enabled")==="true"
  );

  const lastSeen=useRef<string|null>(null);

  async function load(){
    const next=await api<{
      unread:number;
      items:Obj[];
    }>(token,"/api/admin/notifications?limit=30");

    const newest=next.items[0];
    const newestId=newest
      ? txt(get(newest,"event_id","EVENT_ID"),"")
      : "";

    if(
      lastSeen.current &&
      newestId &&
      newestId!==lastSeen.current &&
      enabled
    ){
      const paid=next.items.find(
        x=>
          txt(get(x,"event_type","EVENT_TYPE"))===
          "PAYMENT_CONFIRMED" &&
          txt(get(x,"event_id","EVENT_ID"))!==
          lastSeen.current
      );

      if(paid){
        playAlert();

        if(Notification.permission==="granted"){
          new Notification(
            txt(get(paid,"title","TITLE"),"New paid order"),
            {
              body:txt(
                get(paid,"message","MESSAGE"),
                "A new paid order requires attention."
              ),
            },
          );
        }
      }
    }

    if(newestId) lastSeen.current=newestId;
    setData(next);
  }

  useEffect(()=>{
    void load();

    const timer=setInterval(()=>{
      void load();
    },15000);

    return()=>clearInterval(timer);
  },[token,enabled]);

  async function enable(){
    if("Notification" in window){
      await Notification.requestPermission();
    }

    setEnabled(true);
    localStorage.setItem(
      "finatics-alerts-enabled",
      "true",
    );

    playAlert();
  }

  async function read(eventId:string){
    await api(
      token,
      `/api/admin/notifications/${eventId}/read`,
      {method:"POST"},
    );
    await load();
  }

  async function readAll(){
    await api(
      token,
      "/api/admin/notifications/read-all",
      {method:"POST"},
    );
    await load();
  }

  return (
    <div className="notification-wrap">
      <button
        className="notification-bell"
        onClick={()=>setOpen(x=>!x)}
        aria-label="Notifications"
      >
        <span className="bell-symbol">!</span>
        {data.unread>0 && (
          <b>{data.unread>99 ? "99+" : data.unread}</b>
        )}
      </button>

      {!enabled && (
        <button
          className="enable-alerts"
          onClick={enable}
        >
          Enable order alerts
        </button>
      )}

      {open && (
        <div className="notification-panel">
          <div className="notification-head">
            <div>
              <strong>Notifications</strong>
              <span>{data.unread} unread</span>
            </div>

            {data.unread>0 && (
              <button onClick={readAll}>
                Mark all read
              </button>
            )}
          </div>

          <div className="notification-list">
            {data.items.length===0 && (
              <div className="empty">
                No notifications yet.
              </div>
            )}

            {data.items.map(item=>{
              const id=txt(
                get(item,"event_id","EVENT_ID")
              );

              const isRead=
                get(item,"is_read","IS_READ")===true;

              const severity=txt(
                get(item,"severity","SEVERITY")
              ).toLowerCase();

              return (
                <button
                  key={id}
                  className={
                    `notification-item ${isRead?"read":""}`
                  }
                  onClick={()=>void read(id)}
                >
                  <i className={severity}/>
                  <div>
                    <strong>
                      {txt(get(item,"title","TITLE"))}
                    </strong>
                    <span>
                      {txt(get(item,"message","MESSAGE"))}
                    </span>
                    <small>
                      {dt(
                        get(
                          item,
                          "created_dstamp",
                          "CREATED_DSTAMP",
                        )
                      )}
                    </small>
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

export function LiveDashboard({
  token,
  me,
}:{
  token:Token;
  me:{displayName?:string|null;email:string};
}){
  const[data,setData]=useState<Obj|null>(null);
  const[error,setError]=useState<unknown>(null);

  async function load(){
    try{
      setData(
        await api<Obj>(
          token,
          "/api/admin/monitoring/summary",
        )
      );
      setError(null);
    }catch(e){
      setError(e);
    }
  }

  useEffect(()=>{
    void load();

    const timer=setInterval(()=>{
      void load();
    },20000);

    return()=>clearInterval(timer);
  },[token]);

  if(error) return <ErrorBox error={error}/>;
  if(!data) return <Loader/>;

  const recent=(
    get(data,"recentPaid") as Obj[] || []
  );

  const exceptions=(
    get(data,"exceptions") as Obj[] || []
  );

  const metrics=[
    {
      label:"New paid orders",
      value:num(get(data,"new_paid_orders")),
      tone:"attention",
    },
    {
      label:"Requires action",
      value:num(get(data,"orders_requiring_action")),
      tone:"attention",
    },
    {
      label:"Pending payment",
      value:num(get(data,"pending_payment")),
      tone:"",
    },
    {
      label:"Ready to dispatch",
      value:num(get(data,"ready_to_dispatch")),
      tone:"good",
    },
    {
      label:"Orders today",
      value:num(get(data,"orders_today")),
      tone:"",
    },
    {
      label:"Sales today",
      value:money(get(data,"paid_sales_today")),
      tone:"good",
    },
  ];

  return (
    <>
      <div className="head">
        <div>
          <h1>Control centre</h1>
          <p>
            Signed in as {me.displayName||me.email}.
            Live order monitoring refreshes automatically.
          </p>
        </div>

        <Pill tone="good">LIVE</Pill>
      </div>

      <div className="live-metrics">
        {metrics.map(m=>(
          <section
            key={m.label}
            className={`live-metric ${m.tone}`}
          >
            <span>{m.label}</span>
            <strong>{m.value}</strong>
          </section>
        ))}
      </div>

      <div className="monitor-grid">
        <section className="card">
          <div className="section-title">
            <div>
              <h2>Recent paid orders</h2>
              <p>Orders that now require fulfilment.</p>
            </div>
          </div>

          {recent.length===0 ? (
            <div className="empty">
              No paid orders yet.
            </div>
          ) : (
            <div className="recent-orders">
              {recent.map((r,i)=>(
                <div
                  key={txt(
                    get(r,"order_id","ORDER_ID"),
                    String(i),
                  )}
                >
                  <div>
                    <strong>
                      {txt(get(r,"order_id","ORDER_ID"))}
                    </strong>
                    <span>
                      {txt(
                        get(
                          r,
                          "contact_email",
                          "CONTACT_EMAIL",
                        ),
                        txt(get(r,"name","NAME"))
                      )}
                    </span>
                  </div>

                  <div className="recent-right">
                    <strong>
                      {money(
                        get(r,"order_value","ORDER_VALUE"),
                        txt(
                          get(
                            r,
                            "inv_currency",
                            "INV_CURRENCY",
                          ),
                          "GBP",
                        )
                      )}
                    </strong>
                    <small>
                      {txt(
                        get(
                          r,
                          "fulfilment_status",
                          "FULFILMENT_STATUS",
                        )
                      )}
                    </small>
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>

        <section className="card">
          <div className="section-title">
            <div>
              <h2>Exceptions</h2>
              <p>
                Orders DYNETIC thinks need attention.
              </p>
            </div>

            <Pill
              tone={
                exceptions.length ? "bad" : "good"
              }
            >
              {exceptions.length}
            </Pill>
          </div>

          {exceptions.length===0 ? (
            <div className="all-clear">
              <strong>All clear</strong>
              <span>
                No current payment or stock exceptions.
              </span>
            </div>
          ) : (
            <div className="exceptions">
              {exceptions.map((r,i)=>(
                <div key={i}>
                  <Pill tone="bad">
                    {txt(
                      get(
                        r,
                        "exception_type",
                        "EXCEPTION_TYPE",
                      )
                    )}
                  </Pill>
                  <strong>
                    {txt(get(r,"order_id","ORDER_ID"))}
                  </strong>
                  <span>
                    {txt(
                      get(
                        r,
                        "contact_email",
                        "CONTACT_EMAIL",
                      )
                    )}
                  </span>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>
    </>
  );
}

const buckets=[
  ["ALL","All"],
  ["PENDING_PAYMENT","Pending payment"],
  ["NEW_PAID","New paid"],
  ["PICKING","Picking"],
  ["READY","Ready"],
  ["DISPATCHED","Dispatched"],
  ["DELIVERED","Delivered"],
  ["CANCELLED","Cancelled"],
] as const;

export function MonitoredOrders({
  token,
  canCancel,
}:{
  token:Token;
  canCancel:boolean;
}){
  const[q,setQ]=useState("");
  const[bucket,setBucket]=useState("ALL");
  const[rows,setRows]=useState<Obj[]>([]);
  const[selected,setSelected]=useState<Obj|null>(null);
  const[error,setError]=useState<unknown>(null);
  const[loading,setLoading]=useState(true);
  const[nonce,setNonce]=useState(0);

  async function load(){
    try{
      const result=await api<Obj[]>(
        token,
        "/api/admin/monitoring/orders"+
        query({
          q:q||undefined,
          workflow:bucket,
          limit:300,
        }),
      );

      setRows(result);
      setError(null);
    }catch(e){
      setError(e);
    }finally{
      setLoading(false);
    }
  }

  useEffect(()=>{
    setLoading(true);
    void load();

    const timer=setInterval(()=>{
      void load();
    },20000);

    return()=>clearInterval(timer);
  },[token,q,bucket,nonce]);

  const counts=useMemo(()=>{
    const o:Record<string,number>={};

    rows.forEach(r=>{
      const k=txt(
        get(r,"workflow_bucket","WORKFLOW_BUCKET"),
        "UNKNOWN",
      );
      o[k]=(o[k]||0)+1;
    });

    return o;
  },[rows]);

  return (
    <>
      <div className="head">
        <div>
          <h1>Orders</h1>
          <p>
            Live operational queue.
            Refreshes every 20 seconds.
          </p>
        </div>

        <Btn
          kind="ghost"
          onClick={()=>setNonce(x=>x+1)}
        >
          Refresh
        </Btn>
      </div>

      <div className="workflow-tabs">
        {buckets.map(([code,label])=>(
          <button
            key={code}
            className={bucket===code ? "active" : ""}
            onClick={()=>setBucket(code)}
          >
            {label}
            {code!=="ALL" && counts[code]>0 && (
              <b>{counts[code]}</b>
            )}
          </button>
        ))}
      </div>

      <section className="card">
        <div className="toolbar">
          <input
            className="input search"
            value={q}
            onChange={e=>setQ(e.target.value)}
            placeholder="Search order, customer, postcode..."
          />
          <span>{rows.length} orders</span>
        </div>

        {error ? (
          <ErrorBox error={error}/>
        ) : loading ? (
          <Loader/>
        ) : (
          <div className="tablewrap">
            <table>
              <thead>
                <tr>
                  <th>Order</th>
                  <th>Customer</th>
                  <th>Workflow</th>
                  <th>Payment</th>
                  <th>Value</th>
                  <th>Delivery</th>
                </tr>
              </thead>

              <tbody>
                {rows.map((r,i)=>{
                  const id=txt(
                    get(r,"order_id","ORDER_ID"),
                    String(i),
                  );

                  const workflow=txt(
                    get(
                      r,
                      "workflow_bucket",
                      "WORKFLOW_BUCKET",
                    )
                  );

                  return (
                    <tr
                      className="click"
                      key={id}
                      onClick={()=>setSelected(r)}
                    >
                      <td>
                        <strong>{id}</strong>
                        <small>
                          {dt(
                            get(
                              r,
                              "order_date",
                              "ORDER_DATE",
                            )
                          )}
                        </small>
                      </td>

                      <td>
                        <strong>
                          {txt(get(r,"name","NAME"))}
                        </strong>
                        <small>
                          {txt(
                            get(
                              r,
                              "contact_email",
                              "CONTACT_EMAIL",
                            )
                          )}
                        </small>
                      </td>

                      <td>
                        <Pill
                          tone={
                            workflow==="NEW_PAID"
                              ? "good"
                              : workflow==="CANCELLED"
                                ? "bad"
                                : workflow==="PENDING_PAYMENT"
                                  ? "warn"
                                  : ""
                          }
                        >
                          {workflow.replaceAll("_"," ")}
                        </Pill>
                      </td>

                      <td>
                        {txt(
                          get(
                            r,
                            "payment_status",
                            "PAYMENT_STATUS",
                          )
                        )}
                      </td>

                      <td>
                        {money(
                          get(
                            r,
                            "order_value",
                            "ORDER_VALUE",
                          ),
                          txt(
                            get(
                              r,
                              "inv_currency",
                              "INV_CURRENCY",
                            ),
                            "GBP",
                          )
                        )}
                      </td>

                      <td>
                        <strong>
                          {txt(
                            get(
                              r,
                              "dispatch_method",
                              "DISPATCH_METHOD",
                            )
                          )}
                        </strong>
                        <small>
                          {txt(
                            get(r,"postcode","POSTCODE")
                          )}
                        </small>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {selected && (
        <OperationalOrderDetail
          token={token}
          summary={selected}
          canCancel={canCancel}
          onClose={()=>setSelected(null)}
          onChanged={()=>{
            setSelected(null);
            setNonce(x=>x+1);
          }}
        />
      )}
    </>
  );
}

function OperationalOrderDetail({
  token,
  summary,
  canCancel,
  onClose,
  onChanged,
}:{
  token:Token;
  summary:Obj;
  canCancel:boolean;
  onClose:()=>void;
  onChanged:()=>void;
}){
  const orderId=txt(
    get(summary,"order_id","ORDER_ID")
  );

  const[detail,setDetail]=useState<Obj|null>(null);
  const[timeline,setTimeline]=useState<Obj|null>(null);
  const[error,setError]=useState<unknown>(null);
  const[cancelOpen,setCancelOpen]=useState(false);

  useEffect(()=>{
    void Promise.all([
      api<Obj>(
        token,
        `/api/admin/orders/${encodeURIComponent(orderId)}`,
      ),
      api<Obj>(
        token,
        `/api/admin/orders/${encodeURIComponent(orderId)}/timeline`,
      ),
      api(
        token,
        `/api/admin/orders/${encodeURIComponent(orderId)}/acknowledge`,
        {method:"POST"},
      ),
    ])
      .then(([d,t])=>{
        setDetail(d);
        setTimeline(t);
      })
      .catch(setError);
  },[token,orderId]);

  if(error){
    return (
      <Modal title={`Order ${orderId}`} onClose={onClose}>
        <ErrorBox error={error}/>
      </Modal>
    );
  }

  if(!detail || !timeline){
    return (
      <Modal title={`Order ${orderId}`} onClose={onClose}>
        <Loader/>
      </Modal>
    );
  }

  const lines=(get(detail,"lines") as Obj[]) || [];
  const payments=(get(detail,"payments") as Obj[]) || [];
  const address=(get(
    detail,
    "delivery_address",
    "DELIVERY_ADDRESS",
  ) as Obj) || {};

  const events=(get(timeline,"events") as Obj[]) || [];
  const audits=(get(timeline,"audit") as Obj[]) || [];

  const fulfilment=txt(
    get(
      detail,
      "fulfilment_status",
      "FULFILMENT_STATUS",
    )
  );

  const payment=txt(
    get(
      detail,
      "payment_status",
      "PAYMENT_STATUS",
    )
  );

  const picked=lines.some(
    x=>num(get(x,"qty_picked","QTY_PICKED"))>0
  );

  const terminal=[
    "CANCELLED",
    "SHIPPED",
    "DELIVERED",
  ].includes(fulfilment);

  return (
    <Modal title={`Order ${orderId}`} onClose={onClose}>
      <div className="order-top">
        <div>
          <span>Value</span>
          <strong>
            {money(
              get(detail,"order_value","ORDER_VALUE"),
              txt(
                get(
                  detail,
                  "inv_currency",
                  "INV_CURRENCY",
                ),
                "GBP",
              )
            )}
          </strong>
        </div>

        <div>
          <span>Payment</span>
          <strong>{payment}</strong>
        </div>

        <div>
          <span>Fulfilment</span>
          <strong>{fulfilment}</strong>
        </div>

        <div>
          <span>Placed</span>
          <strong>
            {dt(get(detail,"order_date","ORDER_DATE"))}
          </strong>
        </div>
      </div>

      <div className="detail-grid">
        <section className="detail-card">
          <h3>Customer</h3>
          <strong>
            {txt(
              get(
                detail,
                "name",
                "NAME",
                "contact",
                "CONTACT",
              )
            )}
          </strong>
          <span>
            {txt(
              get(
                detail,
                "contact_email",
                "CONTACT_EMAIL",
              )
            )}
          </span>
          <span>
            {txt(
              get(
                detail,
                "contact_phone",
                "CONTACT_PHONE",
                "contact_mobile",
                "CONTACT_MOBILE",
              )
            )}
          </span>
        </section>

        <section className="detail-card">
          <h3>Delivery</h3>
          <strong>{txt(get(address,"name"))}</strong>
          <span>{txt(get(address,"address1"))}</span>
          {get(address,"address2") && (
            <span>{txt(get(address,"address2"))}</span>
          )}
          <span>
            {[
              txt(get(address,"town"),""),
              txt(get(address,"county"),""),
            ].filter(Boolean).join(", ")}
          </span>
          <span>{txt(get(address,"postcode"))}</span>
        </section>

        <section className="detail-card">
          <h3>Method</h3>
          <strong>
            {txt(
              get(
                detail,
                "dispatch_method",
                "DISPATCH_METHOD",
              )
            )}
          </strong>
          <span>
            {txt(
              get(
                detail,
                "carrier_id",
                "CARRIER_ID",
              )
            )}
          </span>
          <span>
            {txt(
              get(
                detail,
                "service_level",
                "SERVICE_LEVEL",
              )
            )}
          </span>
        </section>
      </div>

      <h3 className="detail-heading">Order lines</h3>

      <div className="order-lines">
        {lines.map((line,i)=>(
          <div key={i}>
            <div>
              <strong>
                {txt(
                  get(
                    line,
                    "product_name",
                    "PRODUCT_NAME",
                    "sku_id",
                    "SKU_ID",
                  )
                )}
              </strong>
              <span>
                {txt(get(line,"variant_name","VARIANT_NAME"))}
              </span>
              <small>
                {txt(get(line,"sku_id","SKU_ID"))}
              </small>
            </div>

            <div className="line-qty">
              <span>
                Qty {num(
                  get(line,"qty_ordered","QTY_ORDERED")
                )}
              </span>
              <strong>
                {money(
                  get(
                    line,
                    "extended_price",
                    "EXTENDED_PRICE",
                    "line_value",
                    "LINE_VALUE",
                  ),
                  txt(
                    get(
                      line,
                      "product_currency",
                      "PRODUCT_CURRENCY",
                    ),
                    "GBP",
                  )
                )}
              </strong>
            </div>
          </div>
        ))}
      </div>

      <h3 className="detail-heading">Timeline</h3>

      <div className="timeline">
        <div className="timeline-item">
          <i/>
          <div>
            <strong>Order created</strong>
            <span>
              {dt(get(detail,"order_date","ORDER_DATE"))}
            </span>
          </div>
        </div>

        {events.map((event,i)=>(
          <div className="timeline-item" key={i}>
            <i/>
            <div>
              <strong>
                {txt(get(event,"title","TITLE"))}
              </strong>
              <span>
                {txt(get(event,"message","MESSAGE"))}
              </span>
              <small>
                {dt(
                  get(
                    event,
                    "created_dstamp",
                    "CREATED_DSTAMP",
                  )
                )}
              </small>
            </div>
          </div>
        ))}

        {audits.map((event,i)=>(
          <div className="timeline-item audit" key={`a-${i}`}>
            <i/>
            <div>
              <strong>
                Admin {txt(get(event,"action","ACTION"))}
              </strong>
              <span>
                {txt(
                  get(event,"reason","REASON"),
                  "Administrative change",
                )}
              </span>
              <small>
                {txt(
                  get(
                    event,
                    "changed_by",
                    "CHANGED_BY",
                  )
                )} - {dt(
                  get(
                    event,
                    "created_dstamp",
                    "CREATED_DSTAMP",
                  )
                )}
              </small>
            </div>
          </div>
        ))}
      </div>

      {payments.length>0 && (
        <>
          <h3 className="detail-heading">Payments</h3>
          <div className="payment-list">
            {payments.map((p,i)=>(
              <div key={i}>
                <strong>
                  {txt(get(p,"provider","PROVIDER"))}
                </strong>
                <span>
                  {txt(get(p,"status","STATUS"))}
                </span>
                <span>
                  {money(
                    get(p,"amount","AMOUNT"),
                    "GBP",
                  )}
                </span>
              </div>
            ))}
          </div>
        </>
      )}

      <div className="dangerzone">
        <div>
          <strong>Cancel order</strong>
          <span>
            Open allocations are released.
            Picked or shipped orders are protected.
            Captured payments are not silently refunded.
          </span>
        </div>

        <Btn
          kind="danger"
          disabled={
            !canCancel ||
            terminal ||
            picked
          }
          onClick={()=>setCancelOpen(true)}
        >
          Cancel order
        </Btn>
      </div>

      {cancelOpen && (
        <CancelBox
          token={token}
          orderId={orderId}
          onClose={()=>setCancelOpen(false)}
          onDone={onChanged}
        />
      )}
    </Modal>
  );
}

function CancelBox({
  token,
  orderId,
  onClose,
  onDone,
}:{
  token:Token;
  orderId:string;
  onClose:()=>void;
  onDone:()=>void;
}){
  const[reason,setReason]=useState("CUSTOMER");
  const[notes,setNotes]=useState("");
  const[confirm,setConfirm]=useState("");
  const[saving,setSaving]=useState(false);
  const[error,setError]=useState<unknown>(null);

  async function cancel(){
    setSaving(true);
    setError(null);

    try{
      await api(
        token,
        `/api/admin/orders/${encodeURIComponent(orderId)}/cancel`,
        {
          method:"POST",
          body:JSON.stringify({
            reasonCode:reason,
            notes,
          }),
        },
      );

      onDone();
    }catch(e){
      setError(e);
    }finally{
      setSaving(false);
    }
  }

  return (
    <div className="nested-confirm">
      <h3>Confirm cancellation</h3>

      <p>
        Type the order ID before DYNETIC will cancel it.
      </p>

      <div className="form">
        <label>
          Reason
          <select
            className="input"
            value={reason}
            onChange={e=>setReason(e.target.value)}
          >
            <option>CUSTOMER</option>
            <option>STOCK</option>
            <option>DUPLICATE</option>
            <option>ERROR</option>
            <option>OTHER</option>
          </select>
        </label>

        <label>
          Notes
          <textarea
            className="input textarea"
            maxLength={400}
            value={notes}
            onChange={e=>setNotes(e.target.value)}
          />
        </label>

        <label>
          Type {orderId}
          <input
            className="input"
            value={confirm}
            onChange={e=>setConfirm(e.target.value)}
          />
        </label>

        {error ? <ErrorBox error={error}/> : null}

        <div className="actions">
          <Btn kind="ghost" onClick={onClose}>
            Keep order
          </Btn>

          <Btn
            kind="danger"
            disabled={
              saving ||
              confirm!==orderId
            }
            onClick={cancel}
          >
            {saving ? "Cancelling..." : "Cancel order"}
          </Btn>
        </div>
      </div>
    </div>
  );
}
