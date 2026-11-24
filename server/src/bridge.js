import express from 'express';
import { createServer } from 'node:http';
import {CommandChannel,OperationScheduler} from './command-channel.js';
import { WebSocketServer, WebSocket } from 'ws';
import { rateLimit } from 'express-rate-limit';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { validateConfig, sameSecret, randomToken } from './config.js';
import { installOAuth } from './oauth.js';
import { makeMcp } from './mcp.js';
import {uploadSelection,readUploadBody,forwardUpload,uploadFailure} from './direct-upload.js';
import { VERSION } from './version.js';


export function createBridge(inputConfig) {
  const config = validateConfig(inputConfig), app = express();
  app.disable('x-powered-by');
  // Enable only when exactly one trusted local reverse proxy is in front of this process.
  if (config.trustProxy === true) app.set('trust proxy','loopback');
  app.use((req,res,next) => {
    res.set('Cache-Control','no-store'); res.set('X-Content-Type-Options','nosniff'); res.set('Referrer-Policy','no-referrer');
    res.set('Content-Security-Policy',"default-src 'none'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");
    const origin = req.headers.origin;
    const allowed = [config.publicUrl,'https://chatgpt.com','https://chat.openai.com'];
    if (origin && !allowed.includes(origin)) return res.status(403).json({error:'origin_denied'});
    if (origin) {
      res.set('Access-Control-Allow-Origin',origin); res.set('Vary','Origin');
      res.set('Access-Control-Allow-Headers','Authorization, Content-Type, MCP-Protocol-Version, MCP-Session-Id');
      res.set('Access-Control-Allow-Methods','GET, POST, PUT, DELETE, OPTIONS');
      res.set('Access-Control-Expose-Headers','WWW-Authenticate, MCP-Session-Id');
    }
    if (req.method === 'OPTIONS') return res.status(204).end(); next();
  });
  app.use(express.json({limit:'32kb'})); app.use(express.urlencoded({extended:false,limit:'12kb'}));
  const oauth = installOAuth(app,config);
  // Public service identity. This page never requests credentials or starts a session.
  app.get('/',(_req,res)=>res.type('html').send('<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Charles PhoneMCP — servidor piloto</title></head><body><main><h1>Charles PhoneMCP</h1><p>Servidor piloto independente do projeto Phone-MCP, para controle autorizado de aplicativos Android em sessões isoladas.</p><p>Este serviço pessoal não é uma página de login do Google, da OpenAI ou de outro provedor. Não solicita credenciais dessas contas. Nenhum acesso ao dispositivo é concedido nesta página.</p><p>O pareamento requer autorização do proprietário e um código de uso único. As permissões de aplicativos e sessões são controladas no próprio dispositivo.</p><p>Versão: '+VERSION+'</p><p><a href="https://github.com/alencarflunardello-stack/charles-phone-mcp">Código-fonte público do piloto</a> · <a href="https://github.com/Mirochill/Phone-MCP">Projeto original (MIT)</a> · <a href="/health">Estado do serviço</a></p></main></body></html>'));
  app.get('/health',(_req,res) => res.json({ok:true,version:VERSION}));
  // Public Google Search Console site-ownership proof for this pilot domain only.
  app.get('/googlea0930a7fe97df352.html',(_req,res)=>res.type('html').send('google-site-verification: googlea0930a7fe97df352.html'));
  let pairingUsed = false, pairingCode = config.pairingCode;
  let pairingExpires = Date.now() + 15*60000;
  const issuePairing=()=>{pairingCode=randomToken();pairingUsed=false;pairingExpires=Date.now()+15*60000;return {endpoint:config.publicUrl,code:pairingCode,expiresAt:pairingExpires};};
  const pairingLimit=rateLimit({windowMs:60000,limit:8,standardHeaders:'draft-8',legacyHeaders:false});
  app.post('/admin/pairing',pairingLimit,(req,res)=>{
    if(!sameSecret(req.headers.authorization,'Bearer '+config.adminPassword))return res.status(401).json({error:'unauthorized'});
    res.json(issuePairing());
  });
  // Retire browser-based password collection and install/deep-link landing pages.
  // Owners use the authenticated pairing API and the app's local connection screen.
  app.all('/admin/setup',(_req,res)=>res.status(410).type('text').send('Pareamento disponível somente no aplicativo e na API administrativa autenticada.'));
  app.get('/pairing/:code',(_req,res)=>res.status(410).type('text').send('O pareamento é realizado diretamente no aplicativo já instalado.'));
  app.post('/pair',rateLimit({windowMs:60000,limit:8,standardHeaders:'draft-8',legacyHeaders:false}),(req,res) => {
    if (!pairingCode || pairingUsed || Date.now() > pairingExpires || !sameSecret(req.body?.code,pairingCode))
      return res.status(401).json({error:'pairing_code_invalid_or_expired'});
    pairingUsed = true;
    res.json({endpoint:config.publicUrl,token:config.phoneToken});
  });
  const server = createServer(app);
  const wss = new WebSocketServer({noServer:true,maxPayload:2*1024*1024,perMessageDeflate:false});
  let phone = null, phoneAlive = false, connectedSince = null;
  const channel=new CommandChannel(config.commandTimeoutMs??12000),scheduler=new OperationScheduler();
  server.on('upgrade',(req,socket,head) => {
    const authorization = req.headers.authorization;
    if (req.url !== '/device' || req.headers.origin || !sameSecret(authorization,`Bearer ${config.phoneToken}`)) {
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n'); return;
    }
    if(phone){const old=phone;phone=null;scheduler.disconnect();channel.disconnect(old,'Connexion du téléphone remplacée ; les commandes ne sont pas rejouées.');old.close(4001,'Device connection replaced');}
    wss.handleUpgrade(req,socket,head,ws => { phone = ws; wss.emit('connection',ws); });
  });
  wss.on('connection',ws => {
    connectedSince = new Date().toISOString();
    phoneAlive = true; ws.on('pong',() => { phoneAlive = true; });
    ws.on('error',() => {});
    ws.on('message',data => {
      try {
        const response = JSON.parse(data.toString());
        channel.receive(ws,response);
      } catch { ws.close(1008,'Invalid response'); }
    });
    ws.on('close',() => {
      if (phone === ws) { phone = null; scheduler.disconnect();channel.disconnect(ws); }
    });
  });
  const heartbeat = setInterval(() => {
    if (!phone) return;
    if (!phoneAlive) { phone.terminate(); return; }
    phoneAlive = false; phone.ping();
  },60000).unref();
  const command=(op,args)=>channel.send(phone,op,args);
  app.put('/uploads/:jobId',oauth.authenticate,rateLimit({windowMs:60000,limit:600,standardHeaders:'draft-8',legacyHeaders:false}),async(req,res)=>{
    if(!req.phoneGrant.scopes.includes('phone.write'))return res.status(403).json({error:'insufficient_scope'});
    if(req.headers['content-type']?.split(';')[0]!=='application/octet-stream')return res.status(415).json({error:'binary_body_required'});
    try{const selection=uploadSelection(new URL(req.originalUrl,config.publicUrl));const bytes=await readUploadBody(req,req.headers['content-length']);const value=await forwardUpload(command,req.phoneGrant,selection,bytes);res.json(value);}
    catch(error){const f=uploadFailure(error);res.status(f.status).json(f.body);}
  });
  app.post('/mcp',oauth.authenticate,rateLimit({windowMs:60000,limit:600,standardHeaders:'draft-8',legacyHeaders:false}),async (req,res,next) => {
    const mcp = makeMcp(req.phoneGrant,command,() => ({connected:phone?.readyState === WebSocket.OPEN,connectedSince:phone ? connectedSince : null,commandInProgress:channel.pending.size>0,serverVersion:VERSION}),VERSION,scheduler);
    const transport = new StreamableHTTPServerTransport({sessionIdGenerator:undefined,enableJsonResponse:true});
    res.on('close',() => { transport.close().catch(() => {}); mcp.close().catch(() => {}); });
    try { await mcp.connect(transport); await transport.handleRequest(req,res,req.body); }
    catch (error) { if (!res.headersSent) next(error); }
  });
  app.get('/mcp',oauth.authenticate,(_req,res) => res.status(405).set('Allow','POST').end());
  app.delete('/mcp',oauth.authenticate,(_req,res) => res.status(405).set('Allow','POST').end());
  app.use((error,_req,res,_next) => res.status(error.status ?? 500).json({error:'request_failed'}));
  async function close() {
    clearInterval(heartbeat); oauth.close();
    channel.disconnect(null,'Serveur arrêté.');
    for (const ws of wss.clients) ws.terminate();
    await new Promise(resolve => wss.close(resolve));
    if (server.listening) await new Promise(resolve => server.close(resolve));
  }
  return {app,server,close};
}
