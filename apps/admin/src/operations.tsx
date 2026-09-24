import { useEffect, useMemo, useState } from "react";

type Obj=Record<string,unknown>;
type Token=()=>Promise<string>;

const BASE=(import.meta.env.VITE_API_BASE_URL||"https://api.finaticsaquatics.co.uk").replace(/\/$/,"");
const get=(r:Obj,...k:string[])=>{for(const x of k)if(r[x]!==undefined)return r[x]};
const txt=(v:unknown,f="-")=>v===null||v===undefined||v===""?f:String(v);
const num=(v:unknown)=>Number.isFinite(Number(v))?Number(v):0;
const money=(v:unknown,c="GBP")=>Number.isFinite(Number(v))?new Intl.NumberFormat("en-GB",{style:"currency",currency:c}).format(Number(v)):"-";
const dt=(v:unknown)=>{if(!v)return"-";const d=new Date(String(v));return Number.isNaN(d.getTime())?String(v):d.toLocaleString("en-GB")};
const Q=(x:Obj)=>{const s=new URLSearchParams();Object.entries(x).forEach(([k,v])=>{if(v!==undefined&&v!==null&&v!=="")s.set(k,String(v))});return s.size?`?${s}`:""};

async function req<T>(token:Token,path:string,init:RequestInit={}):Promise<T>{
  const h=new Headers(init.headers);
  h.set("Accept","application/json");
  h.set("Authorization",`Bearer ${await token()}`);
  if(init.body)h.set("Content-Type","application/json");
  const r=await fetch(BASE+path,{...init,headers:h});
  const raw=await r.text();
  let b:any=null;
  try{b=raw?JSON.parse(raw):null}catch{b=raw}
  if(!r.ok)throw new Error(String(b?.error||b?.message||`HTTP_${r.status}`));
  return b as T;
}

function Btn({children,onClick,disabled,kind=""}:{children:React.ReactNode;onClick?:()=>void;disabled?:boolean;kind?:string}){return <button className={`btn ${kind}`} onClick={onClick} disabled={disabled}>{children}</button>}
function Pill({children,tone=""}:{children:React.ReactNode;tone?:string}){return <span className={`pill ${tone}`}>{children}</span>}
function Load(){return <div className="load"><i/>Loading...</div>}
function Err({e}:{e:unknown}){return <div className="error"><strong>Operation could not be completed</strong><span>{e instanceof Error?e.message:String(e)}</span></div>}
function Modal({title,onClose,children}:{title:string;onClose:()=>void;children:React.ReactNode}){return <div className="shade" onMouseDown={e=>{if(e.target===e.currentTarget)onClose()}}><div className="modal"><div className="modalhead"><h2>{title}</h2><Btn kind="ghost" onClick={onClose}>Close</Btn></div><div className="modalbody">{children}</div></div></div>}

