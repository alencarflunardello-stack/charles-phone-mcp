// Owner-run, loopback-only diagnostic and read credential renewal.
import 'dotenv/config';
import {randomBytes,createHash} from 'node:crypto';
import {existsSync,readFileSync,writeFileSync,renameSync,chmodSync} from 'node:fs';
import {join} from 'node:path';
const base='http://127.0.0.1:8787', dir=join(process.env.HOME,'charles-hub/tunnel');
const state=join(dir,'read-renewal.private.json'), header=join(dir,'mcp-read.header');
const scope=['phone.read'];
process.umask(0o077);
function store(path,value){const tmp=path+'.'+randomBytes(8).toString('hex')+'.tmp';writeFileSync(tmp,value,{mode:0o600,flag:'wx'});renameSync(tmp,path);chmodSync(path,0o600);}
async function request(path,body,admin=false){
 const r=await fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json',...(admin?{Authorization:'Bearer '+process.env.ADMIN_PASSWORD}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw Error(path+' HTTP '+r.status);
 return r.json();
}
async function issue(){
 if(!process.env.ADMIN_PASSWORD)throw Error('Configuracao administrativa ausente.');
 const redirect=base+'/hub-callback',verifier=randomBytes(32).toString('base64url'),challenge=createHash('sha256').update(verifier).digest('base64url');
 const c=await request('/register',{client_name:'Charles Hub leitura local',redirect_uris:[redirect],token_endpoint_auth_method:'none'});
 const q=new URLSearchParams({client_id:c.client_id,redirect_uri:redirect,response_type:'code',code_challenge_method:'S256',code_challenge:challenge,scope:scope.join(' ')});
 const r=await fetch(base+'/authorize?'+q,{signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw Error('Autorizacao HTTP '+r.status);
 const html=await r.text(),id=html.match(/Referência da solicitação: <code>([^<]+)/)?.[1],nonce=html.match(/name="nonce" value="([^"]+)"/)?.[1];
 if(!id||!nonce)throw Error('Solicitacao ausente.');
 const d=await request('/admin/oauth/request',{approvalId:id},true);
 if(d.clientId!==c.client_id||d.redirectUri!==redirect||JSON.stringify(d.scopes)!==JSON.stringify(scope))throw Error('Solicitacao divergente.');
 await request('/admin/oauth/request',{approvalId:id,decision:'allow',clientId:d.clientId,redirectUri:d.redirectUri,scopes:d.scopes},true);
 const a=await fetch(base+'/approve',{method:'POST',redirect:'manual',headers:{'Content-Type':'application/json'},body:JSON.stringify({nonce,decision:'allow'}),signal:AbortSignal.timeout(10000)});
 if(a.status!==303)throw Error('Aprovacao HTTP '+a.status);
 const location=new URL(a.headers.get('location'));
 if(location.origin+location.pathname!==redirect)throw Error('Callback divergente.');
 const code=location.searchParams.get('code');
 if(!code)throw Error('Codigo ausente.');
 return {client_id:c.client_id,t:await request('/token',{grant_type:'authorization_code',client_id:c.client_id,redirect_uri:redirect,code,code_verifier:verifier})};
}
async function main(){
 let record;
 if(existsSync(state)){
   const old=JSON.parse(readFileSync(state,'utf8'));
   if(old.scope!=='phone.read'||!old.client_id||!old.refresh_token)throw Error('Registro de renovacao invalido.');
   record={client_id:old.client_id,t:await request('/token',{grant_type:'refresh_token',client_id:old.client_id,refresh_token:old.refresh_token,scope:'phone.read'})};
 }else record=await issue();
 const {client_id,t}=record;
 if(t.scope!=='phone.read'||!t.access_token||!t.refresh_token)throw Error('Permissoes ou credenciais divergentes.');
 store(state,JSON.stringify({client_id,refresh_token:t.refresh_token,scope:t.scope,expires_at:Date.now()+t.expires_in*1000}));
 store(header,'Bearer '+t.access_token);
 console.log('CREDENCIAL DE LEITURA RENOVADA; renovacao futura armazenada localmente.');
 async function rpc(method,params,id){
   const r=await fetch(base+'/mcp',{method:'POST',headers:{Authorization:'Bearer '+t.access_token,'Content-Type':'application/json',Accept:'application/json, text/event-stream','MCP-Protocol-Version':'2025-03-26'},body:JSON.stringify({jsonrpc:'2.0',id,method,params}),signal:AbortSignal.timeout(10000)});
   if(!r.ok)throw Error('MCP '+method+' HTTP '+r.status);
   const data=await r.json();if(data.error)throw Error('MCP '+method+' falhou');return data.result;
 }
 await rpc('initialize',{protocolVersion:'2025-03-26',capabilities:{},clientInfo:{name:'charles-local-check',version:'1'}},1);
 const result=await rpc('tools/call',{name:'phone_connection',arguments:{}},2);
 const d=result.structuredContent??JSON.parse(result.content[0].text);
 console.log(JSON.stringify({connected:d.connected,connectedSince:d.connectedSince,serverVersion:d.serverVersion}));
 if(typeof d.connected!=='boolean')throw Error('Resposta de pareamento invalida.');
}
main().catch(e=>{console.error('FALHA: '+e.message);process.exitCode=1;});
