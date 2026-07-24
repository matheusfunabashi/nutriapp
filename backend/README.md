# Sage backend (Cloudflare Worker)

Thin proxy + shared cache for the Sage iOS app. Holds the API keys, fans out to
Open Food Facts / USDA / Kroger / OpenAI, caches results, and serves stable
product pack-shot URLs.

## Architecture
- **KV (`CACHE`)** — product snapshots (`product:v4:<barcode>`), search hits,
  bucketed explanations, OAuth tokens, and image metadata / negative-cache
  entries (`image:v1:<barcode>`, `image:miss:v1:<barcode>`).
- **R2 (`IMAGES`)** — downloaded pack-shot bytes at `product-images/{barcode}`.
- **D1 (`DB`)** — `usage` (free-tier counters), `product_meta` (popularity +
  image-backfill flags), `fetch_log` (paid-call audit).
- Scores are computed **on-device** (Swift `ScoringEngine`); the app sends them
  + the drivers to `/explain`. The Worker never re-derives the score.

## Product images
Resolution chain (once per barcode, then cached):

1. **KV + R2 cache** — serve immediately when fresh (&lt; 30 days). Stale entries
   are returned and revalidated in the background (`waitUntil`).
2. **Kroger Products API** — official US retailer pack shots (preferred).
3. **Open Food Facts** — front-image selection (same priority order as the
   iOS `OFFImageResolver`).
4. **null** — app falls back to placeholder / user photo. Misses are
   negative-cached for 7 days. Kroger 429/5xx gets a 6h per-barcode backoff.

Successful resolutions download the image once into R2 and expose it at a
stable Worker URL:

```
GET /images/{barcode}   → image/jpeg (Cache-Control: immutable, ETag)
```

`POST /lookup` includes a top-level `image` object:

```json
{
  "source": "off",
  "product": { "...": "OFF fields including deprecated image_* URLs" },
  "image": {
    "url": "https://<worker>/images/001111041600",
    "thumbUrl": "https://<worker>/images/001111041600",
    "source": "kroger",
    "isFrontImage": true,
    "isLowQuality": false
  }
}
```

`product.image_front_url` / `image_url` / `image_front_small_url` are kept for
older app builds (**deprecated** — prefer top-level `image`).

Each resolution logs `{ event: "image_resolved", barcode, source }` so Kroger
coverage can be measured in production.

### Kroger API display terms
**Review Kroger’s API / brand display terms before enabling Kroger images in
production.** Official pack shots may carry usage constraints (attribution,
caching duration, redistribution). Do not ship Kroger-sourced images publicly
until legal/product has signed off. Leaving `KROGER_CLIENT_ID` /
`KROGER_CLIENT_SECRET` unset disables Kroger and falls through to OFF only.

### Live smoke (credentials in `.dev.vars`)
```bash
# From backend/ — reads KROGER_* from ./ .dev.vars or ../.dev.vars
./scripts/kroger-smoke.sh
# Prints only: TOKEN_OK host=… expires_in=…
# Writes raw JSON under scripts/fixtures-live/ (gitignored)
```

Validated host (2026-07-24): `https://api.kroger.com` (`expires_in=1800`).
Set `KROGER_BASE_URL` in `wrangler.toml` `[vars]` (already defaulted).
Foreign EANs (e.g. Brazilian `789…`) are skipped before any Kroger HTTP call
(`shouldAttemptKroger` / log `image_kroger_skip`).

### Deploy checklist
```bash
npx wrangler login
# Enable R2 once in the Dashboard (R2 → Get started), then:
npx wrangler r2 bucket create sage-product-images
npx wrangler r2 bucket create sage-product-images-preview
# Uncomment [[r2_buckets]] in wrangler.toml and redeploy.

# Secrets from repo-root .dev.vars (quoted values):
grep '^KROGER_CLIENT_ID=' ../.dev.vars | cut -d'"' -f2 | npx wrangler secret put KROGER_CLIENT_ID
grep '^KROGER_CLIENT_SECRET=' ../.dev.vars | cut -d'"' -f2 | npx wrangler secret put KROGER_CLIENT_SECRET
npx wrangler secret list
npx wrangler deploy
```