export function InventoryOperations({token,canAdjust}:{token:Token;canAdjust:boolean}){
  const[q,setQ]=useState(""),[rows,setRows]=useState<Obj[]>([]),[selected,setSelected]=useState<Obj|null>(null),[loading,setLoading]=useState(true),[e,setE]=useState<unknown>(null),[nonce,setNonce]=useState(0);

  useEffect(()=>{let live=true;setLoading(true);setE(null);
    req<Obj[]>(token,"/api/admin/inventory/rows"+Q({q:q||undefined,limit:300}))
      .then(x=>live&&setRows(x)).catch(x=>live&&setE(x)).finally(()=>live&&setLoading(false));
    return()=>{live=false};
  },[token,q,nonce]);

  const totals=useMemo(()=>rows.reduce<{on:number;alloc:number;avail:number}>((a,r)=>({on:a.on+num(get(r,"qty_on_hand","QTY_ON_HAND")),alloc:a.alloc+num(get(r,"qty_allocated","QTY_ALLOCATED")),avail:a.avail+num(get(r,"qty_available","QTY_AVAILABLE"))}),{on:0,alloc:0,avail:0}),[rows]);

  return <>
    <div className="head"><div><h1>Inventory</h1><p>Live stock with audited adjustment controls. Allocated stock can never be reduced below its reservation.</p></div><Btn kind="ghost" onClick={()=>setNonce(x=>x+1)}>Refresh</Btn></div>
    <div className="opstats"><div><span>Rows</span><strong>{rows.length}</strong></div><div><span>On hand</span><strong>{totals.on}</strong></div><div><span>Allocated</span><strong>{totals.alloc}</strong></div><div><span>Available</span><strong>{totals.avail}</strong></div></div>
    <section className="card">
      <div className="toolbar"><input className="input search" value={q} onChange={x=>setQ(x.target.value)} placeholder="Search SKU, product, tag, batch or location..."/><span>{canAdjust?"Adjustments enabled":"Read only"}</span></div>
      {e?<Err e={e}/>:loading?<Load/>:<div className="tablewrap"><table><thead><tr><th>Product / SKU</th><th>Location</th><th>On hand</th><th>Allocated</th><th>Available</th><th>Condition</th><th>Last movement</th><th/></tr></thead><tbody>
        {rows.map((r,i)=>{const key=txt(get(r,"inventory_key","INVENTORY_KEY"),String(i));const available=num(get(r,"qty_available","QTY_AVAILABLE"));return <tr key={key}>
          <td><strong>{txt(get(r,"product_name","PRODUCT_NAME","variant_name","VARIANT_NAME"))}</strong><small>{txt(get(r,"sku_id","SKU_ID"))} Â· stock row #{key}</small></td>
          <td>{txt(get(r,"location_id","LOCATION_ID"))}</td>
          <td>{num(get(r,"qty_on_hand","QTY_ON_HAND"))}</td><td>{num(get(r,"qty_allocated","QTY_ALLOCATED"))}</td><td><Pill tone={available>0?"good":"warn"}>{available}</Pill></td>
          <td>{txt(get(r,"condition_id","CONDITION_ID"))}</td><td>{dt(get(r,"move_dstamp","MOVE_DSTAMP"))}</td>
          <td><Btn disabled={!canAdjust} kind="ghost" onClick={()=>setSelected(r)}>Adjust</Btn></td>
        </tr>})}
      </tbody></table></div>}
    </section>
    {selected&&<AdjustModal token={token} row={selected} onClose={()=>setSelected(null)} onDone={()=>{setSelected(null);setNonce(x=>x+1)}}/>}
  </>;
}

function AdjustModal({token,row,onClose,onDone}:{token:Token;row:Obj;onClose:()=>void;onDone:()=>void}){
  const[qty,setQty]=useState(""),[reason,setReason]=useState("COUNT"),[notes,setNotes]=useState(""),[saving,setSaving]=useState(false),[e,setE]=useState<unknown>(null),[result,setResult]=useState<Obj|null>(null);
  const key=txt(get(row,"inventory_key","INVENTORY_KEY"));
  const current=num(get(row,"qty_on_hand","QTY_ON_HAND")),allocated=num(get(row,"qty_allocated","QTY_ALLOCATED"));
  const adjustment=Number(qty),newQty=Number.isFinite(adjustment)?current+adjustment:current;
  const unsafe=Number.isFinite(adjustment)&&(newQty<0||newQty<allocated);

  async function save(){
    setSaving(true);setE(null);
    try{
      const r=await req<Obj>(token,`/api/admin/inventory/${encodeURIComponent(key)}/adjust`,{method:"POST",body:JSON.stringify({adjustmentQty:Number(qty),reasonCode:reason,notes})});
      setResult(r);
    }catch(x){setE(x)}finally{setSaving(false)}
  }

  return <Modal title={`Adjust ${txt(get(row,"sku_id","SKU_ID"))} at ${txt(get(row,"location_id","LOCATION_ID"))}`} onClose={onClose}>
    {result?<div className="successbox"><strong>Inventory adjusted</strong><span>{txt(get(result.operation as Obj||{},"result_message","RESULT_MESSAGE"),"Stock updated and audited.")}</span><Btn onClick={onDone}>Done</Btn></div>:<div className="form">
      <div className="adjust-summary"><div><span>On hand</span><strong>{current}</strong></div><div><span>Allocated</span><strong>{allocated}</strong></div><div><span>After adjustment</span><strong>{newQty}</strong></div></div>
      <label>Adjustment quantity <small>Use + to add stock or - to remove stock.</small><input className="input" type="number" step="1" value={qty} onChange={x=>setQty(x.target.value)} placeholder="+10 or -3"/></label>
      <label>Reason code<select className="input" value={reason} onChange={x=>setReason(x.target.value)}><option>COUNT</option><option>DAMAGE</option><option>LOSS</option><option>FOUND</option><option>CORRECT</option><option>RETURN</option></select></label>
      <label>Notes<textarea className="input textarea" maxLength={400} value={notes} onChange={x=>setNotes(x.target.value)} placeholder="Why is the stock changing?"/></label>
      {unsafe&&<div className="warningbox">That adjustment would leave on-hand stock below zero or below the quantity already allocated. DYNETIC will reject it.</div>}
      {e?<Err e={e}/>:null}
      <div className="actions"><Btn kind="ghost" onClick={onClose}>Cancel</Btn><Btn disabled={saving||!qty||Number(qty)===0||unsafe} onClick={save}>{saving?"Adjusting...":"Confirm adjustment"}</Btn></div>
    </div>}
  </Modal>;
}

