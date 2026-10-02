import {useEffect,useMemo,useState,type ReactNode} from "react";
import { newOperationId, refundableBalance, orderHref } from "./operational-0318";
import {ADMIN_CONFIG} from "./env";
import {EmptyState,ErrorState,LoadingState} from "./ui/states";
import {api,bool,dateInput,dt,get,items,loadReasons,money,num,query,txt,type HasPermission,type Obj,type Token} from "./admin-api";

export type Me = {
  adminUserId: string;
  email?: string | null;
  displayName?: string | null;
  roles: string[];
  permissions: string[];
  bootstrap: boolean;
};

function Button({children,onClick,disabled,kind="",title}:{children:ReactNode;onClick?:()=>void;disabled?:boolean;kind?:string;title?:string}){return <button className={`btn ${kind}`} onClick={onClick} disabled={disabled} title={title}>{children}</button>}
function Pill({children,tone=""}:{children:ReactNode;tone?:string}){return <span className={`pill ${tone}`}>{children}</span>}
function Card({children,wide=false}:{children:ReactNode;wide?:boolean}){return <section className={`card ${wide?"wide":""}`}>{children}</section>}
function Header({title,sub,action}:{title:string;sub?:string;action?:ReactNode}){return <div className="head"><div><h1>{title}</h1>{sub&&<p>{sub}</p>}</div>{action}</div>}
function Load(){return <LoadingState/>}
function ErrorBox({error}:{error:unknown}){return <ErrorState error={error} compact/>}
function Empty({children="Nothing to show."}:{children?:ReactNode}){return <EmptyState title={typeof children==="string"?children:"Nothing to show."}>{typeof children==="string"?null:children}</EmptyState>}
function Search({value,setValue,placeholder}:{value:string;setValue:(v:string)=>void;placeholder:string}){return <input className="input search" value={value} onChange={e=>setValue(e.target.value)} placeholder={placeholder}/>}
function Modal({title,onClose,children,wide=false}:{title:string;onClose:()=>void;children:ReactNode;wide?:boolean}){return <div className="shade" onMouseDown={e=>{if(e.target===e.currentTarget)onClose()}}><div className={`modal ${wide?"cp-modal-wide":""}`}><div className="modalhead"><h2>{title}</h2><Button kind="ghost" onClick={onClose}>Close</Button></div><div className="modalbody">{children}</div></div></div>}
function Table({rows,cols,keyOf,onClick}:{rows:Obj[];cols:{name:string;cell:(r:Obj)=>ReactNode}[];keyOf:(r:Obj,i:number)=>string;onClick?:(r:Obj)=>void}){return <div className="tablewrap"><table><thead><tr>{cols.map(c=><th key={c.name}>{c.name}</th>)}</tr></thead><tbody>{rows.map((r,i)=><tr key={keyOf(r,i)} className={onClick?"click":""} onClick={()=>onClick?.(r)}>{cols.map(c=><td key={c.name}>{c.cell(r)}</td>)}</tr>)}</tbody></table></div>}
function Field({label,children,help}:{label:string;children:ReactNode;help?:string}){return <label className="cp-field"><span>{label}</span>{children}{help&&<small>{help}</small>}</label>}
function ConfirmText({value,setValue,expected}:{value:string;setValue:(v:string)=>void;expected:string}){return <Field label={`Type ${expected} to confirm`}><input className="input" value={value} onChange={e=>setValue(e.target.value)} placeholder={expected}/></Field>}
function Metric({label,value,tone=""}:{label:string;value:ReactNode;tone?:string}){return <div className={`cp-metric ${tone}`}><span>{label}</span><strong>{value}</strong></div>}
function ReasonSelect({reasons,value,onChange}:{reasons:Obj[];value:string;onChange:(v:string)=>void}){return <select className="input" value={value} onChange={e=>onChange(e.target.value)}>{reasons.map((r,i)=><option key={txt(get(r,"reason_code","REASON_CODE"),String(i))} value={txt(get(r,"reason_code","REASON_CODE"))}>{txt(get(r,"description","DESCRIPTION", "reason_code","REASON_CODE"))}</option>)}</select>}
function toneForStatus(v:unknown){const s=txt(v,"").toUpperCase();if(["PAID","READY","SHIPPED","DELIVERED","COMPLETE","COMPLETED","RESOLVED","CLOSED","SUBMITTED","REQUEUED","ACTIVE"].includes(s))return"good";if(["FAILED","ERROR","CANCELLED","REJECTED"].includes(s))return"bad";if(["PENDING","OPEN","STARTED","PART_ALLOCATED","PART_REFUNDED","HOLD","AWAITING_CUSTOMER","REQUESTED"].includes(s))return"warn";return""}
function statusPill(v:unknown){const s=txt(v);return <Pill tone={toneForStatus(s)}>{s.replaceAll("_"," ")}</Pill>}

function urlParam(name:string){return new URLSearchParams(window.location.search).get(name)??""}
function entityHref(path:string,params:Record<string,string|undefined>){const q=new URLSearchParams();Object.entries(params).forEach(([k,v])=>{if(v)q.set(k,v)});const s=q.toString();return s?`${path}?${s}`:path}
function relatedOrderId(r:Obj){return txt(get(r,"order_id","ORDER_ID","reference_id","REFERENCE_ID"))}
function relatedCustomerKey(r:Obj){return txt(get(r,"customer_key","CUSTOMER_KEY","customer_id","CUSTOMER_ID","customer_email","CUSTOMER_EMAIL","recipient","RECIPIENT"))}
export function CustomersPage({token}:{token:Token}){  const initialCustomer=urlParam("customer");const[q,setQ]=useState(initialCustomer),[rows,setRows]=useState<Obj[]>([]),[selected,setSelected]=useState<Obj|null>(null),[detail,setDetail]=useState<Obj|null>(null),[loading,setLoading]=useState(false),[detailLoading,setDetailLoading]=useState(false),[error,setError]=useState<unknown>(null);  useEffect(()=>{const t=setTimeout(()=>{setLoading(true);setError(null);api<Obj[]>(token,"/api/admin/customers"+query({q:q||undefined,limit:200})).then(setRows).catch(setError).finally(()=>setLoading(false))},250);return()=>clearTimeout(t)},[q,token]);  useEffect(()=>{if(!selected){setDetail(null);return}const key=txt(get(selected,"customer_key","CUSTOMER_KEY","customer_id","CUSTOMER_ID","email","EMAIL"));if(!key)return;setDetailLoading(true);setError(null);api<Obj>(token,`/api/admin/customers/${encodeURIComponent(key)}`).then(setDetail).catch(setError).finally(()=>setDetailLoading(false))},[selected,token]);  useEffect(()=>{if(!initialCustomer||selected||rows.length===0)return;const wanted=initialCustomer.toLowerCase();const match=rows.find(r=>[get(r,"customer_key","CUSTOMER_KEY"),get(r,"customer_id","CUSTOMER_ID"),get(r,"email","EMAIL","contact_email","CONTACT_EMAIL")].some(v=>txt(v).toLowerCase()===wanted));if(match)setSelected(match)},[initialCustomer,rows,selected]);  const cols=[{name:"Customer",cell:(r:Obj)=><><strong>{txt(get(r,"customer_id","CUSTOMER_ID","customer_key","CUSTOMER_KEY"))}</strong><small>{txt(get(r,"email","EMAIL","contact_email","CONTACT_EMAIL"))}</small></>},{name:"Orders",cell:(r:Obj)=>num(get(r,"order_count","ORDER_COUNT","orders","ORDERS"))},{name:"Open",cell:(r:Obj)=>num(get(r,"open_order_count","OPEN_ORDER_COUNT","open_orders","OPEN_ORDERS"))},{name:"Total value",cell:(r:Obj)=>money(get(r,"order_value","ORDER_VALUE","total_value","TOTAL_VALUE"))},{name:"Latest",cell:(r:Obj)=>dt(get(r,"last_order_date","LAST_ORDER_DATE","latest_order","LATEST_ORDER"))}];  const detailOrders=items(get(detail??{},"orders","ORDERS"));  return <><Header title="Customers" sub="Customer support view backed by WMS order history, with direct links into operational orders."/><Card><div className="toolbar"><Search value={q} setValue={setQ} placeholder="Search customer ID or email..."/><span>{rows.length} customers</span></div>{error&&!selected?<ErrorBox error={error}/>:loading?<Load/>:rows.length===0?<Empty>{q?"No customers match this search.":"No customers found."}</Empty>:<Table rows={rows} cols={cols} keyOf={(r,i)=>txt(get(r,"customer_key","CUSTOMER_KEY","customer_id","CUSTOMER_ID","email","EMAIL"),String(i))} onClick={setSelected}/>}</Card>{selected&&<Modal title={`Customer ${txt(get(selected,"customer_id","CUSTOMER_ID","customer_key","CUSTOMER_KEY"))}`} onClose={()=>setSelected(null)} wide>{error?<ErrorBox error={error}/>:detailLoading||!detail?<Load/>:<><dl>{Object.entries(detail).filter(([k,v])=>!["orders","ORDERS"].includes(k)&&typeof v!=="object").map(([k,v])=><div key={k}><dt>{k.replaceAll("_"," ")}</dt><dd>{txt(v)}</dd></div>)}</dl><h3>Orders</h3>{detailOrders.length?<Table rows={detailOrders} cols={[{name:"Order",cell:r=>{const id=txt(get(r,"order_id","ORDER_ID"));return <a href={orderHref(id)}>{id}</a>}},{name:"Payment",cell:r=>statusPill(get(r,"payment_status","PAYMENT_STATUS"))},{name:"Fulfilment",cell:r=>statusPill(get(r,"fulfilment_status","FULFILMENT_STATUS"))},{name:"Value",cell:r=>money(get(r,"order_value","ORDER_VALUE"))},{name:"Created",cell:r=>dt(get(r,"created_dstamp","CREATED_DSTAMP","order_date","ORDER_DATE"))}]} keyOf={(r,i)=>txt(get(r,"order_id","ORDER_ID"),String(i))}/>:<Empty>No orders found for this customer.</Empty>}</>}</Modal>}</>;}

