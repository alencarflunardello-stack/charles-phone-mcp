#!/usr/bin/env bash
# Owner-run recovery, read-only MCP credential. No pairing token changes.
set -euo pipefail
umask 077
H="$HOME/charles-hub"
cd "$H/tunnel"
test -x ./tunnel-client
test -s "$PREFIX/etc/tls/cert.pem"
test -s "$H/phone-mcp/server/hub-read-renew.mjs"
# Only request values if unavailable in the current shell.
if [[ -z "${CONTROL_PLANE_TUNNEL_ID:-}" ]]; then read -r -p "ID do tunel existente: " CONTROL_PLANE_TUNNEL_ID; fi
if [[ -z "${CONTROL_PLANE_API_KEY:-}" ]]; then read -r -s -p "Chave API existente (oculta): " CONTROL_PLANE_API_KEY; echo; fi
[[ "$CONTROL_PLANE_TUNNEL_ID" == tunnel_* && -n "$CONTROL_PLANE_API_KEY" ]]
export CONTROL_PLANE_TUNNEL_ID CONTROL_PLANE_API_KEY
export MCP_SERVER_URL=http://127.0.0.1:8787/mcp
export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
export MCP_OAUTH_DISCOVERY=disabled
export MCP_EXTRA_HEADERS="Authorization: file:$H/tunnel/mcp-read.header"
# Stop only known processes belonging to this local installation.
node --input-type=module <<'JS'
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
const cwd=process.cwd(), own=process.getuid(), self=process.pid;
const matches=[];
for(const p of fs.readdirSync('/proc').filter(x=>/^\d+$/.test(x))){
 try{
  if(+p===self||fs.statSync('/proc/'+p).uid!==own||fs.readlinkSync('/proc/'+p+'/cwd')!==cwd)continue;
  const a=fs.readFileSync('/proc/'+p+'/cmdline','utf8').split('\0').filter(Boolean);
  if(path.basename(a[0]??'')==='tunnel-client'&&a[1]==='run'&&a.includes('--control-plane.http-proxy=http://127.0.0.1:8889'))matches.push({p:+p,a,kind:'tunel'});
  else if(path.basename(a[0]??'')==='node'&&a[1]==='-e'&&a[2]?.includes('api.openai.com:443')&&a[2]?.includes('s.listen(8889,"127.0.0.1")'))matches.push({p:+p,a,kind:'proxy'});
 }catch{}
}
for(const m of matches.sort((a,b)=>a.kind==='tunel'?-1:b.kind==='tunel'?1:0)){
 try{
  const a=fs.readFileSync('/proc/'+m.p+'/cmdline','utf8').split('\0').filter(Boolean);
  if(JSON.stringify(a)!==JSON.stringify(m.a)||fs.readlinkSync('/proc/'+m.p+'/cwd')!==cwd)continue;
  process.kill(m.p,'SIGTERM');
  console.log('Encerrando '+m.kind+' identificado, PID '+m.p);
 }catch(e){if(e.code!=='ESRCH'&&e.code!=='ENOENT')throw e;}
}
async function free(port){return new Promise(resolve=>{const s=net.createServer();s.once('error',()=>resolve(false));s.listen(port,'127.0.0.1',()=>s.close(()=>resolve(true)));});}
for(let i=0;i<12;i++){
 if(await free(8080)&&await free(8889)){console.log('PORTAS 8080 E 8889 LIVRES');process.exit(0);}
 await new Promise(r=>setTimeout(r,1000));
}
console.error('PORTAS AINDA OCUPADAS; nenhum processo desconhecido sera encerrado.');
process.exit(1);
JS
(cd "$H/phone-mcp/server" && node hub-read-renew.mjs)
node -e 'const h=require("http"),n=require("net");const s=h.createServer((q,r)=>{r.writeHead(403);r.end()});s.on("connect",(q,c,b)=>{c.on("error",()=>c.destroy());if(q.url!=="api.openai.com:443")return c.end("HTTP/1.1 403 Forbidden\r\n\r\n");const u=n.connect(443,"api.openai.com",()=>{c.write("HTTP/1.1 200 Connection Established\r\n\r\n");if(b.length)u.write(b);c.pipe(u);u.pipe(c)});u.on("error",()=>c.destroy());c.on("close",()=>u.destroy())});s.listen(8889,"127.0.0.1")' > proxy-recovery.log 2>&1 &
P=$!
T=""
cleanup(){ if [[ -n "$T" ]]; then kill "$T" 2>/dev/null || true; fi; kill "$P" 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sleep 2
kill -0 "$P"
./tunnel-client run --control-plane.http-proxy=http://127.0.0.1:8889 > tunel-autenticado.log 2>&1 &
T=$!
for i in $(seq 1 12); do
 kill -0 "$T" || { echo "TUNEL ENCERROU; verificar tunel-autenticado.log localmente."; exit 1; }
 if curl -fsS --max-time 2 http://127.0.0.1:8080/readyz; then echo; break; fi
 sleep 2
done
sleep 32
kill -0 "$T"
curl -fsS --max-time 5 http://127.0.0.1:8080/readyz; echo
curl -fsS --max-time 5 http://127.0.0.1:8080/health/control-plane; echo
echo "CLIENTE ATIVO; mantenha esta sessao aberta. Reconecte o plugin existente."
wait "$T"