export function OrdersOperations({token,canCancel}:{token:Token;canCancel:boolean}){
  const[q,setQ]=useState(""),[rows,setRows]=useState<Obj[]>([]),[sel,setSel]=useState<Obj|null>(null),[detail,setDetail]=useState<Obj|null>(null),[loading,setLoading]=useState(true),[e,setE]=useState<unknown>(null),[nonce,setNonce]=useState(0);

  useEffect(()=>{let live=true;setLoading(true);setE(null);req<any>(token,"/api/admin/orders"+Q({q:q||undefined,limit:250})).then(x=>live&&setRows(Array.isArray(x)?x:x?.items||[])).catch(x=>live&&setE(x)).finally(()=>live&&setLoading(false));return()=>{live=false}},[token,q,nonce]);
  useEffect(()=>{if(!sel){setDetail(null);return}const id=txt(get(sel,"order_id","ORDER_ID","orderId"),"");if(id)req<Obj>(token,`/api/admin/orders/${encodeURIComponent(id)}`).then(setDetail).catch(setE)},[sel,token,nonce]);

  return <>
    <div className="head"><div><h1>Orders</h1><p>Operational order visibility with protected cancellation. Picked or shipped orders cannot be cancelled here.</p></div><Btn kind="ghost" onClick={()=>setNonce(x=>x+1)}>Refresh</Btn></div>
    <section className="card"><div className="toolbar"><input className="input search" value={q} onChange={x=>setQ(x.target.value)} placeholder="Search order, customer or status..."/><span>{rows.length} orders</span></div>
    {e?<Err e={e}/>:loading?<Load/>:<div className="tablewrap"><table><thead><tr><th>Order</th><th>Customer</th><th>Status</th><th>Payment</th><th>Fulfilment</th><th>Value</th></tr></thead><tbody>{rows.map((r,i)=><tr className="click" key={txt(get(r,"order_id","ORDER_ID","orderId"),String(i))} onClick={()=>setSel(r)}><td><strong>{txt(get(r,"order_id","ORDER_ID","orderId","order_reference","ORDER_REFERENCE"))}</strong><small>{dt(get(r,"order_date","ORDER_DATE","created_dstamp"))}</small></td><td>{txt(get(r,"customer_email","contact_email","CUSTOMER_EMAIL","email","CONTACT_EMAIL"))}</td><td><Pill>{txt(get(r,"status","STATUS"))}</Pill></td><td><Pill tone={txt(get(r,"payment_status","PAYMENT_STATUS"))==="PAID"?"good":"warn"}>{txt(get(r,"payment_status","PAYMENT_STATUS"))}</Pill></td><td>{txt(get(r,"fulfilment_status","FULFILMENT_STATUS"))}</td><td>{money(get(r,"order_value","ORDER_VALUE","total"),String(get(r,"inv_currency","INV_CURRENCY","currency")||"GBP"))}</td></tr>)}</tbody></table></div>}
    </section>
    {sel&&<OrderModal token={token} order={sel} detail={detail} canCancel={canCancel} onClose={()=>setSel(null)} onChanged={()=>{setSel(null);setNonce(x=>x+1)}}/>}
  </>;
}