function MiniJsonRows({rows}:{rows:Obj[]}){if(!rows.length)return <Empty/>;return <div className="cp-stack">{rows.slice(0,12).map((r,i)=><div className="cp-mini" key={i}>{Object.entries(r).slice(0,5).map(([k,v])=><span key={k}><b>{k.replaceAll("_"," ")}</b>{typeof v==="object"?JSON.stringify(v):txt(v)}</span>)}</div>)}</div>}
export function OrderNoteModal({token,orderId,onClose,onDone}:{token:Token;orderId:string;onClose:()=>void;onDone:()=>void}){const[type,setType]=useState("INTERNAL"),[text,setText]=useState(""),[important,setImportant]=useState(false),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);async function save(){setSaving(true);try{await api(token,`/api/admin/orders/${encodeURIComponent(orderId)}/notes`,{method:"POST",body:JSON.stringify({type,text,important})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title="Add order note" onClose={onClose}><div className="form"><Field label="Type"><select className="input" value={type} onChange={e=>setType(e.target.value)}><option>INTERNAL</option><option>CUSTOMER</option><option>FULFILMENT</option></select></Field><Field label="Note"><textarea className="input textarea" value={text} onChange={e=>setText(e.target.value)} maxLength={2000}/></Field><label className="check"><input type="checkbox" checked={important} onChange={e=>setImportant(e.target.checked)}/> Important</label>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||text.trim().length<2} onClick={()=>void save()}>{saving?"Saving...":"Add note"}</Button></div></div></Modal>}
export function OrderCancelModal({token,orderId,refundRecommended,onClose,onDone}:{token:Token;orderId:string;refundRecommended:boolean;onClose:()=>void;onDone:()=>void}){const[reasons,setReasons]=useState<Obj[]>([]),[reason,setReason]=useState(""),[notes,setNotes]=useState(""),[confirm,setConfirm]=useState(""),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);useEffect(()=>{loadReasons(token,"ORDER_CANCEL").then(r=>{setReasons(r);setReason(txt(get(r[0],"reason_code","REASON_CODE"),""))}).catch(setError)},[token]);async function save(){setSaving(true);try{await api(token,`/api/admin/orders/${encodeURIComponent(orderId)}/cancel`,{method:"POST",body:JSON.stringify({reasonCode:reason,notes})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title="Cancel order" onClose={onClose}><div className="form">{refundRecommended&&<div className="warningbox"><strong>Payment captured</strong><br/>Cancellation does not silently refund money. Complete any required refund separately in Payments.</div>}<Field label="Reason"><ReasonSelect reasons={reasons} value={reason} onChange={setReason}/></Field><Field label="Notes"><textarea className="input textarea" value={notes} onChange={e=>setNotes(e.target.value)} maxLength={1000}/></Field><ConfirmText value={confirm} setValue={setConfirm} expected={orderId}/>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Keep order</Button><Button kind="danger" disabled={saving||confirm!==orderId||!reason} onClick={()=>void save()}>{saving?"Cancelling...":"Cancel order"}</Button></div></div></Modal>}
export function OrderAmendModal({token,order,onClose,onDone}:{token:Token;order:Obj;onClose:()=>void;onDone:()=>void}){const orderId=txt(get(order,"order_id","ORDER_ID"));const[reason,setReason]=useState(""),[priority,setPriority]=useState(txt(get(order,"priority","PRIORITY"),"")),[contact,setContact]=useState(txt(get(order,"contact","CONTACT"),"")),[phone,setPhone]=useState(txt(get(order,"contact_phone","CONTACT_PHONE"),"")),[email,setEmail]=useState(txt(get(order,"contact_email","CONTACT_EMAIL"),"")),[name,setName]=useState(txt(get(order,"name","NAME"),"")),[address1,setAddress1]=useState(txt(get(order,"address1","ADDRESS1"),"")),[address2,setAddress2]=useState(txt(get(order,"address2","ADDRESS2"),"")),[town,setTown]=useState(txt(get(order,"town","TOWN"),"")),[county,setCounty]=useState(txt(get(order,"county","COUNTY"),"")),[postcode,setPostcode]=useState(txt(get(order,"postcode","POSTCODE"),"")),[country,setCountry]=useState(txt(get(order,"country","COUNTRY"),"")),[instructions,setInstructions]=useState(txt(get(order,"instructions","INSTRUCTIONS"),"")),[packingNotes,setPackingNotes]=useState(txt(get(order,"packing_notes","PACKING_NOTES"),"")),[shipBy,setShipBy]=useState(dateInput(get(order,"ship_by_date","SHIP_BY_DATE"))),[deliverBy,setDeliverBy]=useState(dateInput(get(order,"deliver_by_date","DELIVER_BY_DATE"))),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);async function save(){setSaving(true);try{const patch:Obj={priority:priority===""?undefined:Number(priority),contact,contactPhone:phone,contactEmail:email,name,address1,address2,town,county,postcode,country,instructions,packingNotes,shipByDate:shipBy||undefined,deliverByDate:deliverBy||undefined};await api(token,`/api/admin/orders/${encodeURIComponent(orderId)}`,{method:"PATCH",body:JSON.stringify({reason,patch})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title="Amend order header" onClose={onClose} wide><div className="form cp-form-grid"><Field label="Reason"><input className="input" value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why is this order being changed?"/></Field><Field label="Priority"><input className="input" type="number" value={priority} onChange={e=>setPriority(e.target.value)}/></Field><Field label="Contact"><input className="input" value={contact} onChange={e=>setContact(e.target.value)}/></Field><Field label="Phone"><input className="input" value={phone} onChange={e=>setPhone(e.target.value)}/></Field><Field label="Email"><input className="input" value={email} onChange={e=>setEmail(e.target.value)}/></Field><Field label="Name"><input className="input" value={name} onChange={e=>setName(e.target.value)}/></Field><Field label="Address 1"><input className="input" value={address1} onChange={e=>setAddress1(e.target.value)}/></Field><Field label="Address 2"><input className="input" value={address2} onChange={e=>setAddress2(e.target.value)}/></Field><Field label="Town"><input className="input" value={town} onChange={e=>setTown(e.target.value)}/></Field><Field label="County"><input className="input" value={county} onChange={e=>setCounty(e.target.value)}/></Field><Field label="Postcode"><input className="input" value={postcode} onChange={e=>setPostcode(e.target.value)}/></Field><Field label="Country"><input className="input" value={country} onChange={e=>setCountry(e.target.value)}/></Field><Field label="Ship by"><input className="input" type="datetime-local" value={shipBy} onChange={e=>setShipBy(e.target.value)}/></Field><Field label="Deliver by"><input className="input" type="datetime-local" value={deliverBy} onChange={e=>setDeliverBy(e.target.value)}/></Field><Field label="Instructions"><textarea className="input textarea" value={instructions} onChange={e=>setInstructions(e.target.value)}/></Field><Field label="Packing notes"><textarea className="input textarea" value={packingNotes} onChange={e=>setPackingNotes(e.target.value)}/></Field></div>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||reason.trim().length<2} onClick={()=>void save()}>{saving?"Saving...":"Save amendment"}</Button></div></Modal>}

export function PaymentsPage({token,has}:{token:Token;has:HasPermission}){const[q,setQ]=useState(()=>urlParam("q")),[status,setStatus]=useState(""),[rows,setRows]=useState<Obj[]>([]),[selected,setSelected]=useState<Obj|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState<unknown>(null),[nonce,setNonce]=useState(0);useEffect(()=>{let live=true;setLoading(true);api<Obj[]>(token,"/api/admin/payments"+query({q:q||undefined,status:status||undefined,limit:250})).then(x=>live&&setRows(x)).catch(e=>live&&setError(e)).finally(()=>live&&setLoading(false));return()=>{live=false}},[token,q,status,nonce]);const cols=[{name:"Payment",cell:(r:Obj)=><><strong>{txt(get(r,"payment_id","PAYMENT_ID"))}</strong><small>{txt(get(r,"provider","PROVIDER"))} · {txt(get(r,"provider_reference","PROVIDER_REFERENCE"))}</small></>},{name:"Order",cell:(r:Obj)=>{const id=txt(get(r,"reference_id","REFERENCE_ID"));return id?<a href={orderHref(id)}>{id}</a>:"-"}},{name:"Status",cell:(r:Obj)=>statusPill(get(r,"status","STATUS"))},{name:"Captured",cell:(r:Obj)=>money(get(r,"captured_amount","CAPTURED_AMOUNT"),txt(get(r,"currency","CURRENCY"),"GBP"))},{name:"Refunded",cell:(r:Obj)=>money(get(r,"refunded_amount","REFUNDED_AMOUNT"),txt(get(r,"currency","CURRENCY"),"GBP"))},{name:"Refundable",cell:(r:Obj)=>money(get(r,"refundable_amount","REFUNDABLE_AMOUNT"),txt(get(r,"currency","CURRENCY"),"GBP"))},{name:"When",cell:(r:Obj)=>dt(get(r,"created_dstamp","CREATED_DSTAMP"))}];return <><Header title="Payments" sub="Stripe payment evidence and guarded full/partial refunds. Refund requests are recorded internally before provider submission." action={<Button kind="ghost" onClick={()=>setNonce(x=>x+1)}>Refresh</Button>}/><Card><div className="toolbar cp-filters"><Search value={q} setValue={setQ} placeholder="Search payment, order or Stripe reference..."/><select className="input cp-filter" value={status} onChange={e=>setStatus(e.target.value)}><option value="">All statuses</option><option>PAID</option><option>AUTHORISED</option><option>PENDING</option><option>PART_REFUNDED</option><option>REFUNDED</option><option>FAILED</option></select><span>{rows.length} payments</span></div>{error?<ErrorBox error={error}/>:loading?<Load/>:<Table rows={rows} cols={cols} keyOf={(r,i)=>txt(get(r,"payment_id","PAYMENT_ID"),String(i))} onClick={setSelected}/>}</Card>{selected&&<PaymentModal token={token} payment={selected} canRefund={has("payment.refund")} onClose={()=>setSelected(null)} onChanged={()=>{setSelected(null);setNonce(x=>x+1)}}/>}</>}
function PaymentModal({token,payment,canRefund,onClose,onChanged}:{token:Token;payment:Obj;canRefund:boolean;onClose:()=>void;onChanged:()=>void}){const paymentId=txt(get(payment,"payment_id","PAYMENT_ID"));const refundable=refundableBalance(payment);const[refund,setRefund]=useState(false);return <Modal title={`Payment ${paymentId}`} onClose={onClose}><dl>{Object.entries(payment).map(([k,v])=><div key={k}><dt>{k.replaceAll("_"," ")}</dt><dd>{typeof v==="object"?JSON.stringify(v):txt(v)}</dd></div>)}</dl><div className="dangerzone"><div><strong>Refund</strong><span>Maximum currently refundable: {money(refundable,txt(get(payment,"currency","CURRENCY"),"GBP"))}.</span></div><Button kind="danger" disabled={!canRefund||refundable<=0} onClick={()=>setRefund(true)}>Refund payment</Button></div>{refund&&<RefundModal token={token} payment={payment} onClose={()=>setRefund(false)} onDone={onChanged}/>}</Modal>}
function RefundModal({token,payment,onClose,onDone}:{token:Token;payment:Obj;onClose:()=>void;onDone:()=>void}){const[operationId]=useState(()=>newOperationId("refund"));const paymentId=txt(get(payment,"payment_id","PAYMENT_ID")),currency=txt(get(payment,"currency","CURRENCY"),"GBP"),max=refundableBalance(payment);const[reasons,setReasons]=useState<Obj[]>([]),[reason,setReason]=useState(""),[amount,setAmount]=useState(String(max)),[notes,setNotes]=useState(""),[confirm,setConfirm]=useState(""),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);useEffect(()=>{loadReasons(token,"REFUND").then(r=>{setReasons(r);setReason(txt(get(r[0],"reason_code","REASON_CODE"),""))}).catch(setError)},[token]);async function save(){setSaving(true);try{await api(token,`/api/admin/payments/${paymentId}/refund`,{method:"POST",body:JSON.stringify({amount:Number(amount),reasonCode:reason,notes,operationId})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <div className="nested-confirm"><h3>Refund payment</h3><div className="form"><Field label={`Amount (${currency})`}><input className="input" type="number" min="0.01" max={max} step="0.01" value={amount} onChange={e=>setAmount(e.target.value)}/></Field><Field label="Reason"><ReasonSelect reasons={reasons} value={reason} onChange={setReason}/></Field><Field label="Notes"><textarea className="input textarea" value={notes} onChange={e=>setNotes(e.target.value)}/></Field><ConfirmText value={confirm} setValue={setConfirm} expected={paymentId}/>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button kind="danger" disabled={saving||confirm!==paymentId||!reason||Number(amount)<=0||Number(amount)>max} onClick={()=>void save()}>{saving?"Submitting...":`Refund ${money(Number(amount)||0,currency)}`}</Button></div></div></div>}

export function ReturnsPage({token,has}:{token:Token;has:HasPermission}){
  const[rows,setRows]=useState<Obj[]>([]);
  const[status,setStatus]=useState("");
  const[orderId,setOrderId]=useState("");
  const[selected,setSelected]=useState<Obj|null>(null);
  const[creating,setCreating]=useState(false);
  const[createOrder,setCreateOrder]=useState<Obj|null>(null);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState<unknown>(null);
  const[nonce,setNonce]=useState(0);
  const[orderSearch,setOrderSearch]=useState("");
  const[orderMatches,setOrderMatches]=useState<Obj[]>([]);
  const[orderSearching,setOrderSearching]=useState(false);

  useEffect(()=>{
    let live=true;
    setLoading(true);
    setError(null);
    api<Obj[]>(token,"/api/admin/returns"+query({status:status||undefined,orderId:orderId||undefined,limit:250}))
      .then(x=>live&&setRows(x))
      .catch(e=>live&&setError(e))
      .finally(()=>live&&setLoading(false));
    return()=>{live=false};
  },[token,status,orderId,nonce]);

  useEffect(()=>{
    const q=orderSearch.trim();
    if(q.length<2){setOrderMatches([]);setOrderSearching(false);return;}
    const timer=window.setTimeout(()=>{
      setOrderSearching(true);
      setError(null);
      api(token,`/api/admin/orders?q=${encodeURIComponent(q)}&limit=20`)
        .then(r=>setOrderMatches(items(r)))
        .catch(setError)
        .finally(()=>setOrderSearching(false));
    },250);
    return()=>window.clearTimeout(timer);
  },[token,orderSearch]);

  const openCreate=(order:Obj|null)=>{
    setCreateOrder(order);
    setCreating(true);
  };

  const cols=[
    {name:"Case",cell:(r:Obj)=><><strong>{txt(get(r,"case_number","CASE_NUMBER"))}</strong><small>{txt(get(r,"return_case_id","RETURN_CASE_ID"))}</small></>},
    {name:"Order",cell:(r:Obj)=>{const id=txt(get(r,"order_id","ORDER_ID"));return id?<a href={orderHref(id)}>{id}</a>:"-"}},
    {name:"Type",cell:(r:Obj)=>txt(get(r,"case_type","CASE_TYPE"))},
    {name:"Status",cell:(r:Obj)=>statusPill(get(r,"status","STATUS"))},
    {name:"Requested",cell:(r:Obj)=>money(get(r,"refund_requested","REFUND_REQUESTED"))},
    {name:"Approved",cell:(r:Obj)=>money(get(r,"refund_approved","REFUND_APPROVED"))},
    {name:"Created",cell:(r:Obj)=>dt(get(r,"created_dstamp","CREATED_DSTAMP"))}
  ];

  return <>
    <Header
      title="Returns & claims"
      sub="Find the outbound order first, create the return or claim, then track the case through resolution."
      action={has("return.create")?<Button onClick={()=>openCreate(null)}>New case</Button>:undefined}
    />

    {has("return.create")?<Card>
      <h2>Find outbound order</h2>
      <p className="cp-muted">Search the existing outbound order before opening a return or claim.</p>
      <div className="toolbar cp-filters">
        <input
          className="input cp-filter"
          value={orderSearch}
          onChange={e=>setOrderSearch(e.target.value)}
          placeholder="Order ID, customer ID or email"
        />
        <span>{orderSearching?"Searching...":orderMatches.length?`${orderMatches.length} matching orders`:""}</span>
      </div>

      {orderMatches.length>0?<div className="tablewrap">
        <table>
          <thead><tr><th>Order</th><th>Customer</th><th>Payment</th><th>Fulfilment</th><th/></tr></thead>
          <tbody>{orderMatches.map((o,i)=>{
            const id=txt(get(o,"order_id","ORDER_ID"),String(i));
            const customer=txt(get(o,"customer_name","CUSTOMER_NAME","customer_id","CUSTOMER_ID","contact_email","CONTACT_EMAIL","customer_email","CUSTOMER_EMAIL"),"-");
            const payment=txt(get(o,"payment_status","PAYMENT_STATUS"),"-");
            const fulfilment=txt(get(o,"fulfilment_status","FULFILMENT_STATUS","status","STATUS"),"-");
            return <tr key={id}>
              <td><a href={orderHref(id)}>{id}</a></td>
              <td>{customer}</td>
              <td>{statusPill(payment)}</td>
              <td>{statusPill(fulfilment)}</td>
              <td><Button onClick={()=>openCreate(o)}>Create return / claim</Button></td>
            </tr>;
          })}</tbody>
        </table>
      </div>:orderSearch.trim().length>=2&&!orderSearching?<Empty>No matching outbound orders.</Empty>:null}
    </Card>:null}

    <Card>
      <h2>Existing cases</h2>
      <div className="toolbar cp-filters">
        <input className="input cp-filter" value={orderId} onChange={e=>setOrderId(e.target.value)} placeholder="Order ID"/>
        <select className="input cp-filter" value={status} onChange={e=>setStatus(e.target.value)}>
          <option value="">All statuses</option>
          <option>OPEN</option>
          <option>INVESTIGATING</option><option>AWAITING_CUSTOMER</option><option>APPROVED</option>
          <option>RESOLVED</option>
          <option>CLOSED</option>
          <option>REJECTED</option>
        </select>
        <span>{rows.length} cases</span>
      </div>
      {error?<ErrorBox error={error}/>:loading?<Load/>:<Table rows={rows} cols={cols} keyOf={(r,i)=>txt(get(r,"return_case_id","RETURN_CASE_ID"),String(i))} onClick={setSelected}/ >}
    </Card>

    {creating&&<CreateReturnModal
      token={token}
      initialOrder={createOrder}
      onClose={()=>{setCreating(false);setCreateOrder(null)}}
      onDone={()=>{setCreating(false);setCreateOrder(null);setNonce(x=>x+1)}}
    />}

    {selected&&<ManageReturnModal
      token={token}
      item={selected}
      canManage={has("return.manage")}
      onClose={()=>setSelected(null)}
      onDone={()=>{setSelected(null);setNonce(x=>x+1)}}
    />}
  </>;
}
function CreateReturnModal({token,initialOrder,onClose,onDone}:{token:Token;initialOrder?:Obj|null;onClose:()=>void;onDone:()=>void}){
  const[operationId]=useState(()=>newOperationId("return"));
  const[reasons,setReasons]=useState<Obj[]>([]);
  const[orderQuery,setOrderQuery]=useState(()=>txt(initialOrder&&get(initialOrder,"order_id","ORDER_ID"),""));
  const[orders,setOrders]=useState<Obj[]>([]);
  const[selectedOrder,setSelectedOrder]=useState<Obj|null>(initialOrder??null);
  const[orderLines,setOrderLines]=useState<Obj[]>([]);
  const[lineQty,setLineQty]=useState<Record<string,string>>({});
  const[searching,setSearching]=useState(false);
  const[loadingOrder,setLoadingOrder]=useState(false);
  const[caseType,setCaseType]=useState("DOA");
  const[reason,setReason]=useState("");
  const[expectedResolution,setExpectedResolution]=useState("");
  const[customerMessage,setCustomerMessage]=useState("");
  const[internalNotes,setInternalNotes]=useState("");
  const[refund,setRefund]=useState("0");
  const[error,setError]=useState<unknown>(null);
  const[saving,setSaving]=useState(false);

  useEffect(()=>{
    loadReasons(token,"RETURN")
      .then(r=>{
        setReasons(r);
        setReason(txt(get(r[0],"reason_code","REASON_CODE"),""));
      })
      .catch(setError);
  },[token]);

  useEffect(()=>{
    const q=orderQuery.trim();
    const selectedId=txt(selectedOrder&&get(selectedOrder,"order_id","ORDER_ID"),"");

    if(q.length<2||selectedId===q){
      setOrders([]);
      setSearching(false);
      return;
    }

    const timer=window.setTimeout(()=>{
      setSearching(true);
      api(token,`/api/admin/orders?q=${encodeURIComponent(q)}&limit=20`)
        .then(r=>setOrders(items(r)))
        .catch(setError)
        .finally(()=>setSearching(false));
    },250);

    return()=>window.clearTimeout(timer);
  },[token,orderQuery,selectedOrder]);

  const selectedOrderId=txt(selectedOrder&&get(selectedOrder,"order_id","ORDER_ID"),"");

  useEffect(()=>{
    if(!selectedOrderId){
      setOrderLines([]);
      setLineQty({});
      return;
    }

    let live=true;
    setLoadingOrder(true);
    setError(null);
    setLineQty({});

    api<Obj>(token,`/api/admin/orders/${encodeURIComponent(selectedOrderId)}`)
      .then(detail=>{
        if(!live)return;
        setOrderLines((get(detail,"lines","LINES") as Obj[])||[]);
      })
      .catch(e=>live&&setError(e))
      .finally(()=>live&&setLoadingOrder(false));

    return()=>{live=false};
  },[token,selectedOrderId]);

  const selectedLines=orderLines.map(line=>{
    const lineId=Number(get(line,"line_id","LINE_ID"));
    const key=String(lineId);
    const qty=Number(lineQty[key]??0);
    const ordered=num(get(line,"qty_ordered","QTY_ORDERED"));

    return {
      line,
      lineId,
      qty,
      ordered,
      issueType:caseType,
      resolution:expectedResolution||undefined
    };
  }).filter(x=>Number.isFinite(x.qty)&&x.qty>0);

  const invalidQty=selectedLines.some(x=>x.qty>x.ordered);

  async function save(){
    if(!selectedOrderId||!selectedLines.length||invalidQty)return;

    setSaving(true);
    setError(null);

    try{
      await api(token,"/api/admin/returns",{
        method:"POST",
        body:JSON.stringify({
          orderId:selectedOrderId,
          caseType,
          reasonCode:reason||undefined,
          customerMessage,
          internalNotes,
          refundRequested:Number(refund)||0,
          operationId,
          lines:selectedLines.map(x=>({
            lineId:x.lineId,
            qty:x.qty,
            issueType:x.issueType,
            resolution:x.resolution
          }))
        })
      });

      onDone();
    }catch(e){
      setError(e);
    }finally{
      setSaving(false);
    }
  }

  return <Modal title="New return / claim" onClose={onClose} wide>
    <div className="form">
      <Field label="Find outbound order">
        <input
          className="input"
          value={orderQuery}
          onChange={e=>{
            setOrderQuery(e.target.value);
            setSelectedOrder(null);
          }}
          placeholder="Order ID, customer ID or email"
        />
      </Field>

      {searching?<small>Searching orders...</small>:null}

      {!selectedOrder&&orders.length>0?<div className="card" style={{maxHeight:220,overflow:"auto"}}>
        {orders.map((o,i)=>{
          const id=txt(get(o,"order_id","ORDER_ID"));
          const customer=txt(get(o,"customer_name","CUSTOMER_NAME","customer_id","CUSTOMER_ID","customer_email","CUSTOMER_EMAIL","contact_email","CONTACT_EMAIL"),"-");
          const payment=txt(get(o,"payment_status","PAYMENT_STATUS"),"-");
          const fulfilment=txt(get(o,"fulfilment_status","FULFILMENT_STATUS","status","STATUS"),"-");

          return <button
            key={id||String(i)}
            type="button"
            className="btn btn-ghost"
            style={{display:"block",width:"100%",textAlign:"left",marginBottom:4}}
            onClick={()=>{
              setSelectedOrder(o);
              setOrderQuery(id);
            }}
          >
            <strong>{id}</strong> - {customer} - {payment} - {fulfilment}
          </button>;
        })}
      </div>:null}

      {selectedOrder?<div className="card">
        <strong>Selected order: <a href={orderHref(selectedOrderId)}>{selectedOrderId}</a></strong>
        <br/>
        <small>
          {txt(get(selectedOrder,"customer_name","CUSTOMER_NAME","customer_id","CUSTOMER_ID","customer_email","CUSTOMER_EMAIL","contact_email","CONTACT_EMAIL"),"Customer details unavailable")}
          {" - Payment: "}{txt(get(selectedOrder,"payment_status","PAYMENT_STATUS"),"-")}
          {" - Fulfilment: "}{txt(get(selectedOrder,"fulfilment_status","FULFILMENT_STATUS","status","STATUS"),"-")}
        </small>
      </div>:null}

      {loadingOrder?<Load/>:selectedOrder&&orderLines.length===0?<Empty>No order lines found.</Empty>:null}

      {orderLines.length>0?<div>
        <h3>Choose items and quantities</h3>
        <div className="tablewrap">
          <table>
            <thead>
              <tr><th>Line</th><th>SKU</th><th>Ordered</th><th>Return / claim qty</th></tr>
            </thead>
            <tbody>{orderLines.map((line,i)=>{
              const lineId=txt(get(line,"line_id","LINE_ID"),String(i));
              const sku=txt(get(line,"sku_id","SKU_ID"),"-");
              const ordered=num(get(line,"qty_ordered","QTY_ORDERED"));
              const value=lineQty[lineId]??"0";
              const qty=Number(value);
              const invalid=Number.isFinite(qty)&&qty>ordered;

              return <tr key={lineId}>
                <td>{lineId}</td>
                <td><strong>{sku}</strong></td>
                <td>{ordered}</td>
                <td>
                  <input
                    className="input"
                    type="number"
                    min="0"
                    max={ordered}
                    step="1"
                    aria-label={`Qty for ${sku}`}
                    value={value}
                    onChange={e=>setLineQty(q=>({...q,[lineId]:e.target.value}))}
                  />
                  {invalid?<small>Cannot exceed ordered quantity.</small>:null}
                </td>
              </tr>;
            })}</tbody>
          </table>
        </div>
      </div>:null}

      <Field label="Case type">
        <select className="input" value={caseType} onChange={e=>setCaseType(e.target.value)}>
          <option>DOA</option>
          <option>DAMAGED</option>
          <option>WRONG_ITEM</option>
          <option>CUSTOMER_RETURN</option>
        </select>
      </Field>

      <Field label="Reason">
        <ReasonSelect reasons={reasons} value={reason} onChange={setReason}/>
      </Field>

      <Field label="Expected resolution" help="Optional expected outcome recorded against the selected return lines.">
        <input className="input" aria-label="Expected resolution" maxLength={40} value={expectedResolution}
          onChange={e=>setExpectedResolution(e.target.value)}
          placeholder="Refund, replacement, investigate..."
        />
      </Field>

      <Field label="Customer message">
        <textarea className="input textarea" value={customerMessage} onChange={e=>setCustomerMessage(e.target.value)}/>
      </Field>

      <Field label="Internal notes">
        <textarea className="input textarea" value={internalNotes} onChange={e=>setInternalNotes(e.target.value)}/>
      </Field>

      <Field label="Refund requested">
        <input className="input" type="number" step="0.01" min="0" value={refund} onChange={e=>setRefund(e.target.value)}/>
      </Field>

      {selectedOrder&&orderLines.length>0&&selectedLines.length===0?<small>Select at least one item by entering a quantity above zero.</small>:null}

      {error?<ErrorBox error={error}/>:null}

      <div className="actions">
        <Button kind="ghost" onClick={onClose}>Cancel</Button>
        <Button
          disabled={saving||!selectedOrder||!caseType||!selectedLines.length||invalidQty}
          onClick={()=>void save()}
        >
          {saving?"Creating...":"Create case"}
        </Button>
      </div>
    </div>
  </Modal>;
}
function ManageReturnModal({token,item,canManage,onClose,onDone}:{token:Token;item:Obj;canManage:boolean;onClose:()=>void;onDone:()=>void}){
  const id=txt(get(item,"return_case_id","RETURN_CASE_ID"));
  const[detail,setDetail]=useState<Obj|null>(null);
  const[detailLoading,setDetailLoading]=useState(true);
  const[status,setStatus]=useState(txt(get(item,"status","STATUS"),"OPEN"));
  const[resolution,setResolution]=useState(txt(get(item,"resolution","RESOLUTION"),""));
  const[assignedTo,setAssignedTo]=useState(txt(get(item,"assigned_to","ASSIGNED_TO"),""));
  const[notes,setNotes]=useState(txt(get(item,"internal_notes","INTERNAL_NOTES"),""));
  const[approved,setApproved]=useState(txt(get(item,"refund_approved","REFUND_APPROVED"),""));
  const[replacement,setReplacement]=useState(txt(get(item,"replacement_order_id","REPLACEMENT_ORDER_ID"),""));
  const[error,setError]=useState<unknown>(null);
  const[saving,setSaving]=useState(false);

  useEffect(()=>{
    let live=true;
    setDetailLoading(true);

    api<Obj>(token,`/api/admin/returns/${encodeURIComponent(id)}`)
      .then(x=>live&&setDetail(x))
      .catch(e=>live&&setError(e))
      .finally(()=>live&&setDetailLoading(false));

    return()=>{live=false};
  },[token,id]);

  const current=(get(detail??{},"case","CASE") as Obj)||item;
  const lines=(get(detail??{},"lines","LINES") as Obj[])||[];

  async function save(){
    setSaving(true);
    setError(null);

    try{
      await api(token,`/api/admin/returns/${id}`,{
        method:"PATCH",
        body:JSON.stringify({
          status,
          resolution:resolution||undefined,
          assignedTo:assignedTo||undefined,
          internalNotes:notes||undefined,
          refundApproved:approved===""?undefined:Number(approved),
          replacementOrderId:replacement||undefined
        })
      });

      onDone();
    }catch(e){
      setError(e);
    }finally{
      setSaving(false);
    }
  }

  return <Modal title={`Return ${txt(get(current,"case_number","CASE_NUMBER"),id)}`} onClose={onClose} wide>
    <dl>
      {Object.entries(current)
        .filter(([k])=>!["internal_notes","INTERNAL_NOTES","resolution","RESOLUTION","status","STATUS"].includes(k))
        .map(([k,v])=><div key={k}><dt>{k.replaceAll("_"," ")}</dt><dd>{txt(v)}</dd></div>)}
    </dl>

    <h3 className="detail-heading">Items</h3>

    {detailLoading?<Load/>:lines.length?<div className="tablewrap">
      <table>
        <thead><tr><th>Line</th><th>SKU</th><th>Qty</th><th>Issue</th><th>Expected resolution</th></tr></thead>
        <tbody>{lines.map((line,i)=><tr key={txt(get(line,"return_case_line_id","RETURN_CASE_LINE_ID"),String(i))}>
          <td>{txt(get(line,"line_id","LINE_ID"),"-")}</td>
          <td>{txt(get(line,"sku_id","SKU_ID"),"-")}</td>
          <td>{txt(get(line,"qty","QTY"),"-")}</td>
          <td>{txt(get(line,"issue_type","ISSUE_TYPE"),"-")}</td>
          <td>{txt(get(line,"resolution","RESOLUTION"),"-")}</td>
        </tr>)}</tbody>
      </table>
    </div>:<Empty>No item-level lines are recorded for this case.</Empty>}

    {canManage?<div className="form cp-top-gap">
      <Field label="Status">
        <select className="input" value={status} onChange={e=>setStatus(e.target.value)}>
          <option>OPEN</option>
          <option>INVESTIGATING</option>
          <option>AWAITING_CUSTOMER</option>
          <option>APPROVED</option>
          <option>RESOLVED</option>
          <option>CLOSED</option>
          <option>REJECTED</option>
        </select>
      </Field>

      <Field label="Resolution">
        <textarea className="input textarea" value={resolution} onChange={e=>setResolution(e.target.value)}/>
      </Field>

      <Field label="Assigned to">
        <input className="input" value={assignedTo} onChange={e=>setAssignedTo(e.target.value)}/>
      </Field>

      <Field label="Internal notes">
        <textarea className="input textarea" value={notes} onChange={e=>setNotes(e.target.value)}/>
      </Field>

      <Field label="Refund approved">
        <input className="input" type="number" min="0" step="0.01" value={approved} onChange={e=>setApproved(e.target.value)}/>
      </Field>

      <Field label="Replacement order ID">
        <input className="input" value={replacement} onChange={e=>setReplacement(e.target.value)}/>
      </Field>

      {error?<ErrorBox error={error}/>:null}

      <div className="actions">
        <Button disabled={saving} onClick={()=>void save()}>{saving?"Saving...":"Save case"}</Button>
      </div>
    </div>:error?<ErrorBox error={error}/>:null}
  </Modal>;
}
export function InventoryModal({token,row,canAdjust,canMove,onClose,onDone}:{token:Token;row:Obj;canAdjust:boolean;canMove:boolean;onClose:()=>void;onDone:()=>void}){const[mode,setMode]=useState<"adjust"|"move"|null>(null);return <Modal title={`${txt(get(row,"sku_id","SKU_ID"))} @ ${txt(get(row,"location_id","LOCATION_ID"))}`} onClose={onClose}><div className="order-top"><div><span>On hand</span><strong>{num(get(row,"qty_on_hand","QTY_ON_HAND"))}</strong></div><div><span>Allocated</span><strong>{num(get(row,"qty_allocated","QTY_ALLOCATED"))}</strong></div><div><span>Available</span><strong>{num(get(row,"qty_available","QTY_AVAILABLE"))}</strong></div><div><span>Inventory key</span><strong>{txt(get(row,"inventory_key","INVENTORY_KEY"))}</strong></div></div><div className="cp-actionbar"><Button disabled={!canAdjust} onClick={()=>setMode("adjust")}>Adjust stock</Button><Button kind="ghost" disabled={!canMove||num(get(row,"qty_allocated","QTY_ALLOCATED"))!==0} onClick={()=>setMode("move")}>Move row</Button></div>{mode==="adjust"&&<InventoryAdjust token={token} row={row} onClose={()=>setMode(null)} onDone={onDone}/>} {mode==="move"&&<InventoryMove token={token} row={row} onClose={()=>setMode(null)} onDone={onDone}/>}</Modal>}
function InventoryAdjust({token,row,onClose,onDone}:{token:Token;row:Obj;onClose:()=>void;onDone:()=>void}){  const key=txt(get(row,"inventory_key","INVENTORY_KEY")),current=num(get(row,"qty_on_hand","QTY_ON_HAND")),allocated=num(get(row,"qty_allocated","QTY_ALLOCATED"));  const[reasons,setReasons]=useState<Obj[]>([]),[reason,setReason]=useState(""),[count,setCount]=useState(String(current)),[notes,setNotes]=useState(""),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);  useEffect(()=>{loadReasons(token,"INVENTORY_ADJUST").then(r=>{setReasons(r);setReason(txt(get(r[0],"reason_code","REASON_CODE"),""))}).catch(setError)},[token]);  const target=Number(count),delta=target-current,unsafe=count===""||!Number.isFinite(target)||target<0||target<allocated;  async function save(){setSaving(true);try{await api(token,`/api/admin/inventory/${key}/count`,{method:"POST",body:JSON.stringify({newQuantity:target,expectedCurrentQuantity:current,reasonCode:reason,note:notes,siteId:txt(get(row,"site_id","SITE_ID"),""),operationId:newOperationId("stock-count")})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}  return <div className="nested-confirm"><h3>Record stock count</h3><div className="form"><Field label="Total physical count" help={`Current system on-hand: ${current}. WMS will derive adjustment ${delta>=0?"+":""}${delta}.`}><input className="input" type="number" min={allocated} step="1" value={count} onChange={e=>setCount(e.target.value)} placeholder="Enter total counted quantity"/></Field><Field label="Reason"><ReasonSelect reasons={reasons} value={reason} onChange={setReason}/></Field><Field label="Notes"><textarea className="input textarea" value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Count context or discrepancy notes"/></Field>{target<allocated&&<div className="warningbox">Count cannot be below the {allocated} units already allocated.</div>}{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||unsafe||delta===0||!reason} onClick={()=>void save()}>{saving?"Recording...":"Record physical count"}</Button></div></div></div>;}
function InventoryMove({token,row,onClose,onDone}:{token:Token;row:Obj;onClose:()=>void;onDone:()=>void}){const key=txt(get(row,"inventory_key","INVENTORY_KEY"));const[reasons,setReasons]=useState<Obj[]>([]),[reason,setReason]=useState(""),[to,setTo]=useState(""),[notes,setNotes]=useState(""),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);useEffect(()=>{loadReasons(token,"INVENTORY_MOVE").then(r=>{setReasons(r);setReason(txt(get(r[0],"reason_code","REASON_CODE"),""))}).catch(setError)},[token]);async function save(){setSaving(true);try{await api(token,`/api/admin/inventory/${key}/move`,{method:"POST",body:JSON.stringify({toLocationId:to,reasonCode:reason,notes,stationId:"ADMIN"})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <div className="nested-confirm"><h3>Move inventory row</h3><div className="form"><Field label="Destination location"><input className="input" value={to} onChange={e=>setTo(e.target.value)}/></Field><Field label="Reason"><ReasonSelect reasons={reasons} value={reason} onChange={setReason}/></Field><Field label="Notes"><textarea className="input textarea" value={notes} onChange={e=>setNotes(e.target.value)}/></Field>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||!to||!reason||to===txt(get(row,"location_id","LOCATION_ID"))} onClick={()=>void save()}>{saving?"Moving...":"Move stock"}</Button></div></div></div>}

export function FulfilmentPage({token,has}:{token:Token;has:HasPermission}){const initialOrderId=urlParam("orderId");const[tab,setTab]=useState<"picks"|"shipments">("picks");return <><Header title="Fulfilment" sub="Pick queue, short-close confirmation and shipment controls."/><div className="workflow-tabs"><button className={tab==="picks"?"active":""} onClick={()=>setTab("picks")}>Picks</button><button className={tab==="shipments"?"active":""} onClick={()=>setTab("shipments")}>Shipments</button></div>{tab==="picks"?<PicksPanel token={token} canConfirm={has("pick.confirm")} initialOrderId={initialOrderId}/>:<ShipmentsPanel token={token} canShip={has("shipment.ship")} initialOrderId={initialOrderId}/>}</>}
function PicksPanel({token,canConfirm,initialOrderId=""}:{token:Token;canConfirm:boolean;initialOrderId?:string}){const[status,setStatus]=useState(""),[orderId,setOrderId]=useState(initialOrderId),[rows,setRows]=useState<Obj[]>([]),[selected,setSelected]=useState<Obj|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState<unknown>(null),[nonce,setNonce]=useState(0);useEffect(()=>{let live=true;setLoading(true);api<Obj[]>(token,"/api/admin/picks"+query({status:status||undefined,orderId:orderId||undefined,limit:300})).then(x=>live&&setRows(x)).catch(e=>live&&setError(e)).finally(()=>live&&setLoading(false));return()=>{live=false}},[token,status,orderId,nonce]);return <Card><div className="toolbar cp-filters"><input className="input cp-filter" value={orderId} onChange={e=>setOrderId(e.target.value)} placeholder="Order ID"/><select className="input cp-filter" value={status} onChange={e=>setStatus(e.target.value)}><option value="">All statuses</option><option>OPEN</option><option>STARTED</option><option>COMPLETED</option><option>CANCELLED</option></select><span>{rows.length} tasks</span></div>{error?<ErrorBox error={error}/>:loading?<Load/>:<Table rows={rows} cols={[{name:"Task",cell:r=>txt(get(r,"pick_task_id","PICK_TASK_ID"))},{name:"Order",cell:r=>txt(get(r,"order_id","ORDER_ID"))},{name:"SKU",cell:r=>txt(get(r,"sku_id","SKU_ID"))},{name:"Location",cell:r=>txt(get(r,"location_id","LOCATION_ID"))},{name:"Required",cell:r=>num(get(r,"qty_required","QTY_REQUIRED"))},{name:"Picked",cell:r=>num(get(r,"qty_picked","QTY_PICKED"))},{name:"Status",cell:r=>statusPill(get(r,"status","STATUS"))},{name:"Priority",cell:r=>txt(get(r,"priority","PRIORITY"))}]} keyOf={(r,i)=>txt(get(r,"pick_task_id","PICK_TASK_ID"),String(i))} onClick={canConfirm?setSelected:undefined}/>} {selected&&<PickConfirmModal token={token} task={selected} onClose={()=>setSelected(null)} onDone={()=>{setSelected(null);setNonce(x=>x+1)}}/>}</Card>}
function PickConfirmModal({token,task,onClose,onDone}:{token:Token;task:Obj;onClose:()=>void;onDone:()=>void}){const id=txt(get(task,"pick_task_id","PICK_TASK_ID")),required=num(get(task,"qty_required","QTY_REQUIRED")),already=num(get(task,"qty_picked","QTY_PICKED"));const[qty,setQty]=useState(String(Math.max(0,required-already))),[shortClose,setShortClose]=useState(false),[reasons,setReasons]=useState<Obj[]>([]),[shortReason,setShortReason]=useState(""),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);useEffect(()=>{loadReasons(token,"PICK_SHORT").then(r=>{setReasons(r);setShortReason(txt(get(r[0],"reason_code","REASON_CODE"),""))}).catch(()=>{})},[token]);async function save(){setSaving(true);try{await api(token,`/api/admin/picks/${id}/confirm`,{method:"POST",body:JSON.stringify({qtyPicked:Number(qty),stationId:"ADMIN",shortClose,shortReason:shortClose?shortReason:undefined})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title={`Confirm pick ${id}`} onClose={onClose}><div className="form"><Field label="Quantity picked"><input className="input" type="number" min="0" value={qty} onChange={e=>setQty(e.target.value)}/></Field><label className="check"><input type="checkbox" checked={shortClose} onChange={e=>setShortClose(e.target.checked)}/> Short close remaining quantity</label>{shortClose&&<Field label="Short reason"><ReasonSelect reasons={reasons} value={shortReason} onChange={setShortReason}/></Field>}{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||Number(qty)<0||(shortClose&&!shortReason)} onClick={()=>void save()}>{saving?"Confirming...":"Confirm pick"}</Button></div></div></Modal>}
function ShipmentsPanel({token,canShip,initialOrderId=""}:{token:Token;canShip:boolean;initialOrderId?:string}){const[orderId,setOrderId]=useState(""),[rows,setRows]=useState<Obj[]>([]),[selected,setSelected]=useState<Obj|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState<unknown>(null),[nonce,setNonce]=useState(0);useEffect(()=>{let live=true;setLoading(true);api<Obj[]>(token,"/api/admin/shipments"+query({orderId:orderId||undefined,limit:300})).then(x=>live&&setRows(x)).catch(e=>live&&setError(e)).finally(()=>live&&setLoading(false));return()=>{live=false}},[token,orderId,nonce]);return <Card><div className="toolbar"><input className="input cp-filter" value={orderId} onChange={e=>setOrderId(e.target.value)} placeholder="Order ID"/><span>{rows.length} shipment rows</span></div>{error?<ErrorBox error={error}/>:loading?<Load/>:<Table rows={rows} cols={[{name:"Order",cell:r=>txt(get(r,"order_id","ORDER_ID"))},{name:"Container",cell:r=>txt(get(r,"container_id","CONTAINER_ID"))},{name:"Status",cell:r=>statusPill(get(r,"status","STATUS","container_status","CONTAINER_STATUS"))},{name:"Carrier",cell:r=>txt(get(r,"carrier_id","CARRIER_ID"))},{name:"Service",cell:r=>txt(get(r,"service_level","SERVICE_LEVEL"))},{name:"Created",cell:r=>dt(get(r,"created_dstamp","CREATED_DSTAMP"))}]} keyOf={(r,i)=>txt(get(r,"container_id","CONTAINER_ID"),String(i))} onClick={canShip?setSelected:undefined}/>} {selected&&<ShipConfirmModal token={token} row={selected} onClose={()=>setSelected(null)} onDone={()=>{setSelected(null);setNonce(x=>x+1)}}/>}</Card>}
function ShipConfirmModal({token,row,onClose,onDone}:{token:Token;row:Obj;onClose:()=>void;onDone:()=>void}){const id=txt(get(row,"container_id","CONTAINER_ID"));const[confirm,setConfirm]=useState(""),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);async function save(){setSaving(true);try{await api(token,`/api/admin/containers/${encodeURIComponent(id)}/ship`,{method:"POST",body:JSON.stringify({stationId:"ADMIN"})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title="Ship container" onClose={onClose}><div className="form"><div className="warningbox">This executes the DYNETIC shipment command for container {id}.</div><ConfirmText value={confirm} setValue={setConfirm} expected={id}/>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||confirm!==id} onClick={()=>void save()}>{saving?"Shipping...":"Ship container"}</Button></div></div></Modal>}

export function CataloguePage({token,has}:{token:Token;has:HasPermission}){const[q,setQ]=useState(""),[rows,setRows]=useState<Obj[]>([]),[selected,setSelected]=useState<Obj|null>(null),[detail,setDetail]=useState<Obj|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState<unknown>(null),[nonce,setNonce]=useState(0),[creating,setCreating]=useState(false);useEffect(()=>{let live=true;setLoading(true);api<Obj[]>(token,"/api/admin/products"+query({q:q||undefined,limit:200})).then(x=>live&&setRows(items(x))).catch(e=>live&&setError(e)).finally(()=>live&&setLoading(false));return()=>{live=false}},[token,q,nonce]);useEffect(()=>{if(!selected){setDetail(null);return}const id=txt(get(selected,"product_id","PRODUCT_ID"));api<Obj>(token,`/api/admin/products/${encodeURIComponent(id)}`).then(setDetail).catch(setError)},[selected,token,nonce]);return <><Header title="Catalogue" sub="Products, variants, pricing and web availability. Mutations use the existing admin-management API and DYNETIC audit trail." action={has("product.create")?<Button onClick={()=>setCreating(true)}>Create product</Button>:undefined}/><Card><div className="toolbar"><Search value={q} setValue={setQ} placeholder="Search product, SKU or slug..."/><span>{rows.length} products</span></div>{error?<ErrorBox error={error}/>:loading?<Load/>:<Table rows={rows} cols={[{name:"Product",cell:r=><><strong>{txt(get(r,"product_name","PRODUCT_NAME"))}</strong><small>{txt(get(r,"product_id","PRODUCT_ID"))}</small></>},{name:"Category",cell:r=>txt(get(r,"category_name","CATEGORY_NAME","category_code","CATEGORY_CODE"))},{name:"Variants",cell:r=>num(get(r,"variant_count","VARIANT_COUNT"))},{name:"From",cell:r=>money(get(r,"min_price","MIN_PRICE"),txt(get(r,"currency","CURRENCY"),"GBP"))},{name:"Available",cell:r=>num(get(r,"qty_available","QTY_AVAILABLE"))},{name:"Status",cell:r=>bool(get(r,"active","ACTIVE"))?<Pill tone="good">Active</Pill>:<Pill tone="bad">Inactive</Pill>}]} keyOf={(r,i)=>txt(get(r,"product_id","PRODUCT_ID"),String(i))} onClick={setSelected}/>}</Card>{selected&&<CatalogueModal token={token} detail={detail} has={has} onClose={()=>setSelected(null)} onChanged={()=>setNonce(x=>x+1)}/>} {creating&&<CatalogueCreateModal token={token} onClose={()=>setCreating(false)} onDone={()=>{setCreating(false);setNonce(x=>x+1)}}/>}</>}
function CatalogueCreateModal({token,onClose,onDone}:{token:Token;onClose:()=>void;onDone:()=>void}) {
  const[productId,setProductId]=useState("");
  const[name,setName]=useState("");
  const[slug,setSlug]=useState("");
  const[categories,setCategories]=useState<Obj[]>([]);
  const[categoryCode,setCategoryCode]=useState("");
  const[deliveryClass,setDeliveryClass]=useState("STANDARD");
  const[currency,setCurrency]=useState("GBP");
  const[saving,setSaving]=useState(false);
  const[loadingCategories,setLoadingCategories]=useState(true);
  const[error,setError]=useState<unknown>(null);

  useEffect(()=>{
    let live=true;
    setLoadingCategories(true);
    api<Obj[]>(token,"/api/admin/product-categories")
      .then(rows=>{
        if(!live)return;
        setCategories(rows);
        setCategoryCode(txt(get(rows[0],"category_code","CATEGORY_CODE"),""));
      })
      .catch(e=>live&&setError(e))
      .finally(()=>live&&setLoadingCategories(false));
    return()=>{live=false};
  },[token]);

  async function save(){
    setSaving(true);
    setError(null);

    try {
      await api(token,"/api/admin/products",{
        method:"POST",
        body:JSON.stringify({
          productId,
          productName:name,
          slug,
          categoryCode,
          deliveryClass,
          currency
        })
      });

      onDone();
    } catch(e){
      setError(e);
    } finally {
      setSaving(false);
    }
  }

  return <Modal title="Create product" onClose={onClose}>
    <div className="form">
      <Field label="Product ID" help="Internal product master identifier.">
        <input className="input" value={productId} onChange={e=>setProductId(e.target.value.toUpperCase())}/>
      </Field>

      <Field label="Name">
        <input className="input" value={name} onChange={e=>setName(e.target.value)}/>
      </Field>

      <Field label="Slug" help="Lower-case web address value, for example air-driven-fry-tray.">
        <input className="input" value={slug} onChange={e=>setSlug(e.target.value.toLowerCase())}/>
      </Field>

      <Field label="Category">
        <select className="input" value={categoryCode} onChange={e=>setCategoryCode(e.target.value)} disabled={loadingCategories}>
          <option value="">{loadingCategories?"Loading categories...":"Select category"}</option>
          {categories.map((c,i)=>{
            const code=txt(get(c,"category_code","CATEGORY_CODE"),String(i));
            const label=txt(get(c,"category_name","CATEGORY_NAME"),code);
            return <option key={code} value={code}>{label} ({code})</option>;
          })}
        </select>
      </Field>

      <Field label="Delivery class">
        <input className="input" value={deliveryClass} onChange={e=>setDeliveryClass(e.target.value.toUpperCase())}/>
      </Field>

      <Field label="Currency">
        <input className="input" value={currency} maxLength={3} onChange={e=>setCurrency(e.target.value.toUpperCase())}/>
      </Field>

      {categories.length===0&&!loadingCategories&&!error?<div className="warningbox">No active product categories are configured. A category is required before a product can be created.</div>:null}
      {error?<ErrorBox error={error}/>:null}

      <div className="actions">
        <Button kind="ghost" onClick={onClose}>Cancel</Button>
        <Button
          disabled={saving||loadingCategories||!productId||!name||!slug||!categoryCode}
          onClick={()=>void save()}
        >
          {saving?"Creating...":"Create product"}
        </Button>
      </div>
    </div>
  </Modal>;
}
function CatalogueModal({token,detail,has,onClose,onChanged}:{token:Token;detail:Obj|null;has:HasPermission;onClose:()=>void;onChanged:()=>void}){const[editing,setEditing]=useState(false),[variant,setVariant]=useState<Obj|null>(null);if(!detail)return <Modal title="Product" onClose={onClose}><Load/></Modal>;const id=txt(get(detail,"product_id","PRODUCT_ID")),variants=(get(detail,"variants") as Obj[])||[];return <Modal title={txt(get(detail,"product_name","PRODUCT_NAME"),id)} onClose={onClose} wide><div className="cp-actionbar">{has("product.update")&&<Button onClick={()=>setEditing(true)}>Edit product</Button>}</div><div className="detail-grid"><section className="detail-card"><h3>Catalogue</h3><strong>{id}</strong><span>{txt(get(detail,"slug","SLUG"))}</span><span>{txt(get(detail,"category_code","CATEGORY_CODE"))}</span></section><section className="detail-card"><h3>Delivery</h3><strong>{txt(get(detail,"delivery_class","DELIVERY_CLASS"))}</strong><span>{txt(get(detail,"currency","CURRENCY"),"GBP")}</span></section><section className="detail-card"><h3>Web</h3><strong>{bool(get(detail,"active","ACTIVE"))?"Active":"Inactive"}</strong><span>{bool(get(detail,"featured","FEATURED"))?"Featured":"Standard"}</span></section></div><h3 className="detail-heading">Variants</h3><Table rows={variants} cols={[{name:"SKU",cell:r=>txt(get(r,"sku_id","SKU_ID"))},{name:"Variant",cell:r=>txt(get(r,"variant_name","VARIANT_NAME"))},{name:"Price",cell:r=>money(get(r,"web_price","WEB_PRICE"),txt(get(detail,"currency","CURRENCY"),"GBP"))},{name:"Available",cell:r=>num(get(r,"qty_available","QTY_AVAILABLE"))},{name:"Sale",cell:r=>txt(get(r,"sale_type","SALE_TYPE"))},{name:"State",cell:r=>txt(get(r,"availability_state","AVAILABILITY_STATE"))}]} keyOf={(r,i)=>txt(get(r,"sku_id","SKU_ID"),String(i))} onClick={has("product.update")?setVariant:undefined}/>{editing&&<ProductEditModal token={token} product={detail} onClose={()=>setEditing(false)} onDone={()=>{setEditing(false);onChanged()}}/>}{variant&&<VariantEditModal token={token} variant={variant} canPrice={has("pricing.update")} onClose={()=>setVariant(null)} onDone={()=>{setVariant(null);onChanged()}}/>}</Modal>}
function ProductEditModal({token,product,onClose,onDone}:{token:Token;product:Obj;onClose:()=>void;onDone:()=>void}){const id=txt(get(product,"product_id","PRODUCT_ID"));const[name,setName]=useState(txt(get(product,"product_name","PRODUCT_NAME"),"")),[brand,setBrand]=useState(txt(get(product,"brand_name","BRAND_NAME"),"")),[category,setCategory]=useState(txt(get(product,"category_code","CATEGORY_CODE"),"")),[delivery,setDelivery]=useState(txt(get(product,"delivery_class","DELIVERY_CLASS"),"STANDARD")),[short,setShort]=useState(txt(get(product,"short_description","SHORT_DESCRIPTION"),"")),[description,setDescription]=useState(txt(get(product,"description","DESCRIPTION"),"")),[active,setActive]=useState(bool(get(product,"active","ACTIVE"))),[featured,setFeatured]=useState(bool(get(product,"featured","FEATURED"))),[sort,setSort]=useState(txt(get(product,"sort_sequence","SORT_SEQUENCE"),"100")),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);async function save(){setSaving(true);try{await api(token,`/api/admin/products/${id}`,{method:"PATCH",body:JSON.stringify({productName:name,brandName:brand||null,categoryCode:category,deliveryClass:delivery,shortDescription:short||null,description:description||null,active,featured,sortSequence:Number(sort)})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title={`Edit ${id}`} onClose={onClose}><div className="form"><Field label="Product name"><input className="input" value={name} onChange={e=>setName(e.target.value)}/></Field><Field label="Brand"><input className="input" value={brand} onChange={e=>setBrand(e.target.value)}/></Field><Field label="Category code"><input className="input" value={category} onChange={e=>setCategory(e.target.value)}/></Field><Field label="Delivery class"><input className="input" value={delivery} onChange={e=>setDelivery(e.target.value)}/></Field><Field label="Short description"><textarea className="input textarea" value={short} onChange={e=>setShort(e.target.value)}/></Field><Field label="Description"><textarea className="input textarea" value={description} onChange={e=>setDescription(e.target.value)}/></Field><Field label="Sort sequence"><input className="input" type="number" value={sort} onChange={e=>setSort(e.target.value)}/></Field><label className="check"><input type="checkbox" checked={active} onChange={e=>setActive(e.target.checked)}/> Active</label><label className="check"><input type="checkbox" checked={featured} onChange={e=>setFeatured(e.target.checked)}/> Featured</label>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||!name||!category} onClick={()=>void save()}>{saving?"Saving...":"Save product"}</Button></div></div></Modal>}
function VariantEditModal({token,variant,canPrice,onClose,onDone}:{token:Token;variant:Obj;canPrice:boolean;onClose:()=>void;onDone:()=>void}){const sku=txt(get(variant,"sku_id","SKU_ID"));const[name,setName]=useState(txt(get(variant,"variant_name","VARIANT_NAME"),"")),[price,setPrice]=useState(txt(get(variant,"web_price","WEB_PRICE"),"")),[saleType,setSaleType]=useState(txt(get(variant,"sale_type","SALE_TYPE"),"")),[availability,setAvailability]=useState(txt(get(variant,"availability_state","AVAILABILITY_STATE"),"")),[active,setActive]=useState(bool(get(variant,"active","ACTIVE"))),[webActive,setWebActive]=useState(txt(get(variant,"web_active","WEB_ACTIVE"),"Y")),[featured,setFeatured]=useState(txt(get(variant,"web_featured","WEB_FEATURED"),"N")),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);async function save(){setSaving(true);try{const body:Obj={variantName:name,saleType:saleType||null,availabilityState:availability||null,active,webActive,webFeatured:featured};if(canPrice&&price!=="")body.webPrice=Number(price);await api(token,`/api/admin/variants/${encodeURIComponent(sku)}`,{method:"PATCH",body:JSON.stringify(body)});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title={`Edit ${sku}`} onClose={onClose}><div className="form"><Field label="Variant name"><input className="input" value={name} onChange={e=>setName(e.target.value)}/></Field><Field label="Web price"><input className="input" type="number" step="0.01" value={price} disabled={!canPrice} onChange={e=>setPrice(e.target.value)}/></Field><Field label="Sale type"><input className="input" value={saleType} onChange={e=>setSaleType(e.target.value)}/></Field><Field label="Availability state"><input className="input" value={availability} onChange={e=>setAvailability(e.target.value)}/></Field><Field label="Web active"><select className="input" value={webActive} onChange={e=>setWebActive(e.target.value)}><option>Y</option><option>N</option></select></Field><Field label="Web featured"><select className="input" value={featured} onChange={e=>setFeatured(e.target.value)}><option>Y</option><option>N</option></select></Field><label className="check"><input type="checkbox" checked={active} onChange={e=>setActive(e.target.checked)}/> Variant active</label>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||!name} onClick={()=>void save()}>{saving?"Saving...":"Save variant"}</Button></div></div></Modal>}

export function InboundPage({token,has}:{token:Token;has:HasPermission}){const[suppliers,setSuppliers]=useState<Obj[]>([]),[pre,setPre]=useState<Obj[]>([]),[selected,setSelected]=useState<Obj|null>(null),[creating,setCreating]=useState(false),[error,setError]=useState<unknown>(null),[loading,setLoading]=useState(true),[nonce,setNonce]=useState(0);useEffect(()=>{let live=true;setLoading(true);Promise.all([api<Obj[]>(token,"/api/admin/suppliers"),api<Obj[]>(token,"/api/admin/pre-advice?limit=200")]).then(([s,p])=>{if(live){setSuppliers(s);setPre(p)}}).catch(e=>live&&setError(e)).finally(()=>live&&setLoading(false));return()=>{live=false}},[token,nonce]);if(error)return <ErrorBox error={error}/>;if(loading)return <Load/>;return <><Header title="Inbound" sub="Supplier maintenance and inbound pre-advice visibility." action={has("supplier.manage")?<Button onClick={()=>setCreating(true)}>Add supplier</Button>:undefined}/><div className="grid2"><Card><h2>Suppliers</h2><div className="cp-stack">{suppliers.map((s,i)=><button className="cp-list-button" key={txt(get(s,"supplier_id","SUPPLIER_ID"),String(i))} onClick={()=>setSelected(s)}><div><strong>{txt(get(s,"name","NAME"))}</strong><span>{txt(get(s,"supplier_id","SUPPLIER_ID"))}</span></div>{bool(get(s,"active","ACTIVE"))?<Pill tone="good">Active</Pill>:<Pill tone="bad">Inactive</Pill>}</button>)}</div></Card><Card><h2>Pre-advice</h2>{pre.length?<div className="cp-stack">{pre.map((p,i)=><div className="cp-list-row" key={txt(get(p,"pre_advice_id","PRE_ADVICE_ID"),String(i))}><div><strong>{txt(get(p,"pre_advice_id","PRE_ADVICE_ID"))}</strong><span>{txt(get(p,"supplier_id","SUPPLIER_ID"))} · {dt(get(p,"due_dstamp","DUE_DSTAMP"))}</span></div>{statusPill(get(p,"status","STATUS"))}</div>)}</div>:<Empty>No pre-advice.</Empty>}</Card></div>{creating&&<SupplierModal token={token} onClose={()=>setCreating(false)} onDone={()=>{setCreating(false);setNonce(x=>x+1)}}/>}{selected&&<SupplierModal token={token} supplier={selected} onClose={()=>setSelected(null)} onDone={()=>{setSelected(null);setNonce(x=>x+1)}} readOnly={!has("supplier.manage")}/>}</>}
function SupplierModal({token,supplier,onClose,onDone,readOnly=false}:{token:Token;supplier?:Obj;onClose:()=>void;onDone:()=>void;readOnly?:boolean}){const[id,setId]=useState(txt(supplier&&get(supplier,"supplier_id","SUPPLIER_ID"),"")),[name,setName]=useState(txt(supplier&&get(supplier,"name","NAME"),"")),[contact,setContact]=useState(txt(supplier&&get(supplier,"contact","CONTACT"),"")),[email,setEmail]=useState(txt(supplier&&get(supplier,"contact_email","CONTACT_EMAIL"),"")),[phone,setPhone]=useState(txt(supplier&&get(supplier,"contact_phone","CONTACT_PHONE"),"")),[notes,setNotes]=useState(txt(supplier&&get(supplier,"notes","NOTES"),"")),[active,setActive]=useState(supplier?bool(get(supplier,"active","ACTIVE")):true),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);async function save(){setSaving(true);try{const body={supplierId:id,name,contact:contact||null,contactEmail:email||null,contactPhone:phone||null,notes:notes||null,active};if(supplier)await api(token,`/api/admin/suppliers/${encodeURIComponent(id)}`,{method:"PATCH",body:JSON.stringify(body)});else await api(token,"/api/admin/suppliers",{method:"POST",body:JSON.stringify(body)});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title={supplier?`Supplier ${id}`:"Add supplier"} onClose={onClose}><div className="form"><Field label="Supplier ID"><input className="input" disabled={!!supplier||readOnly} value={id} onChange={e=>setId(e.target.value.toUpperCase())}/></Field><Field label="Name"><input className="input" disabled={readOnly} value={name} onChange={e=>setName(e.target.value)}/></Field><Field label="Contact"><input className="input" disabled={readOnly} value={contact} onChange={e=>setContact(e.target.value)}/></Field><Field label="Email"><input className="input" disabled={readOnly} value={email} onChange={e=>setEmail(e.target.value)}/></Field><Field label="Phone"><input className="input" disabled={readOnly} value={phone} onChange={e=>setPhone(e.target.value)}/></Field><Field label="Notes"><textarea className="input textarea" disabled={readOnly} value={notes} onChange={e=>setNotes(e.target.value)}/></Field><label className="check"><input type="checkbox" disabled={readOnly} checked={active} onChange={e=>setActive(e.target.checked)}/> Active</label>{error?<ErrorBox error={error}/>:null} {!readOnly&&<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||!id||!name} onClick={()=>void save()}>{saving?"Saving...":"Save supplier"}</Button></div>}</div></Modal>}

export function DeliveryPage({token}:{token:Token}){const[data,setData]=useState<Obj|null>(null),[error,setError]=useState<unknown>(null);useEffect(()=>{api<Obj>(token,"/api/admin/carriers").then(setData).catch(setError)},[token]);if(error)return <ErrorBox error={error}/>;if(!data)return <Load/>;const carriers=(get(data,"carriers") as Obj[])||[],services=(get(data,"services") as Obj[])||[],rates=(get(data,"rates") as Obj[])||[],zones=(get(data,"deliveryZones") as Obj[])||[],classes=(get(data,"deliveryClassControls") as Obj[])||[];return <><Header title="Delivery" sub="Carrier, service, rate, delivery-zone and class-control read model. Delivery configuration is currently read-only in Admin."/><div className="cp-metrics"><Metric label="Carriers" value={carriers.length}/><Metric label="Services" value={services.length}/><Metric label="Rates" value={rates.length}/><Metric label="Zones" value={zones.length}/><Metric label="Delivery classes" value={classes.length}/></div><div className="grid2"><Card><h2>Carriers</h2><MiniJsonRows rows={carriers}/></Card><Card><h2>Services</h2><MiniJsonRows rows={services}/></Card><Card><h2>Zones</h2><MiniJsonRows rows={zones}/></Card><Card><h2>Rates</h2><MiniJsonRows rows={rates}/></Card><Card wide><h2>Delivery class controls</h2><MiniJsonRows rows={classes}/></Card></div></>}

export function PromotionsPage({token,has}:{token:Token;has:HasPermission}){const[rows,setRows]=useState<Obj[]>([]),[selected,setSelected]=useState<Obj|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState<unknown>(null),[nonce,setNonce]=useState(0),[creating,setCreating]=useState(false);useEffect(()=>{setLoading(true);api<Obj[]>(token,"/api/admin/promotions").then(setRows).catch(setError).finally(()=>setLoading(false))},[token,nonce]);return <><Header title="Promotions" sub="Existing promotion maintenance. No create endpoint is exposed, so only existing records can be changed."/><Card>{error?<ErrorBox error={error}/>:loading?<Load/>:<Table rows={rows} cols={[{name:"Promotion",cell:r=><><strong>{txt(get(r,"promotion_id","PROMOTION_ID"))}</strong><small>{txt(get(r,"description","DESCRIPTION"))}</small></>},{name:"Value",cell:r=>txt(get(r,"promotion_value","PROMOTION_VALUE"))},{name:"Minimum",cell:r=>money(get(r,"min_order_value","MIN_ORDER_VALUE"))},{name:"Starts",cell:r=>dt(get(r,"starts_dstamp","STARTS_DSTAMP"))},{name:"Ends",cell:r=>dt(get(r,"ends_dstamp","ENDS_DSTAMP"))},{name:"Status",cell:r=>bool(get(r,"active","ACTIVE"))?<Pill tone="good">Active</Pill>:<Pill>Inactive</Pill>}]} keyOf={(r,i)=>txt(get(r,"promotion_id","PROMOTION_ID"),String(i))} onClick={setSelected}/>}</Card>{selected&&<PromotionModal token={token} item={selected} canEdit={has("promotion.manage")} onClose={()=>setSelected(null)} onDone={()=>{setSelected(null);setNonce(x=>x+1)}}/>}</>}
function PromotionModal({token,item,canEdit,onClose,onDone}:{token:Token;item:Obj;canEdit:boolean;onClose:()=>void;onDone:()=>void}){const id=txt(get(item,"promotion_id","PROMOTION_ID"));const[description,setDescription]=useState(txt(get(item,"description","DESCRIPTION"),"")),[value,setValue]=useState(txt(get(item,"promotion_value","PROMOTION_VALUE"),"")),[minimum,setMinimum]=useState(txt(get(item,"min_order_value","MIN_ORDER_VALUE"),"")),[starts,setStarts]=useState(dateInput(get(item,"starts_dstamp","STARTS_DSTAMP"))),[ends,setEnds]=useState(dateInput(get(item,"ends_dstamp","ENDS_DSTAMP"))),[active,setActive]=useState(bool(get(item,"active","ACTIVE"))),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);async function save(){setSaving(true);try{await api(token,`/api/admin/promotions/${id}`,{method:"PATCH",body:JSON.stringify({description,promotionValue:value===""?undefined:Number(value),minOrderValue:minimum===""?undefined:Number(minimum),startsDstamp:starts||undefined,endsDstamp:ends||undefined,active})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title={`Promotion ${id}`} onClose={onClose}><div className="form"><Field label="Description"><input className="input" disabled={!canEdit} value={description} onChange={e=>setDescription(e.target.value)}/></Field><Field label="Promotion value"><input className="input" disabled={!canEdit} type="number" step="0.01" value={value} onChange={e=>setValue(e.target.value)}/></Field><Field label="Minimum order value"><input className="input" disabled={!canEdit} type="number" step="0.01" value={minimum} onChange={e=>setMinimum(e.target.value)}/></Field><Field label="Starts"><input className="input" disabled={!canEdit} type="datetime-local" value={starts} onChange={e=>setStarts(e.target.value)}/></Field><Field label="Ends"><input className="input" disabled={!canEdit} type="datetime-local" value={ends} onChange={e=>setEnds(e.target.value)}/></Field><label className="check"><input type="checkbox" disabled={!canEdit} checked={active} onChange={e=>setActive(e.target.checked)}/> Active</label>{error?<ErrorBox error={error}/>:null} {canEdit&&<div className="actions"><Button disabled={saving} onClick={()=>void save()}>{saving?"Saving...":"Save promotion"}</Button></div>}</div></Modal>}

export function GiftCardsPage({token,has}:{token:Token;has:HasPermission}){const[q,setQ]=useState(""),[rows,setRows]=useState<Obj[]>([]),[selected,setSelected]=useState<Obj|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState<unknown>(null),[nonce,setNonce]=useState(0),[creating,setCreating]=useState(false);useEffect(()=>{setLoading(true);api<Obj[]>(token,"/api/admin/gift-cards"+query({q:q||undefined,limit:200})).then(setRows).catch(setError).finally(()=>setLoading(false))},[token,q,nonce]);return <><Header title="Gift cards" sub="Balance and immutable transaction ledger."/><Card><div className="toolbar"><Search value={q} setValue={setQ} placeholder="Search gift code..."/><span>{rows.length} cards</span></div>{error?<ErrorBox error={error}/>:loading?<Load/>:<Table rows={rows} cols={[{name:"Code",cell:r=>txt(get(r,"gift_code","GIFT_CODE"))},{name:"Balance",cell:r=>money(get(r,"balance","BALANCE"),txt(get(r,"currency","CURRENCY"),"GBP"))},{name:"Status",cell:r=>statusPill(get(r,"status","STATUS"))},{name:"Created",cell:r=>dt(get(r,"created_dstamp","CREATED_DSTAMP"))}]} keyOf={(r,i)=>txt(get(r,"gift_card_id","GIFT_CARD_ID"),String(i))} onClick={setSelected}/>}</Card>{selected&&<GiftCardModal token={token} card={selected} canManage={has("giftcard.manage")} onClose={()=>setSelected(null)} onDone={()=>{setSelected(null);setNonce(x=>x+1)}}/>}</>}
function GiftCardModal({token,card,canManage,onClose,onDone}:{token:Token;card:Obj;canManage:boolean;onClose:()=>void;onDone:()=>void}){const code=txt(get(card,"gift_code","GIFT_CODE")),transactions=(get(card,"transactions") as Obj[])||[];const[adjust,setAdjust]=useState(false);return <Modal title={`Gift card ${code}`} onClose={onClose}><div className="order-top"><div><span>Balance</span><strong>{money(get(card,"balance","BALANCE"),txt(get(card,"currency","CURRENCY"),"GBP"))}</strong></div><div><span>Status</span><strong>{txt(get(card,"status","STATUS"))}</strong></div></div>{canManage&&<div className="cp-actionbar"><Button onClick={()=>setAdjust(true)}>Adjust balance</Button></div>}<h3 className="detail-heading">Ledger</h3><MiniJsonRows rows={transactions}/>{adjust&&<GiftAdjustModal token={token} code={code} onClose={()=>setAdjust(false)} onDone={onDone}/>}</Modal>}
function GiftAdjustModal({token,code,onClose,onDone}:{token:Token;code:string;onClose:()=>void;onDone:()=>void}){const[reasons,setReasons]=useState<Obj[]>([]),[reason,setReason]=useState(""),[amount,setAmount]=useState(""),[notes,setNotes]=useState(""),[confirm,setConfirm]=useState(""),[error,setError]=useState<unknown>(null),[saving,setSaving]=useState(false);useEffect(()=>{loadReasons(token,"GIFTCARD").then(r=>{setReasons(r);setReason(txt(get(r[0],"reason_code","REASON_CODE"),""))}).catch(setError)},[token]);async function save(){setSaving(true);try{await api(token,`/api/admin/gift-cards/${encodeURIComponent(code)}/adjust`,{method:"POST",body:JSON.stringify({amount:Number(amount),reasonCode:reason,notes,referenceType:"ADMIN"})});onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <div className="nested-confirm"><h3>Adjust balance</h3><div className="form"><Field label="Amount" help="Positive adds credit; negative removes credit."><input className="input" type="number" step="0.01" value={amount} onChange={e=>setAmount(e.target.value)}/></Field><Field label="Reason"><ReasonSelect reasons={reasons} value={reason} onChange={setReason}/></Field><Field label="Notes"><textarea className="input textarea" value={notes} onChange={e=>setNotes(e.target.value)}/></Field><ConfirmText value={confirm} setValue={setConfirm} expected={code}/>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||Number(amount)===0||!reason||confirm!==code} onClick={()=>void save()}>{saving?"Adjusting...":"Adjust balance"}</Button></div></div></div>}

export function CommunicationsPage({token,has}:{token:Token;has:HasPermission}){const[status,setStatus]=useState(""),[rows,setRows]=useState<Obj[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState<unknown>(null),[working,setWorking]=useState(""),[nonce,setNonce]=useState(0);useEffect(()=>{setLoading(true);api<Obj[]>(token,"/api/admin/notifications"+query({status:status||undefined,limit:300})).then(setRows).catch(setError).finally(()=>setLoading(false))},[token,status,nonce]);async function retry(id:string){setWorking(id);try{await api(token,`/api/admin/notifications/${id}/retry`,{method:"POST",body:"{}"});setNonce(x=>x+1)}catch(e){setError(e)}finally{setWorking("")}}return <><Header title="Communications" sub="Notification outbox, delivery failures and guarded retry." action={<Button kind="ghost" onClick={()=>setNonce(x=>x+1)}>Refresh</Button>}/><Card><div className="toolbar"><select className="input cp-filter" value={status} onChange={e=>setStatus(e.target.value)}><option value="">All statuses</option><option>PENDING</option><option>SENT</option><option>FAILED</option><option>ERROR</option></select><span>{rows.length} messages</span></div>{error?<ErrorBox error={error}/>:loading?<Load/>:<div className="tablewrap"><table><thead><tr><th>When</th><th>Channel</th><th>Recipient</th><th>Event</th><th>Order</th><th>Status</th><th>Attempts</th><th>Error</th><th/></tr></thead><tbody>{rows.map((r,i)=>{const id=txt(get(r,"outbox_id","OUTBOX_ID"),String(i)),s=txt(get(r,"status","STATUS"));return <tr key={id}><td>{dt(get(r,"created_dstamp","CREATED_DSTAMP"))}</td><td>{txt(get(r,"channel","CHANNEL"))}</td><td>{(()=>{const recipient=txt(get(r,"recipient","RECIPIENT")),customer=relatedCustomerKey(r);return customer?<a href={entityHref("/customers",{customer})}>{recipient||customer}</a>:recipient})()}</td><td>{txt(get(r,"event_type","EVENT_TYPE","template_code","TEMPLATE_CODE","notification_type","NOTIFICATION_TYPE"),"-")}</td><td>{(()=>{const orderId=relatedOrderId(r);return orderId?<a href={orderHref(orderId)}>{orderId}</a>:"-"})()}</td><td>{statusPill(s)}</td><td>{num(get(r,"attempt_count","ATTEMPT_COUNT"))}</td><td>{txt(get(r,"last_error","LAST_ERROR"),"")}</td><td><Button kind="ghost" disabled={!has("notification.retry")||!["FAILED","ERROR"].includes(s)||working===id} onClick={()=>void retry(id)}>{working===id?"Retrying...":"Retry"}</Button></td></tr>})}</tbody></table></div>}</Card></>}

export function InterfacesPage({token,has}:{token:Token;has:HasPermission}){const[status,setStatus]=useState(""),[rows,setRows]=useState<Obj[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState<unknown>(null),[working,setWorking]=useState(""),[nonce,setNonce]=useState(0);useEffect(()=>{setLoading(true);api<Obj[]>(token,"/api/admin/interfaces/orders"+query({status:status||undefined,limit:300})).then(setRows).catch(setError).finally(()=>setLoading(false))},[token,status,nonce]);async function retry(id:string){setWorking(id);try{await api(token,`/api/admin/interfaces/orders/${id}/retry`,{method:"POST",body:"{}"});setNonce(x=>x+1)}catch(e){setError(e)}finally{setWorking("")}}return <><Header title="Interfaces" sub="Inbound order interface processing and safe retry for failed records."/><Card><div className="toolbar"><select className="input cp-filter" value={status} onChange={e=>setStatus(e.target.value)}><option value="">All statuses</option><option>NEW</option><option>PROCESSED</option><option>FAILED</option><option>ERROR</option></select><span>{rows.length} interface records</span></div>{error?<ErrorBox error={error}/>:loading?<Load/>:<div className="tablewrap"><table><thead><tr><th>Interface</th><th>Source</th><th>Source order</th><th>Status</th><th>Error</th><th>Created</th><th/></tr></thead><tbody>{rows.map((r,i)=>{const id=txt(get(r,"interface_id","INTERFACE_ID"),String(i)),s=txt(get(r,"process_status","PROCESS_STATUS"));return <tr key={id}><td><code>{id}</code></td><td>{txt(get(r,"source_system","SOURCE_SYSTEM"))}</td><td>{txt(get(r,"source_order_id","SOURCE_ORDER_ID"))}</td><td>{statusPill(s)}</td><td>{txt(get(r,"error_text","ERROR_TEXT"),"")}</td><td>{dt(get(r,"created_dstamp","CREATED_DSTAMP"))}</td><td><Button kind="ghost" disabled={!has("interface.retry")||!["FAILED","ERROR"].includes(s)||working===id} onClick={()=>void retry(id)}>{working===id?"Retrying...":"Retry"}</Button></td></tr>})}</tbody></table></div>}</Card></>}


type AuditMeta={entityTypes?:string[];actions?:string[]};

function auditObject(value:unknown):Obj{
  if(value&&typeof value==="object"&&!Array.isArray(value))return value as Obj;
  if(typeof value==="string"){
    try{
      const parsed=JSON.parse(value);
      if(parsed&&typeof parsed==="object"&&!Array.isArray(parsed))return parsed as Obj;
    }catch{}
  }
  return {};
}

function auditValue(value:unknown){
  let result:string;
  if(value===undefined)result="(not set)";
  else if(value===null)result="null";
  else if(typeof value==="string")result=value;
  else{
    try{result=JSON.stringify(value)}catch{result=String(value)}
  }
  return result.length>120?result.slice(0,117)+"...":result;
}

function auditChanges(row:Obj){
  const before=auditObject(get(row,"before_data","BEFORE_DATA"));
  const after=auditObject(get(row,"after_data","AFTER_DATA"));
  const keys=Array.from(new Set([...Object.keys(before),...Object.keys(after)])).sort();
  return keys
    .filter(key=>JSON.stringify(before[key])!==JSON.stringify(after[key]))
    .map(field=>({field,before:auditValue(before[field]),after:auditValue(after[field])}));
}

export function AuditPage({token}:{token:Token}){
  const[meta,setMeta]=useState<AuditMeta>({});
  const[entityType,setEntityType]=useState("");
  const[entityId,setEntityId]=useState("");
  const[action,setAction]=useState("");
  const[changedBy,setChangedBy]=useState("");
  const[dateFrom,setDateFrom]=useState("");
  const[dateTo,setDateTo]=useState("");
  const[offset,setOffset]=useState(0);
  const limit=100;
  const[rows,setRows]=useState<Obj[]>([]);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState<unknown>(null);

  useEffect(()=>{
    api<AuditMeta>(token,"/api/admin/audit/meta")
      .then(setMeta)
      .catch(setError);
  },[token]);

  useEffect(()=>{
    const timer=window.setTimeout(()=>{
      setLoading(true);
      setError(null);
      api<Obj[]>(token,"/api/admin/audit"+query({
        entityType:entityType||undefined,
        entityId:entityId||undefined,
        action:action||undefined,
        changedBy:changedBy||undefined,
        dateFrom:dateFrom||undefined,
        dateTo:dateTo||undefined,
        limit,
        offset
      }))
        .then(setRows)
        .catch(setError)
        .finally(()=>setLoading(false));
    },150);
    return()=>window.clearTimeout(timer);
  },[token,entityType,entityId,action,changedBy,dateFrom,dateTo,offset]);

  const resetPage=()=>setOffset(0);

  const cols=[
    {name:"When",cell:(r:Obj)=>dt(get(r,"created_dstamp","CREATED_DSTAMP"))},
    {name:"Entity",cell:(r:Obj)=><><strong>{txt(get(r,"entity_type","ENTITY_TYPE"))}</strong><small>{txt(get(r,"entity_id","ENTITY_ID"))}</small></>},
    {name:"Action",cell:(r:Obj)=>statusPill(get(r,"action","ACTION"))},
    {name:"Changed by",cell:(r:Obj)=>txt(get(r,"changed_by","CHANGED_BY"),"-")},
    {name:"Reason",cell:(r:Obj)=>txt(get(r,"reason","REASON"),"-")},
    {name:"Changes",cell:(r:Obj)=>{
      const changes=auditChanges(r);
      if(!changes.length)return "-";
      return <details>
        <summary>{changes.length} field{changes.length===1?"":"s"} changed</summary>
        <div className="cp-mini">{changes.map(c=><div key={c.field}>
          <b>{c.field.replaceAll("_"," ")}</b>
          <span>{c.before} {" -> "} {c.after}</span>
        </div>)}</div>
      </details>;
    }}
  ];

  return <>
    <Header title="Audit trail" sub="Search administrative changes by entity, action, operator and date, with field-level before/after values."/>

    <Card>
      <div className="toolbar cp-filters">
        <select className="input cp-filter" value={entityType} onChange={e=>{setEntityType(e.target.value);resetPage()}}>
          <option value="">All entity types</option>
          {(meta.entityTypes??[]).map(x=><option key={x} value={x}>{x}</option>)}
        </select>

        <input className="input cp-filter" value={entityId} onChange={e=>{setEntityId(e.target.value);resetPage()}} placeholder="Entity ID contains..."/>

        <select className="input cp-filter" value={action} onChange={e=>{setAction(e.target.value);resetPage()}}>
          <option value="">All actions</option>
          {(meta.actions??[]).map(x=><option key={x} value={x}>{x}</option>)}
        </select>

        <input className="input cp-filter" value={changedBy} onChange={e=>{setChangedBy(e.target.value);resetPage()}} placeholder="Changed by contains..."/>

        <Field label="From">
          <input className="input cp-filter" type="date" value={dateFrom} onChange={e=>{setDateFrom(e.target.value);resetPage()}}/>
        </Field>

        <Field label="To">
          <input className="input cp-filter" type="date" value={dateTo} onChange={e=>{setDateTo(e.target.value);resetPage()}}/>
        </Field>
      </div>

      {error?<ErrorBox error={error}/>:loading?<Load/>:<Table
        rows={rows}
        cols={cols}
        keyOf={(r,i)=>txt(get(r,"audit_id","AUDIT_ID"),String(i))}
      />}

      <div className="actions">
        <Button kind="ghost" disabled={offset===0} onClick={()=>setOffset(Math.max(0,offset-limit))}>Previous</Button>
        <span>{rows.length?`${offset+1}-${offset+rows.length}`:"0"} events</span>
        <Button kind="ghost" disabled={rows.length<limit} onClick={()=>setOffset(offset+limit)}>Next</Button>
      </div>
    </Card>
  </>;
}
export function AccessPage({token,has}:{token:Token;has:HasPermission}){const[users,setUsers]=useState<Obj[]>([]),[roles,setRoles]=useState<Obj[]>([]),[permissions,setPermissions]=useState<Obj[]>([]),[error,setError]=useState<unknown>(null),[loading,setLoading]=useState(true),[add,setAdd]=useState(false),[edit,setEdit]=useState<Obj|null>(null),[nonce,setNonce]=useState(0);useEffect(()=>{let live=true;setLoading(true);Promise.all([api<Obj[]>(token,"/api/admin/users"),api<Obj[]>(token,"/api/admin/roles"),api<Obj[]>(token,"/api/admin/permissions")]).then(([u,r,p])=>{if(live){setUsers(u);setRoles(r);setPermissions(p)}}).catch(e=>live&&setError(e)).finally(()=>live&&setLoading(false));return()=>{live=false}},[token,nonce]);if(error)return <ErrorBox error={error}/>;if(loading)return <Load/>;return <><Header title="Users & access" sub="Auth0 proves identity; DYNETIC decides internal access." action={has("user.create")?<Button onClick={()=>setAdd(true)}>Add staff user</Button>:undefined}/><div className="grid2"><Card><h2>Staff users</h2><div className="users">{users.map((u,i)=><button key={txt(get(u,"admin_user_id","ADMIN_USER_ID"),String(i))} onClick={()=>setEdit(u)}><div><strong>{txt(get(u,"display_name","DISPLAY_NAME","email","EMAIL"))}</strong><span>{txt(get(u,"email","EMAIL"))}</span></div><div>{((get(u,"roles") as string[])||[]).map(r=><Pill key={r} tone={r==="OWNER"?"good":""}>{r}</Pill>)}</div></button>)}</div></Card><Card><h2>Roles</h2><div className="roles">{roles.map((r,i)=><div key={txt(get(r,"role_code","ROLE_CODE"),String(i))}><strong>{txt(get(r,"role_name","ROLE_NAME"))}</strong><Pill>{txt(get(r,"role_code","ROLE_CODE"))}</Pill><p>{txt(get(r,"description","DESCRIPTION"),"No description")}</p><small>{((get(r,"permissions") as unknown[])||[]).length} permissions</small></div>)}</div></Card><Card wide><h2>Permission catalogue</h2><div className="perms">{permissions.map((p,i)=><div key={txt(get(p,"permission_code","PERMISSION_CODE"),String(i))}><code>{txt(get(p,"permission_code","PERMISSION_CODE"))}</code><span>{txt(get(p,"description","DESCRIPTION"))}</span>{bool(get(p,"dangerous","DANGEROUS"))&&<Pill tone="warn">Sensitive</Pill>}</div>)}</div></Card></div>{add&&<UserModal token={token} roles={roles} onClose={()=>setAdd(false)} onDone={()=>{setAdd(false);setNonce(x=>x+1)}}/>}{edit&&<UserModal token={token} roles={roles} user={edit} onClose={()=>setEdit(null)} onDone={()=>{setEdit(null);setNonce(x=>x+1)}}/>}</>}
function UserModal({token,roles,user,onClose,onDone}:{token:Token;roles:Obj[];user?:Obj;onClose:()=>void;onDone:()=>void}){const[email,setEmail]=useState(txt(user&&get(user,"email","EMAIL"),"")),[name,setName]=useState(txt(user&&get(user,"display_name","DISPLAY_NAME"),"")),[selected,setSelected]=useState<string[]>((user&&get(user,"roles") as string[])||["VIEWER"]),[saving,setSaving]=useState(false),[error,setError]=useState<unknown>(null);const codes=roles.filter(r=>get(r,"active","ACTIVE")!==false).map(r=>txt(get(r,"role_code","ROLE_CODE")));async function save(){setSaving(true);try{if(!user)await api(token,"/api/admin/users",{method:"POST",body:JSON.stringify({email,displayName:name,roles:selected})});else{const id=txt(get(user,"admin_user_id","ADMIN_USER_ID"));await api(token,`/api/admin/users/${id}`,{method:"PATCH",body:JSON.stringify({displayName:name})});await api(token,`/api/admin/users/${id}/roles`,{method:"PUT",body:JSON.stringify({roles:selected})})}onDone()}catch(e){setError(e)}finally{setSaving(false)}}return <Modal title={user?"Edit staff user":"Add staff user"} onClose={onClose}><div className="form"><Field label="Email"><input className="input" disabled={!!user} value={email} onChange={e=>setEmail(e.target.value)}/></Field><Field label="Display name"><input className="input" value={name} onChange={e=>setName(e.target.value)}/></Field><fieldset><legend>DYNETIC roles</legend>{codes.map(c=><label key={c} className="check"><input type="checkbox" checked={selected.includes(c)} onChange={e=>setSelected(x=>e.target.checked?[...x,c]:x.filter(v=>v!==c))}/>{c}</label>)}</fieldset>{error?<ErrorBox error={error}/>:null}<div className="actions"><Button kind="ghost" onClick={onClose}>Cancel</Button><Button disabled={saving||!email} onClick={()=>void save()}>{saving?"Saving...":"Save"}</Button></div></div></Modal>}

export function SystemPage({token}:{token:Token}){const[health,setHealth]=useState<Obj|null>(null),[reasons,setReasons]=useState<Obj[]>([]),[error,setError]=useState<unknown>(null),[nonce,setNonce]=useState(0);useEffect(()=>{Promise.all([api<Obj>(token,"/api/admin/system/health"),api<Obj[]>(token,"/api/admin/config/reason-codes")]).then(([h,r])=>{setHealth(h);setReasons(r)}).catch(setError)},[token,nonce]);if(error)return <ErrorBox error={error}/>;if(!health)return <Load/>;const operational=(get(health,"operational")??{}) as Obj,version=(get(health,"version")??{}) as Obj;return <><Header title="System" sub="Environment, DYNETIC version, operational counters and configured reason codes." action={<Button kind="ghost" onClick={()=>setNonce(x=>x+1)}>Refresh</Button>}/><div className="cp-metrics"><Metric label="Environment" value={ADMIN_CONFIG.environment}/><Metric label="Version" value={txt(get(version,"version","VERSION","versionNumber","version_number"),"0.3.18")}/><Metric label="Exceptions" value={num(get(operational,"exceptions","EXCEPTIONS"))}/><Metric label="Failed notifications" value={num(get(operational,"failed_notifications","FAILED_NOTIFICATIONS"))}/><Metric label="Processing errors 24h" value={num(get(operational,"processing_errors_24h","PROCESSING_ERRORS_24H"))}/></div><div className="grid2"><Card><h2>Runtime</h2><dl><div><dt>API</dt><dd>{ADMIN_CONFIG.apiBaseUrl}</dd></div><div><dt>DB time</dt><dd>{dt(get(health,"databaseTime"))}</dd></div><div><dt>Auth0 domain</dt><dd>{ADMIN_CONFIG.auth0Domain}</dd></div><div><dt>Audience</dt><dd>{ADMIN_CONFIG.auth0Audience}</dd></div></dl></Card><Card><h2>Version payload</h2><pre className="cp-pre">{JSON.stringify(version,null,2)}</pre></Card><Card wide><h2>Reason codes</h2><Table rows={reasons} cols={[{name:"Domain",cell:r=>txt(get(r,"reason_domain","REASON_DOMAIN"))},{name:"Code",cell:r=><code>{txt(get(r,"reason_code","REASON_CODE"))}</code>},{name:"Description",cell:r=>txt(get(r,"description","DESCRIPTION"))},{name:"Notes required",cell:r=>bool(get(r,"requires_notes","REQUIRES_NOTES"))?"Yes":"No"},{name:"Status",cell:r=>bool(get(r,"active","ACTIVE"))?<Pill tone="good">Active</Pill>:<Pill>Inactive</Pill>}]} keyOf={(r,i)=>`${txt(get(r,"reason_domain","REASON_DOMAIN"))}-${txt(get(r,"reason_code","REASON_CODE"),String(i))}`}/></Card></div></>}
