#!/usr/bin/env node
const args=process.argv.slice(2);
const arg=(n,d)=>{const i=args.indexOf(`--${n}`);return i>=0&&args[i+1]!=null?args[i+1]:d};
const base=arg('base','http://localhost:3001').replace(/\/$/,'');
const requests=Number(arg('requests','200'));
const concurrency=Number(arg('concurrency','20'));
const postcode=arg('postcode','CV13 0AA');
const country=arg('country','GB');

async function json(path,init={}){
  const started=performance.now();
  const res=await fetch(`${base}${path}`,{...init,headers:{'content-type':'application/json',...(init.headers||{})}});
  const ms=performance.now()-started; const text=await res.text(); let data=null;
  try{data=text?JSON.parse(text):null}catch{data=text}
  return {ok:res.ok,status:res.status,data,ms};
}
function pct(values,p){if(!values.length)return 0;const xs=[...values].sort((a,b)=>a-b);const i=Math.min(xs.length-1,Math.max(0,Math.ceil((p/100)*xs.length)-1));return xs[i]}

const health=await json('/health');
if(!health.ok){console.error('API health failed');process.exit(1)}
// DYNETIC_TEST_API_ENVIRONMENT_GUARD
const apiEnvironment=String(health.data?.environment??'').trim().toUpperCase();
if(apiEnvironment==='PROD'){
  console.error('SAFETY STOP: tests are FORBIDDEN against the PROD API. No load test has been run.');
  process.exit(2);
}
if(!['DEV','TEST'].includes(apiEnvironment)){
  console.error(`SAFETY STOP: API environment "${apiEnvironment||'<missing>'}" is not an approved test environment. Only DEV or TEST are allowed.`);
  process.exit(2);
}
console.log(`[SAFETY] API environment verified as ${apiEnvironment}.`);
const cat=await json('/api/catalog/products'); if(!cat.ok||!Array.isArray(cat.data)||!cat.data.length){console.error('Catalogue empty');process.exit(1)}
const variants=[];
for(const p of cat.data){
  const d=await json(`/api/catalog/products/${encodeURIComponent(p.slug)}`);
  if(!d.ok||!Array.isArray(d.data?.variants))continue;
  for(const v of d.data.variants){if(v.available===true&&Number(v.availableQty)>0)variants.push({skuId:v.skuId,deliveryClass:String(p.deliveryClass||'')})}
}
if(!variants.length){console.error('No available variants. Seed DEV stock first.');process.exit(1)}
const standard=variants.find(v=>v.deliveryClass.toUpperCase()==='STANDARD');
const livestock=variants.find(v=>v.deliveryClass.toUpperCase()==='LIVESTOCK');
const representative=standard||livestock||variants[0];
const scenarios=[
  {name:'validate',path:'/api/checkout/validate',body:()=>({items:[{sku_id:representative.skuId,qty:1}]}),expect:r=>r.ok&&r.data?.valid===true},
  {name:'delivery-options',path:'/api/delivery/options',body:()=>({items:[{sku_id:representative.skuId,qty:1}],deliveryAddress:{postcode,country}}),expect:r=>r.ok&&r.data?.valid===true&&Array.isArray(r.data?.fulfilmentOptions)},
  {name:'collection-quote',path:'/api/checkout/quote',body:()=>({items:[{sku_id:representative.skuId,qty:1}],deliveryAddress:{postcode,country},fulfilmentOptionCode:'COLLECTION'}),expect:r=>r.ok&&r.data?.valid===true&&r.data?.paymentReady===true}
];
if(standard&&livestock)scenarios.push({name:'mixed-validate',path:'/api/checkout/validate',body:()=>({items:[{sku_id:standard.skuId,qty:1},{sku_id:livestock.skuId,qty:1}]}),expect:r=>r.ok&&r.data?.valid===true&&r.data?.hasStandard===true&&r.data?.hasLivestock===true});

console.log(`DYNETIC load test\nBase: ${base}\nRequests: ${requests}\nConcurrency: ${concurrency}\nPrimary SKU: ${representative.skuId}\nSTANDARD: ${standard?.skuId||'<none>'}\nLIVESTOCK: ${livestock?.skuId||'<none>'}\n`);
let cursor=0;const results=[];
async function worker(){while(true){const n=cursor++;if(n>=requests)return;const s=scenarios[n%scenarios.length];try{const r=await json(s.path,{method:'POST',body:JSON.stringify(s.body())});results.push({scenario:s.name,ok:Boolean(s.expect(r)),status:r.status,ms:r.ms})}catch(e){results.push({scenario:s.name,ok:false,status:0,ms:0,error:String(e)})}}}
const started=performance.now();await Promise.all(Array.from({length:concurrency},()=>worker()));const elapsed=performance.now()-started;
const timings=results.filter(r=>r.ms>0).map(r=>r.ms), failures=results.filter(r=>!r.ok);
console.log(`Overall\n  completed: ${results.length}\n  passed: ${results.length-failures.length}\n  failed: ${failures.length}\n  elapsed: ${(elapsed/1000).toFixed(2)} s\n  throughput: ${(results.length/(elapsed/1000)).toFixed(1)} req/s\n  p50: ${pct(timings,50).toFixed(1)} ms\n  p95: ${pct(timings,95).toFixed(1)} ms\n  p99: ${pct(timings,99).toFixed(1)} ms\n`);
for(const name of [...new Set(results.map(r=>r.scenario))]){const rs=results.filter(r=>r.scenario===name);const ts=rs.filter(r=>r.ms>0).map(r=>r.ms);console.log(`${name}: count=${rs.length} fail=${rs.filter(r=>!r.ok).length} p50=${pct(ts,50).toFixed(1)}ms p95=${pct(ts,95).toFixed(1)}ms`)}
if(failures.length){console.log('\nFirst failures:');console.log(failures.slice(0,10));process.exit(1)}
console.log('\nPASS: load test completed without response-contract failures.');