Until R2 is enabled, `IMAGES` is unbound and `GET /images/{barcode}` **302-redirects**
to the upstream CDN URL stored in KV (stable Worker URL still works).

## Endpoints
| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/health` | — | liveness |
| GET | `/images/{barcode}` | — | cached pack shot from R2 (public; long Cache-Control) |
| GET | `/ruleset/version` | — | scoring-v5 ruleset version probe (edge-cached 5 min; keyed) |
| GET | `/ruleset` | — | full scoring-v5 ruleset JSON (keyed). **Sync before deploy:** `cp Sage/RulesetV5.json backend/src/ruleset.json` |
| POST | `/lookup` | `{ barcode, deviceId?, isPremium?, clientTag? }` | OFF (+ USDA) lookup + image resolution; KV-cached |
| POST | `/search` | `{ query }` | free-text OFF name/brand search (typeahead); KV-cached 24h |
| POST | `/explain` | `{ barcode, classHash, overall, your, … }` | bucketed LLM overview; cache-first |

## First-time setup
```bash
cd backend
npm install
npx wrangler login

# Create the stores, then paste the printed ids into wrangler.toml:
npx wrangler kv namespace create CACHE
npx wrangler kv namespace create CACHE --preview
npx wrangler d1 create sage
npx wrangler r2 bucket create sage-product-images
npx wrangler r2 bucket create sage-product-images-preview

# Schema:
npm run migrate:local        # local dev
npm run migrate:remote       # production

# Secrets (never commit these):
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put USDA_API_KEY          # api.data.gov FoodData Central
npx wrangler secret put KROGER_CLIENT_ID      # developer.kroger.com
npx wrangler secret put KROGER_CLIENT_SECRET
npx wrangler secret put SAGE_API_KEY          # optional shared gate for /lookup etc.
npx wrangler secret put ADMIN_TOKEN           # Bearer for POST /admin/curated-images/{barcode}
```

Local secrets go in `.dev.vars` (see `.dev.vars.example`).

### wrangler.toml bindings
| Binding | Type | Purpose |
|---|---|---|
| `CACHE` | KV | products, search, explanations, image meta, Kroger OAuth token |
| `DB` | D1 | usage + fetch audit |
| `IMAGES` | R2 | pack-shot bytes (`product-images/{barcode}`) + curated overrides (`curated-images/{barcode}`) |

## Product images

Resolution chain: **curated → Kroger → OFF**. Public URL is always
`GET /images/{barcode}?v=N` (KV `cacheVersion` / `IMAGE_CACHE_VERSION` bumps
re-resolve lazily without flushing).

### Upload a curated pack shot
```bash
# Longest side must be ≤1000px. JPEG or PNG.
TOKEN="<ADMIN_TOKEN>"
BARCODE="0037466016450"   # e.g. Lindt
curl -X POST "https://sage-backend.sage-app1710.workers.dev/admin/curated-images/${BARCODE}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: image/jpeg" \
  --data-binary @./lindt-pack.jpg
```

Top Rated / `GET /alternatives` rewrites `image_url` to the Worker image URL
when R2 already has bytes, and background-resolves the rest via `waitUntil`.

## Run / deploy
```bash
# Local dev (uses .dev.vars for secrets — copy from .dev.vars.example):
npm run dev

# Tests (no live network):
npm test

# Smoke test:
curl localhost:8787/health
curl -X POST localhost:8787/lookup -H 'content-type: application/json' \
  -d '{"barcode":"5449000000996"}'

# Ship it:
npm run deploy
```

## Config (wrangler.toml `[vars]`)
- `EXPLANATION_VERSION` — bump to invalidate all cached explanations (e.g. after
  a scoring/prompt change).

## TODO (next backend steps)
- App Attest / DeviceCheck validation of `deviceId` (currently trusted).
- StoreKit receipt validation for `isPremium`.
- Rate limiting + cost alerts.
