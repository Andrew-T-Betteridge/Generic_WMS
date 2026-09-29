import {ADMIN_CONFIG} from "./env";

export type Obj=Record<string,unknown>;
export type Token=()=>Promise<string>;
export type HasPermission=(permission:string)=>boolean;

export class ApiError extends Error{
  status:number;
  code:string;
  body:unknown;
  constructor(status:number,code:string,body:unknown){
    super(code);this.status=status;this.code=code;this.body=body;
  }
}

export const get=(r:Obj|undefined|null,...keys:string[])=>{
  if(!r)return undefined;
  for(const key of keys)if(r[key]!==undefined)return r[key];
};
export const txt=(v:unknown,f="-")=>v===null||v===undefined||v===""?f:String(v);
export const num=(v:unknown)=>Number.isFinite(Number(v))?Number(v):0;
export const bool=(v:unknown)=>v===true||String(v).toUpperCase()==="TRUE"||String(v).toUpperCase()==="Y";
export const money=(v:unknown,c="GBP")=>Number.isFinite(Number(v))?new Intl.NumberFormat("en-GB",{style:"currency",currency:c}).format(Number(v)):"-";
export const dt=(v:unknown)=>{if(!v)return"-";const d=new Date(String(v));return Number.isNaN(d.getTime())?String(v):d.toLocaleString("en-GB")};
export const dateInput=(v:unknown)=>{if(!v)return"";const d=new Date(String(v));if(Number.isNaN(d.getTime()))return"";const p=(n:number)=>String(n).padStart(2,"0");return `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`};
export const query=(values:Obj)=>{const s=new URLSearchParams();Object.entries(values).forEach(([k,v])=>{if(v!==undefined&&v!==null&&v!=="")s.set(k,String(v))});return s.size?`?${s}`:""};
export const items=(value:unknown):Obj[]=>Array.isArray(value)?value as Obj[]:Array.isArray((value as any)?.items)?(value as any).items:[];

export async function api<T>(token:Token,path:string,init:RequestInit={}):Promise<T>{
  const headers=new Headers(init.headers);
  headers.set("Accept","application/json");
  headers.set("Authorization",`Bearer ${await token()}`);
  if(init.body)headers.set("Content-Type","application/json");
  const response=await fetch(ADMIN_CONFIG.apiBaseUrl+path,{...init,headers});
  const raw=await response.text();
  let body:any=null;
  try{body=raw?JSON.parse(raw):null}catch{body=raw}
  if(!response.ok){
    const code=String(body?.error||body?.message||`HTTP_${response.status}`);
    throw new ApiError(response.status,code,body);
  }
  return body as T;
}

export async function loadReasons(token:Token,domain:string):Promise<Obj[]>{
  return api<Obj[]>(token,"/api/admin/config/reason-codes"+query({domain}));
}
