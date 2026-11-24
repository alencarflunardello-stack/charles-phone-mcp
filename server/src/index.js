import 'dotenv/config';
import { createBridge } from './bridge.js';
import { resolve } from 'node:path';

// Render generates canonical base64-encoded 256-bit secrets. Convert only that
// exact encoding to base64url without changing entropy or relaxing validation.
const normalizePhoneToken=value=>{
  if(typeof value==='string'&&/^[A-Za-z0-9+/]{43}=$/.test(value)){
    const decoded=Buffer.from(value,'base64');
    if(decoded.length===32&&decoded.toString('base64')===value)return decoded.toString('base64url');
  }
  return value;
};
try {
  const bridge = createBridge({publicUrl:process.env.PUBLIC_URL,phoneToken:normalizePhoneToken(process.env.PHONE_TOKEN),adminPassword:process.env.ADMIN_PASSWORD,
    stateFile:resolve('runtime/oauth.private.json'),trustProxy:process.env.TRUST_PROXY === 'true'});
  const port = Number(process.env.PORT ?? 8787), host = process.env.BIND_ADDRESS ?? '127.0.0.1';
  bridge.server.listen(port,host,() => console.log(`Phone MCP écoute sur ${host}:${port}. Publiez via votre proxy HTTPS.`));
  for (const signal of ['SIGINT','SIGTERM']) process.on(signal,async () => { await bridge.close(); process.exit(0); });
} catch (error) { console.error(error.message); process.exit(1); }
