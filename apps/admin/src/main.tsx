import React,{useCallback,useEffect,useMemo,useState} from "react";
import ReactDOM from "react-dom/client";
import {Auth0Provider,useAuth0} from "@auth0/auth0-react";
import "./styles.css";
import "./control-plane.css";
import {NotificationBell} from "./monitoring";
import {ADMIN_CONFIG} from "./env";
import {api,type Token} from "./admin-api";
import {
  AccessPage,
  AuditPage,
  CataloguePage,
  CommunicationsPage,
  CustomersPage,
  DeliveryPage,
  ExceptionsPage,
  FulfilmentPage,
  GiftCardsPage,
  InboundPage,
  InterfacesPage,
  InventoryPage,
  OperationsDashboard,
  OrdersPage,
  PaymentsPage,
  PromotionsPage,
  ReturnsPage,
  SystemPage,
  type Me,
} from "./control-plane";

type Page=
  |"dashboard"|"orders"|"payments"|"returns"|"customers"|"inventory"|"fulfilment"
  |"catalogue"|"inbound"|"delivery"|"promotions"|"giftcards"
  |"communications"|"interfaces"|"exceptions"|"audit"|"access"|"system";

type NavItem={page:Page;label:string;permissions:string[]};
type NavSection={label:string;items:NavItem[]};

function Button({children,onClick,kind=""}:{children:React.ReactNode;onClick?:()=>void;kind?:string}){
  return <button className={`btn ${kind}`} onClick={onClick}>{children}</button>;
}
function Load(){return <div className="load"><i/>Loading...</div>}
function ErrorBox({error}:{error:unknown}){return <div className="error"><strong>Admin access unavailable</strong><span>{error instanceof Error?error.message:String(error)}</span></div>}

