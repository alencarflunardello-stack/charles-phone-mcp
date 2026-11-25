#!/usr/bin/env python3
"""Owner-operated OAuth approval; never prints or stores the administrative secret."""
import getpass
import json
import sys
import urllib.error
import urllib.request
import uuid
from urllib.parse import urlsplit

ENDPOINT = "https://charles-phonemcp-pilot-rvsb.onrender.com/admin/oauth/request"

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def main():
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        raise SystemExit("Use um terminal privado interativo.")
    ref = str(uuid.UUID(input("Referência da solicitação OAuth: ").strip()))
    secret = getpass.getpass("ADMIN_PASSWORD atual (não aparece): ")
    if not secret:
        raise SystemExit("Senha vazia; cancelado.")
    opener = urllib.request.build_opener(NoRedirect())
    def post(payload):
        req = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(),
            headers={"Content-Type":"application/json","Authorization":"Bearer "+secret}, method="POST")
        try:
            with opener.open(req, timeout=20) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            raise SystemExit(f"Servidor retornou HTTP {exc.code}. Inicie uma nova autorização se expirou.")
    info = post({"approvalId":ref})
    uri = urlsplit(info["redirectUri"])
    scopes = info["scopes"]
    if info["approvalId"] != ref or uri.scheme != "https" or uri.netloc not in ("chatgpt.com","chat.openai.com") or uri.username or uri.password or not scopes or not set(scopes) <= {"phone.read","phone.write"}:
        raise SystemExit("Destino ou permissões não correspondem ao fluxo previsto. Cancelado.")
    print(json.dumps({"cliente":info["clientName"],"id":info["clientId"],"destino":info["redirectUri"],"permissoes":scopes,"referencia":ref},ensure_ascii=False,indent=2))
    if input("É exatamente a solicitação que você iniciou? Digite AUTORIZAR: ").strip() != "AUTORIZAR":
        raise SystemExit("Cancelado.")
    result = post({"approvalId":ref,"decision":"allow","clientId":info["clientId"],"redirectUri":info["redirectUri"],"scopes":scopes})
    if result.get("approved") is not True:
        raise SystemExit("Aprovação não confirmada.")
    print("Aprovação administrativa confirmada. Volte à página OAuth e conclua a autorização.")

if __name__ == "__main__":
    main()
