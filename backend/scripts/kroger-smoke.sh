#!/usr/bin/env bash
# Live Kroger API smoke test. Reads credentials from .dev.vars — never hardcodes.
# Prints ONLY: which host succeeded and expires_in. Never prints tokens/secrets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
FIXTURES="$ROOT/scripts/fixtures-live"
mkdir -p "$FIXTURES"
trap 'rm -f "$FIXTURES/.token.json"' EXIT

# Resolve .dev.vars path (backend/ or repo root).
DEV_VARS=""
if [[ -f "$ROOT/.dev.vars" ]]; then DEV_VARS="$ROOT/.dev.vars"
elif [[ -f "$REPO/.dev.vars" ]]; then DEV_VARS="$REPO/.dev.vars"
else
  echo "ERROR: .dev.vars not found in $ROOT or $REPO" >&2
  exit 1
fi

# Python does Basic auth + token discovery so we never mishandle quoting in bash.
HOST="$(DEV_VARS="$DEV_VARS" FIXTURES="$FIXTURES" python3 <<'PY'
import base64, json, os, sys, urllib.error, urllib.request
from pathlib import Path

dev = Path(os.environ["DEV_VARS"])
fixtures = Path(os.environ["FIXTURES"])
creds = {}
for line in dev.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    creds[k] = v.strip().strip('"').strip("'")

cid, sec = creds.get("KROGER_CLIENT_ID", ""), creds.get("KROGER_CLIENT_SECRET", "")
if not cid or not sec:
    print("ERROR: missing KROGER_CLIENT_ID / KROGER_CLIENT_SECRET", file=sys.stderr)
    sys.exit(1)

basic = base64.b64encode(f"{cid}:{sec}".encode()).decode()
body = b"grant_type=client_credentials&scope=product.compact"
hosts = ["api.kroger.com", "api-ce.kroger.com"]
worked = None
expires = None
token = None

for host in hosts:
    req = urllib.request.Request(
        f"https://{host}/v1/connect/oauth2/token",
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Authorization": f"Basic {basic}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
            token = data["access_token"]
            expires = data.get("expires_in")
            worked = host
            print(f"TOKEN_OK host={host} expires_in={expires}", file=sys.stderr)
            break
    except urllib.error.HTTPError as e:
        print(f"TOKEN_FAIL host={host} http={e.code}", file=sys.stderr)

if not worked or not token:
    print(
        "ERROR: both token hosts rejected credentials. "
        "Likely needs production-access approval in the Kroger developer portal.",
        file=sys.stderr,
    )
    sys.exit(2)

(fixtures / ".token.json").write_text(json.dumps({"access_token": token, "expires_in": expires}))
(fixtures / "working-host.txt").write_text(worked)
print(worked)
PY
)"

echo "Using host: $HOST"
TOKEN="$(python3 -c 'import json; print(json.load(open("'"$FIXTURES"'/.token.json"))["access_token"])')"
AUTH=(-H "Authorization: Bearer ${TOKEN}" -H "Accept: application/json")

echo "--- (1) term search: jif peanut butter ---"
curl -sS "${AUTH[@]}" \
  "https://${HOST}/v1/products?filter.term=jif%20peanut%20butter&filter.limit=3" \
  -o "$FIXTURES/search-jif.json" -w "http=%{http_code} bytes=%{size_download}\n"

python3 - <<'PY' "$FIXTURES/search-jif.json"
import json,sys
d=json.load(open(sys.argv[1]))
data=d.get("data") or []
print(f"  results={len(data)}")
for i,prod in enumerate(data[:3]):
    imgs=prod.get("images") or []
    fronts=[im for im in imgs if str(im.get("perspective","")).lower()=="front"]
    sizes=(fronts[0].get("sizes") if fronts else (imgs[0].get("sizes") if imgs else [])) or []
    print(f"  [{i}] productId={prod.get('productId')} upc={prod.get('upc')} images={len(imgs)} front_sizes={[s.get('size') for s in sizes]}")
    if sizes:
        print(f"       size_keys={list(sizes[0].keys())}")
PY

JIF_ID="$(python3 -c 'import json; d=json.load(open("'"$FIXTURES"'/search-jif.json")); print((d.get("data") or [{}])[0].get("productId") or "")')"
JIF_UPC="$(python3 -c 'import json; d=json.load(open("'"$FIXTURES"'/search-jif.json")); print((d.get("data") or [{}])[0].get("upc") or "")')"

