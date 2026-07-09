# Sage backend (Cloudflare Worker)

Thin proxy + shared cache for the Sage iOS app. Holds the API keys, fans out to
Open Food Facts / Go-UPC / OpenAI, caches results, and enforces the free-tier
daily scan limit.

## Architecture
- **KV (`CACHE`)** — product snapshots (`product:<barcode>`) + bucketed
  explanations (`exp:<version>:<barcode>:<classHash>`).
- **D1 (`DB`)** — `usage` (free-tier counters), `product_meta` (popularity +
  image-backfill flags), `fetch_log` (paid-call audit).
- Scores are computed **on-device** (Swift `ScoringEngine`); the app sends them
  + the drivers to `/explain`. The Worker never re-derives the score.

## Endpoints
| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/health` | — | liveness |
| POST | `/lookup` | `{ barcode, deviceId?, isPremium?, clientTag? }` | OFF lookup + KV cache; enforces free limit; tracks popularity; Go-UPC premium fallback (calls logged to `fetch_log` with `fallback:<clientTag>` for per-device attribution) |
| POST | `/search` | `{ query }` | free-text OFF name/brand search (typeahead); KV-cached 24h; not metered against the free-tier limit |
| POST | `/explain` | `{ barcode, classHash, overall, your, objective?, productName?, factors? }` | bucketed LLM explanation of how the product fits the user's goal; cache-first; skips when `factors` is empty |

## First-time setup
```bash
cd backend
npm install
npx wrangler login

# Create the stores, then paste the printed ids into wrangler.toml:
npx wrangler kv namespace create CACHE
npx wrangler kv namespace create CACHE --preview
npx wrangler d1 create sage

# Schema:
npm run migrate:local        # local dev
npm run migrate:remote       # production

# Secrets (never commit these):
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put GOUPC_API_KEY    # optional until Go-UPC is wired
```

## Run / deploy
```bash
# Local dev (uses .dev.vars for secrets — copy from .dev.vars.example):
npm run dev

# Smoke test:
curl localhost:8787/health
curl -X POST localhost:8787/lookup -H 'content-type: application/json' \
  -d '{"barcode":"5449000000996","isPremium":true}'

# Ship it:
npm run deploy
```

## Config (wrangler.toml `[vars]`)
- `EXPLANATION_VERSION` — bump to invalidate all cached explanations (e.g. after
  a scoring/prompt change).
- `FREE_DAILY_LIMIT` — free-tier scans per device per day.

## TODO (next backend steps)
- App Attest / DeviceCheck validation of `deviceId` (currently trusted).
- StoreKit receipt validation for `isPremium`.
- Image-backfill admin endpoints (popularity-ranked, manual trigger, monthly cap).
- Rate limiting + cost alerts.
