import React,{useCallback,useEffect,useMemo,useState} from "react";
import ReactDOM from "react-dom/client";
import {Auth0Provider,useAuth0} from "@auth0/auth0-react";
import "./styles.css";
import "./control-plane.css";
import "./ui/ui.css";
import {BrowserRouter} from "react-router";
import {ADMIN_CONFIG} from "./env";
import {api,type Token} from "./admin-api";
import type {Me} from "./control-plane";
import {AdminShell,brandInitials} from "./routing/AdminShell";
import {createHasPermission} from "./lib/permissions";
import {describeError} from "./lib/api-errors";

function Button({children,onClick,kind=""}:{children:React.ReactNode;onClick?:()=>void;kind?:string}){
  return <button className={`btn ${kind}`} onClick={onClick}>{children}</button>;
}
function Load(){return <div className="load"><i/>Loading...</div>}
function ErrorBox({error}:{error:unknown}){const d=describeError(error);return <div className="error" role="alert"><strong>{d.title}</strong><span>{d.kind==="forbidden"?"This account is not registered for Admin access. Ask an Admin administrator to grant access.":d.message}</span><details className="ui-technical"><summary>Technical details</summary><code>{d.technical}</code></details></div>}

function App(){
  const{isLoading,isAuthenticated,loginWithRedirect,logout,getAccessTokenSilently}=useAuth0();
  const[me,setMe]=useState<Me|null>(null),[error,setError]=useState<unknown>(null);
  const token=useCallback<Token>(async()=>{
    const t=await getAccessTokenSilently({authorizationParams:{audience:ADMIN_CONFIG.auth0Audience}});
    if(!t)throw new Error("AUTH_TOKEN_MISSING");
    return t;
  },[getAccessTokenSilently]);

  useEffect(()=>{
    if(!isAuthenticated){setMe(null);return}
    api<Me>(token,"/api/admin/me").then(setMe).catch(setError);
  },[isAuthenticated,token]);

  // Single interpretation of /api/admin/me permissions, matching the API (exact code or "*").
  const has=useMemo(()=>createHasPermission(me?.permissions),[me]);
  if(isLoading)return <div className="splash"><Load/></div>;
  if(!isAuthenticated)return <div className="splash"><div className="login"><div className="logo">{brandInitials(ADMIN_CONFIG.adminTitle)}</div><h1>{ADMIN_CONFIG.adminTitle}</h1><p>Internal operations portal powered by DYNETIC WMS.</p><Button onClick={()=>loginWithRedirect()}>Sign in with Auth0</Button></div></div>;
  if(error)return <div className="splash"><div className="login"><h1>Admin access unavailable</h1><ErrorBox error={error}/><Button kind="ghost" onClick={()=>logout({logoutParams:{returnTo:location.origin}})}>Sign out</Button></div></div>;
  if(!me)return <div className="splash"><Load/></div>;

  return <AdminShell me={me} token={token} has={has} title={ADMIN_CONFIG.adminTitle} environment={ADMIN_CONFIG.environment} onSignOut={()=>logout({logoutParams:{returnTo:location.origin}})}/>;
}

const{auth0Domain:domain,auth0ClientId:clientId,auth0Audience:audience}=ADMIN_CONFIG;
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Auth0Provider domain={domain} clientId={clientId} cacheLocation="localstorage" useRefreshTokens authorizationParams={{redirect_uri:location.origin,audience,scope:"openid profile email"}}>
      <BrowserRouter>
        <App/>
      </BrowserRouter>
    </Auth0Provider>
  </React.StrictMode>,
);