function App(){
  const{isLoading,isAuthenticated,loginWithRedirect,logout,getAccessTokenSilently}=useAuth0();
  const[me,setMe]=useState<Me|null>(null),[error,setError]=useState<unknown>(null),[page,setPage]=useState<Page>("dashboard");
  const token=useCallback<Token>(async()=>{
    const t=await getAccessTokenSilently({authorizationParams:{audience:ADMIN_CONFIG.auth0Audience}});
    if(!t)throw new Error("AUTH_TOKEN_MISSING");
    return t;
  },[getAccessTokenSilently]);

  useEffect(()=>{
    if(!isAuthenticated){setMe(null);return}
    api<Me>(token,"/api/admin/me").then(setMe).catch(setError);
  },[isAuthenticated,token]);

  const has=useCallback((permission:string)=>!!me?.permissions.includes(permission),[me]);
  const canAny=useCallback((permissions:string[])=>permissions.some(has),[has]);

  const sections=useMemo<NavSection[]>(()=>{
    const raw:NavSection[]=[
    {label:"Operations",items:[
      {page:"dashboard",label:"Control centre",permissions:["dashboard.read"]},
      {page:"orders",label:"Orders",permissions:["order.read"]},
      {page:"payments",label:"Payments",permissions:["payment.read"]},
      {page:"returns",label:"Returns & claims",permissions:["return.read"]},
      {page:"customers",label:"Customers",permissions:["order.read"]},
      {page:"inventory",label:"Inventory",permissions:["inventory.read"]},
      {page:"fulfilment",label:"Fulfilment",permissions:["pick.read","shipment.read"]},
    ]},
    {label:"Commercial",items:[
      {page:"catalogue",label:"Catalogue",permissions:["product.read"]},
      {page:"promotions",label:"Promotions",permissions:["config.read"]},
      {page:"giftcards",label:"Gift cards",permissions:["giftcard.read"]},
    ]},
    {label:"Supply & delivery",items:[
      {page:"inbound",label:"Inbound",permissions:["supplier.read","pre_advice.read"]},
      {page:"delivery",label:"Delivery",permissions:["carrier.read"]},
    ]},
    {label:"Platform",items:[
      {page:"communications",label:"Communications",permissions:["notification.read"]},
      {page:"interfaces",label:"Interfaces",permissions:["interface.read"]},
      {page:"exceptions",label:"Exceptions",permissions:["exception.read"]},
      {page:"audit",label:"Audit",permissions:["audit.read"]},
      {page:"access",label:"Users & roles",permissions:["user.read"]},
      {page:"system",label:"System",permissions:["system.read"]},
    ]},
  ];
    return raw.map(section=>({...section,items:section.items.filter(item=>canAny(item.permissions))})).filter(section=>section.items.length>0);
  },[canAny]);

  useEffect(()=>{
    if(!me)return;
    const available=new Set(sections.flatMap(s=>s.items.map(i=>i.page)));
    if(!available.has(page))setPage(available.has("dashboard")?"dashboard":sections[0]?.items[0]?.page??"dashboard");
  },[me,page,sections]);

  if(isLoading)return <div className="splash"><Load/></div>;
  if(!isAuthenticated)return <div className="splash"><div className="login"><div className="logo">FA</div><h1>{ADMIN_CONFIG.adminTitle}</h1><p>Internal operations portal powered by DYNETIC WMS.</p><Button onClick={()=>loginWithRedirect()}>Sign in with Auth0</Button></div></div>;
  if(error)return <div className="splash"><div className="login"><h1>Admin access unavailable</h1><ErrorBox error={error}/><Button kind="ghost" onClick={()=>logout({logoutParams:{returnTo:location.origin}})}>Sign out</Button></div></div>;
  if(!me)return <div className="splash"><Load/></div>;

  const content=page==="orders"?<OrdersPage token={token} has={has}/>:
    page==="payments"?<PaymentsPage token={token} has={has}/>:
    page==="returns"?<ReturnsPage token={token} has={has}/>:
    page==="customers"?<CustomersPage token={token}/>:
    page==="inventory"?<InventoryPage token={token} has={has}/>:
    page==="fulfilment"?<FulfilmentPage token={token} has={has}/>:
    page==="catalogue"?<CataloguePage token={token} has={has}/>:
    page==="inbound"?<InboundPage token={token} has={has}/>:
    page==="delivery"?<DeliveryPage token={token}/>:
    page==="promotions"?<PromotionsPage token={token} has={has}/>:
    page==="giftcards"?<GiftCardsPage token={token} has={has}/>:
    page==="communications"?<CommunicationsPage token={token} has={has}/>:
    page==="interfaces"?<InterfacesPage token={token} has={has}/>:
    page==="exceptions"?<ExceptionsPage token={token}/>:
    page==="audit"?<AuditPage token={token}/>:
    page==="access"?<AccessPage token={token} has={has}/>:
    page==="system"?<SystemPage token={token}/>:
    <OperationsDashboard token={token} me={me}/>;

  return <div className="shell cp-shell"><aside><div className="brand"><div className="logo small">FA</div><div><strong>{ADMIN_CONFIG.adminTitle}</strong><span>DYNETIC WMS · {ADMIN_CONFIG.environment}</span></div></div><nav className="cp-nav">{sections.map(section=><div className="cp-nav-section" key={section.label}><span className="cp-nav-label">{section.label}</span>{section.items.map(item=><button className={page===item.page?"active":""} key={item.page} onClick={()=>setPage(item.page)}>{item.label}</button>)}</div>)}</nav><div className="foot"><strong>{me.displayName||me.email}</strong><span>{me.roles.join(", ")}</span><small>{me.permissions.length} permissions</small><button onClick={()=>logout({logoutParams:{returnTo:location.origin}})}>Sign out</button></div></aside><main>{content}<NotificationBell token={token}/></main></div>;
}

const{auth0Domain:domain,auth0ClientId:clientId,auth0Audience:audience}=ADMIN_CONFIG;
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Auth0Provider domain={domain} clientId={clientId} cacheLocation="localstorage" useRefreshTokens authorizationParams={{redirect_uri:location.origin,audience,scope:"openid profile email"}}>
      <App/>
    </Auth0Provider>
  </React.StrictMode>,
);
