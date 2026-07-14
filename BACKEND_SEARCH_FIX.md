# Backend search fix — for the Worker (do this on the machine that deploys `sage-backend`)

## The problem (measured 2026-07-13)
The app's `/search` is slow/flaky on the **first** time a word is searched (cached
searches are instant). Cause: Open Food Facts' two search endpoints:

| Endpoint the Worker calls | Status right now |
|---|---|
| `search.openfoodfacts.org` (fast "search-a-licious") | **502 on every query** (~3 s wasted) |
| `cgi/search.pl` (slow legacy fallback) | 200 but **5–6 s** |

Because the fast endpoint is currently returning 502, every cold search wastes
~3 s failing over, then spends ~5–6 s on the slow one ≈ **8 s total**, and there
are **no timeouts** so a hung upstream can stall much longer.

## What this change does
1. Adds **request timeouts** so the dead fast endpoint bails in ~2 s instead of ~3 s,
   and the slow endpoint is capped instead of hanging indefinitely.
2. Keeps the fast endpoint first, so **when OFF fixes search-a-licious, cold
   searches automatically drop to <1 s** with no further code change.

It does **not** make OFF itself faster — that's outside our control. The durable
speed win for users is the existing KV cache (repeat searches are instant).

---

## The edits — file: `backend/src/off.ts`

### Edit 1 — add a timeout helper
Find this line (near the top of the search section, ~line 56):

```ts
const SEARCH_UA = { "User-Agent": "Sage/1.0 (backend proxy; contact@sage.app)" };
```

**Paste this new function directly BELOW it:**

```ts
// Bounded fetch: aborts the upstream call after `ms` so a slow/hung OFF
// endpoint fails fast to the fallback instead of stalling the whole request.
async function fetchWithTimeout(url: string, init: RequestInit, ms: number): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}
```

### Edit 2 — give the fast search a 2 s timeout
**Find** this function:

```ts
async function searchModern(query: string, pageSize: number): Promise<SearchHit[]> {
  const url =
    "https://search.openfoodfacts.org/search" +
    `?q=${encodeURIComponent(query)}&page_size=${pageSize}&fields=${SEARCH_FIELDS}`;
  const res = await fetch(url, { headers: SEARCH_UA });
  if (!res.ok) throw new Error(`OFF search-a-licious ${res.status}`);
  const data = (await res.json()) as { hits?: Record<string, unknown>[] };
  return mapHits(data.hits ?? []);
}
```

**Replace it with** (only the `fetch` line changes):

```ts
async function searchModern(query: string, pageSize: number): Promise<SearchHit[]> {
  const url =
    "https://search.openfoodfacts.org/search" +
    `?q=${encodeURIComponent(query)}&page_size=${pageSize}&fields=${SEARCH_FIELDS}`;
  const res = await fetchWithTimeout(url, { headers: SEARCH_UA }, 2000);
  if (!res.ok) throw new Error(`OFF search-a-licious ${res.status}`);
  const data = (await res.json()) as { hits?: Record<string, unknown>[] };
  return mapHits(data.hits ?? []);
}
```

### Edit 3 — cap the slow fallback at 7 s
**Find** this function:

```ts
async function searchLegacy(query: string, pageSize: number): Promise<SearchHit[]> {
  const url =
    "https://world.openfoodfacts.org/cgi/search.pl?action=process&json=1&search_simple=1" +
    `&search_terms=${encodeURIComponent(query)}&page_size=${pageSize}&fields=${SEARCH_FIELDS}`;
  const res = await fetch(url, { headers: SEARCH_UA });
  if (!res.ok) throw new Error(`OFF search ${res.status}`);
  const data = (await res.json()) as { products?: Record<string, unknown>[] };
  return mapHits(data.products ?? []);
}
```

**Replace it with** (only the `fetch` line changes):

```ts
async function searchLegacy(query: string, pageSize: number): Promise<SearchHit[]> {
  const url =
    "https://world.openfoodfacts.org/cgi/search.pl?action=process&json=1&search_simple=1" +
    `&search_terms=${encodeURIComponent(query)}&page_size=${pageSize}&fields=${SEARCH_FIELDS}`;
  const res = await fetchWithTimeout(url, { headers: SEARCH_UA }, 7000);
  if (!res.ok) throw new Error(`OFF search ${res.status}`);
  const data = (await res.json()) as { products?: Record<string, unknown>[] };
  return mapHits(data.products ?? []);
}
```

---

## Deploy (from the `backend/` folder)

```bash
cd backend
npm install          # only needed the first time
npx wrangler deploy
```

If `wrangler` asks to log in: `npx wrangler login` (opens the browser to your
Cloudflare account), then `npx wrangler deploy` again.

## Verify after deploy
Replace `KEY` with the real `SAGE_API_KEY`, then run:

```bash
KEY="<SAGE_API_KEY>"
BASE="https://sage-backend.sage-app1710.workers.dev"

# cold search of a random word — should now be bounded (~5-6s worst case, no long hangs)
curl -s -o /dev/null -w "cold: http=%{http_code} time=%{time_total}s\n" \
  -X POST "$BASE/search" -H "X-Sage-Key: $KEY" -H "Content-Type: application/json" \
  --data '{"query":"pumpernickel"}'

# same word again — should be instant from cache (~0.05s)
curl -s -o /dev/null -w "cached: http=%{http_code} time=%{time_total}s\n" \
  -X POST "$BASE/search" -H "X-Sage-Key: $KEY" -H "Content-Type: application/json" \
  --data '{"query":"pumpernickel"}'
```

Expected: first line bounded (no multi-minute hang), second line ~0.05 s.

## Note
When Open Food Facts brings `search.openfoodfacts.org` back online, cold searches
will get fast (<1 s) automatically with these changes — no further edits needed.
The app already has a one-shot retry on transient 502s (client-side "Change A"),
so the two changes complement each other.