function OrderModal({token,order,detail,canCancel,onClose,onChanged}:{token:Token;order:Obj;detail:Obj|null;canCancel:boolean;onClose:()=>void;onChanged:()=>void}){
  const[cancelOpen,setCancelOpen]=useState(false);
  const id=txt(get(order,"order_id","ORDER_ID","orderId"));
  if(!detail)return <Modal title={`Order ${id}`} onClose={onClose}><Load/></Modal>;
  const status=txt(get(detail,"status","STATUS", "orderStatus"));
  const fulfilment=txt(get(detail,"fulfilment_status","FULFILMENT_STATUS","fulfilmentStatus"));
  const terminal=status==="CANCELLED"||fulfilment==="CANCELLED"||["SHIPPED","DELIVERED"].includes(fulfilment);
  return <Modal title={`Order ${id}`} onClose={onClose}>
    <div className="orderhero"><div><span>Order</span><strong>{id}</strong></div><div><span>Status</span><strong>{status}</strong></div><div><span>Payment</span><strong>{txt(get(detail,"payment_status","PAYMENT_STATUS","paymentStatus"))}</strong></div><div><span>Fulfilment</span><strong>{fulfilment}</strong></div></div>
    <dl>{Object.entries(detail).filter(([,v])=>!Array.isArray(v)&&typeof v!=="object").slice(0,30).map(([k,v])=><div key={k}><dt>{k.replace(/_/g," ")}</dt><dd>{txt(v)}</dd></div>)}</dl>
    {Array.isArray(detail.lines)&&<><h3>Lines</h3><pre>{JSON.stringify(detail.lines,null,2)}</pre></>}
    <div className="dangerzone"><div><strong>Cancel order</strong><span>Releases open allocations. Picked or shipped orders are blocked. Captured payments are never silently refunded.</span></div><Btn disabled={!canCancel||terminal} kind="danger" onClick={()=>setCancelOpen(true)}>Cancel order</Btn></div>
    {cancelOpen&&<CancelOrder token={token} orderId={id} onClose={()=>setCancelOpen(false)} onDone={onChanged}/>}
  </Modal>;
}

function CancelOrder({token,orderId,onClose,onDone}:{token:Token;orderId:string;onClose:()=>void;onDone:()=>void}){
  const[reason,setReason]=useState("CUSTOMER"),[notes,setNotes]=useState(""),[confirm,setConfirm]=useState(""),[saving,setSaving]=useState(false),[e,setE]=useState<unknown>(null),[result,setResult]=useState<Obj|null>(null);
  async function cancel(){
    setSaving(true);setE(null);
    try{setResult(await req<Obj>(token,`/api/admin/orders/${encodeURIComponent(orderId)}/cancel`,{method:"POST",body:JSON.stringify({reasonCode:reason,notes})}))}
    catch(x){setE(x)}finally{setSaving(false)}
  }
  return <div className="nested-confirm">
    {result?<div className="successbox"><strong>Order cancelled</strong><span>{txt(get(result.operation as Obj||{},"result_message","RESULT_MESSAGE"),"Open stock released and audit event recorded.")}</span><Btn onClick={onDone}>Done</Btn></div>:<>
      <h3>Confirm cancellation</h3><p>This is an operational cancellation. It does not silently refund a captured payment.</p>
      <div className="form"><label>Reason<select className="input" value={reason} onChange={x=>setReason(x.target.value)}><option>CUSTOMER</option><option>STOCK</option><option>DUPLICATE</option><option>ERROR</option><option>OTHER</option></select></label><label>Notes<textarea className="input textarea" maxLength={400} value={notes} onChange={x=>setNotes(x.target.value)} placeholder="Cancellation context"/></label><label>Type the order ID to confirm<input className="input" value={confirm} onChange={x=>setConfirm(x.target.value)} placeholder={orderId}/></label>{e?<Err e={e}/>:null}<div className="actions"><Btn kind="ghost" onClick={onClose}>Keep order</Btn><Btn kind="danger" disabled={saving||confirm!==orderId} onClick={cancel}>{saving?"Cancelling...":"Cancel order"}</Btn></div></div>
    </>}
  </div>;
}