echo "--- (2) ID lookup path /products/0004400000323 ---"
HTTP_TRISCUIT="$(curl -sS -o "$FIXTURES/id-0004400000323.json" -w '%{http_code}' \
  "${AUTH[@]}" "https://${HOST}/v1/products/0004400000323")"
echo "  http=${HTTP_TRISCUIT}"

if [[ "$HTTP_TRISCUIT" != "200" ]]; then
  if [[ -n "$JIF_ID" ]]; then
    echo "  Triscuit miss — re-query by first Jif productId=${JIF_ID}"
    curl -sS -o "$FIXTURES/id-jif.json" -w "  http=%{http_code}\n" \
      "${AUTH[@]}" "https://${HOST}/v1/products/${JIF_ID}"
  fi
else
  cp "$FIXTURES/id-0004400000323.json" "$FIXTURES/id-lookup-ok.json"
fi

if [[ -n "$JIF_UPC" ]]; then
  echo "--- (2b) ID lookup path /products/${JIF_UPC} ---"
  curl -sS -o "$FIXTURES/id-by-upc-${JIF_UPC}.json" -w "  http=%{http_code}\n" \
    "${AUTH[@]}" "https://${HOST}/v1/products/${JIF_UPC}"
fi

echo "--- (2c) probe filter.upc / filter.productId / filter.term=upc ---"
PROBE_UPC="${JIF_UPC:-0004400000323}"
curl -sS -o "$FIXTURES/probe-filter-upc.json" -w "  filter.upc http=%{http_code}\n" \
  "${AUTH[@]}" "https://${HOST}/v1/products?filter.upc=${PROBE_UPC}&filter.limit=1" || true
if [[ -n "$JIF_ID" ]]; then
  curl -sS -o "$FIXTURES/probe-filter-productId.json" -w "  filter.productId http=%{http_code}\n" \
    "${AUTH[@]}" "https://${HOST}/v1/products?filter.productId=${JIF_ID}&filter.limit=1" || true
fi
curl -sS -o "$FIXTURES/probe-filter-term-upc.json" -w "  filter.term=upc http=%{http_code}\n" \
  "${AUTH[@]}" "https://${HOST}/v1/products?filter.term=${PROBE_UPC}&filter.limit=1" || true

echo "--- (3) not-found Brazilian EAN 7891000100103 ---"
curl -sS -o "$FIXTURES/not-found-7891000100103.json" -w "  http=%{http_code}\n" \
  "${AUTH[@]}" "https://${HOST}/v1/products/7891000100103"

python3 - <<'PY' "$FIXTURES" "$HOST"
import json,sys
from pathlib import Path
root=Path(sys.argv[1]); host=sys.argv[2]
print("--- shape summary ---")
for p in sorted(root.glob("*.json")):
    if p.name.startswith("."): continue
    try:
        d=json.loads(p.read_text())
    except Exception as e:
        print(f"{p.name}: parse_error {e}"); continue
    keys=list(d.keys()) if isinstance(d,dict) else type(d).__name__
    data=d.get("data") if isinstance(d,dict) else None
    if isinstance(data, list):
        shape=f"data:list(len={len(data)})"
        if data:
            prod=data[0]
            imgs=prod.get("images") or []
            sample_size=None
            if imgs and imgs[0].get("sizes"):
                sample_size=list(imgs[0]["sizes"][0].keys())
            shape += f" productKeys={sorted(prod.keys())[:14]} sizeKeys={sample_size}"
    elif isinstance(data, dict):
        imgs=data.get("images") or []
        sample_size=None
        if imgs and imgs[0].get("sizes"):
            sample_size=list(imgs[0]["sizes"][0].keys())
        shape=f"data:object productKeys={sorted(data.keys())[:14]} sizeKeys={sample_size}"
    else:
        shape=f"data={type(data).__name__ if data is not None else None}"
    err = (d.get("errors") or d.get("error")) if isinstance(d,dict) else None
    print(f"{p.name}: topKeys={keys} {shape} err={bool(err)}")
print(f"WORKING_HOST={host}")
PY

echo "DONE fixtures in $FIXTURES"
