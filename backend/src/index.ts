// Sage backend proxy (Cloudflare Worker).
//
//   POST /lookup   → product data (OFF primary, KV-cached; USDA FoodData
//                    Central gap-fill backfill), tracks popularity.
//                    Also resolves the best pack shot (curated → Kroger → OFF)
//                    into `image: { url, thumbUrl, source, ... }` pointing at
//                    GET /images/{barcode}.
//   GET  /images/{barcode} → cached pack-shot bytes from R2 (lazy-resolves).
//   POST /admin/curated-images/{barcode} → curated override (ADMIN_TOKEN).
//   GET  /alternatives → Top Rated candidates; image_url enriched to /images/…
//   POST /explain  → bucketed LLM explanation (KV-cached by version+barcode+class).
//   GET  /health   → liveness.
//
// Scores are computed on-device (the Swift ScoringEngine is the single source of
// truth); the app sends them + the drivers to /explain.

import { Hono, type MiddlewareHandler } from "hono";
import type { Env, LookupRequest, ExplainRequest, SearchRequest } from "./types";
import { fetchOFF, searchOFF, hasImage } from "./off";
import {
  getProduct, putProduct,
  getSearch, putSearch,
  explanationKey, getExplanation, putExplanation,
} from "./cache";
import { bumpScanCount, logFetch } from "./db";
import { fetchUSDA, mergeUSDA, plausiblyUS } from "./usda";
import { generateExplanation, buildTemplateOverview } from "./explanation";
import { resolveProductImage, serveCachedImage, enrichAlternativesImages, IMAGE_CACHE_VERSION } from "./imageResolver.ts";
import { putCuratedImage } from "./curatedImages.ts";
// Scoring-v4 ruleset served to clients (SCORING_V4.md §10). Keep in sync:
// `cp Sage/RulesetV5.json backend/src/ruleset.json` before deploying — the
// app treats the served version as newer than its bundled copy.
import ruleset from "./ruleset.json";
import alternatives from "./alternatives.json";

const app = new Hono<{ Bindings: Env }>();

// Shared-secret gate on data endpoints (/health and /images stay open —
// images need to load in AsyncImage without custom headers).
const requireKey: MiddlewareHandler<{ Bindings: Env }> = async (c, next) => {
  const expected = c.env.SAGE_API_KEY;
  if (expected && c.req.header("X-Sage-Key") !== expected) {
    return c.json({ error: "unauthorized" }, 401);
  }
  await next();
};
app.use("/lookup", requireKey);
app.use("/explain", requireKey);
app.use("/search", requireKey);

app.get("/health", (c) => c.json({ ok: true, service: "sage-backend" }));

// Stable pack-shot URL — one per barcode for the life of the R2 object.
app.get("/images/:barcode", async (c) => {
  const barcode = c.req.param("barcode")?.trim();
  if (!barcode) return c.text("missing barcode", 400);
  return serveCachedImage(c.env, barcode, c.req.header("If-None-Match") ?? null, {
    origin: new URL(c.req.url).origin,
    waitUntil: (p) => c.executionCtx.waitUntil(p),
    lazyResolve: true,
  });
});

// --- Curated pack-shot upload (admin) --------------------------------------
app.post("/admin/curated-images/:barcode", async (c) => {
  const expected = c.env.ADMIN_TOKEN;
  if (!expected) return c.json({ error: "admin_disabled" }, 503);
  const auth = c.req.header("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token || token !== expected) return c.json({ error: "unauthorized" }, 401);

  const barcode = c.req.param("barcode")?.trim();
  if (!barcode) return c.json({ error: "missing_barcode" }, 400);

  const contentType = c.req.header("Content-Type") || "image/jpeg";
  const bytes = await c.req.arrayBuffer();
  try {
    const result = await putCuratedImage(
      c.env,
      barcode,
      bytes,
      contentType,
      IMAGE_CACHE_VERSION,
    );
    return c.json({ ok: true, ...result, cacheVersion: IMAGE_CACHE_VERSION });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const status =
      msg === "too_large" || msg === "too_large_dimensions" ? 413
      : msg === "unsupported_type" || msg === "empty_body" || msg === "missing_barcode" ? 400
      : 500;
    return c.json({ error: msg }, status);
  }
});

// --- Scoring ruleset (v4) --------------------------------------------------
// Version probe is tiny and edge-cached hard; the full document is fetched
// only on a version mismatch. Both stay behind the shared-secret gate.
app.use("/ruleset", requireKey);
app.use("/ruleset/version", requireKey);

app.get("/ruleset/version", (c) => {
  c.header("Cache-Control", "public, max-age=300");
  return c.json({ version: (ruleset as { version: string }).version });
});

app.get("/ruleset", (c) => {
  c.header("Cache-Control", "public, max-age=300");
  return c.json(ruleset);
});

// --- Better-alternatives dataset (ALTERNATIVES_SPEC.md §4) -----------------
// Precomputed per-shelf candidates. The client probes generated_at and only
// downloads the full document when the server's is strictly newer. Candidates
// are re-scored on-device, so this dataset is not ruleset-locked.
app.use("/alternatives", requireKey);
app.use("/alternatives/version", requireKey);

app.get("/alternatives/version", (c) => {
  c.header("Cache-Control", "public, max-age=300");
  return c.json({ generated_at: (alternatives as { generated_at: string | null }).generated_at });
});

app.get("/alternatives", async (c) => {
  c.header("Cache-Control", "public, max-age=60");
  const origin = new URL(c.req.url).origin;
  const enriched = await enrichAlternativesImages(
    c.env,
    alternatives as { shelves?: Record<string, Array<{ barcode?: string; image_url?: string | null }>> },
    {
      origin,
      waitUntil: (p) => c.executionCtx.waitUntil(p),
    },
  );
  return c.json(enriched);
});

// --- Product lookup -------------------------------------------------------
app.post("/lookup", async (c) => {
  const body = await c.req.json<LookupRequest>().catch(() => null);
  if (!body?.barcode) return c.json({ error: "missing_barcode" }, 400);
  const barcode = body.barcode.trim();
  const origin = new URL(c.req.url).origin;

  // L2 cache hit.
  const cached = await getProduct(c.env.CACHE, barcode);
  if (cached) {
    c.executionCtx.waitUntil(bumpScanCount(c.env.DB, barcode, hasImage(cached)));
    const image = await resolveProductImage(c.env, barcode, cached, {
      origin,
      waitUntil: (p) => c.executionCtx.waitUntil(p),
    });
    // `product.image_*` fields remain for back-compat (deprecated — prefer `image`).
    return c.json({ source: "cache", product: cached, image });
  }

  // Open Food Facts is the primary source (global; owns the classification
  // layer: NOVA, additives, categories, Nutri-Score).
  const off = await fetchOFF(barcode).catch(() => null);

  // USDA (US Branded Foods) supplies the nutrition table, which is
  // manufacturer-label-accurate and preferred over OFF's transcribed values.
  // Queried whenever the product is plausibly US-market — the KV cache
  // amortizes the api.data.gov budget to ~one call per unique product.
  let product = off;
  let source = off ? "off" : null;
  if (c.env.USDA_API_KEY && plausiblyUS(off)) {
    const usda = await fetchUSDA(barcode, c.env.USDA_API_KEY).catch(() => null);
    if (usda) {
      product = mergeUSDA(off, usda);
      source = off ? "off+usda" : "usda";
      const reason = body.clientTag ? `backfill:${body.clientTag}` : "backfill";
      c.executionCtx.waitUntil(logFetch(c.env.DB, "usda", barcode, reason));
    }
  }

  if (!product) {
    return c.json({ error: "not_found" }, 404);
  }

  const finalSource = source ?? "off";
  c.executionCtx.waitUntil(putProduct(c.env.CACHE, barcode, product));
  c.executionCtx.waitUntil(bumpScanCount(c.env.DB, barcode, hasImage(product), finalSource));

  const image = await resolveProductImage(c.env, barcode, product, {
    origin,
    waitUntil: (p) => c.executionCtx.waitUntil(p),
  });

  // Deprecated: clients should read top-level `image` (Worker-hosted URL).
  // product.image_front_url / image_url / image_front_small_url stay populated
  // from OFF for older app builds.
  return c.json({ source: finalSource, product, image });
});

// --- Free-text name search -------------------------------------------------
// Typeahead: not metered against the free-tier scan limit (that stays on
// /lookup, which fires when the user actually selects a product).
app.post("/search", async (c) => {
  const body = await c.req.json<SearchRequest>().catch(() => null);
  const query = body?.query?.trim().toLowerCase().replace(/\s+/g, " ") ?? "";
  if (query.length < 2) return c.json({ error: "query_too_short" }, 400);

  const cached = await getSearch(c.env.CACHE, query);
  if (cached) return c.json({ source: "cache", results: cached });

  const results = await searchOFF(query).catch(() => null);
  if (results === null) return c.json({ error: "search_failed" }, 502);

  c.executionCtx.waitUntil(putSearch(c.env.CACHE, query, results));
  return c.json({ source: "off", results });
});

// --- Personalized explanation --------------------------------------------
app.post("/explain", async (c) => {
  const body = await c.req.json<ExplainRequest>().catch(() => null);
  if (!body?.barcode || !body?.classHash) {
    return c.json({ error: "missing_barcode_or_classHash" }, 400);
  }

  const version = c.env.EXPLANATION_VERSION ?? "exp-v8";
  const key = explanationKey(version, body.barcode, body.classHash);

  // L2 cache hit.
  const cached = await getExplanation(c.env.CACHE, key);
  if (cached) return c.json({ source: "cache", explanation: cached });

  if (!body.rules?.length) {
    return c.json({ source: "skip", explanation: null });
  }

  const text = await generateExplanation(c.env, body).catch(() => buildTemplateOverview(body));
  c.executionCtx.waitUntil(putExplanation(c.env.CACHE, key, text));
  c.executionCtx.waitUntil(logFetch(c.env.DB, "llm", body.barcode, "generate"));
  return c.json({ source: "overview", explanation: text });
});

export default app;
