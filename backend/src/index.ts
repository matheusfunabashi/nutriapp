// Sage backend proxy (Cloudflare Worker).
//
//   POST /lookup   → product data (OFF, KV-cached; Go-UPC premium fallback TODO),
//                    enforces the free-tier daily limit, tracks popularity.
//   POST /explain  → bucketed LLM explanation (KV-cached by version+barcode+class).
//   GET  /health   → liveness.
//
// Scores are computed on-device (the Swift ScoringEngine is the single source of
// truth); the app sends them + the drivers to /explain.

import { Hono } from "hono";
import type { Env, LookupRequest, ExplainRequest } from "./types";
import { fetchOFF, hasImage } from "./off";
import {
  getProduct, putProduct,
  explanationKey, getExplanation, putExplanation,
} from "./cache";
import { checkAndIncrementUsage, bumpScanCount, logFetch } from "./db";
import { generateExplanation } from "./explanation";

const app = new Hono<{ Bindings: Env }>();

app.get("/health", (c) => c.json({ ok: true, service: "sage-backend" }));

// --- Product lookup -------------------------------------------------------
app.post("/lookup", async (c) => {
  const body = await c.req.json<LookupRequest>().catch(() => null);
  if (!body?.barcode) return c.json({ error: "missing_barcode" }, 400);
  const barcode = body.barcode.trim();

  // Free-tier daily limit (premium skips it).
  if (!body.isPremium) {
    const limit = Number(c.env.FREE_DAILY_LIMIT ?? "1");
    const allowed = await checkAndIncrementUsage(c.env.DB, body.deviceId, limit);
    if (!allowed) return c.json({ error: "daily_limit_reached" }, 429);
  }

  // L2 cache hit.
  const cached = await getProduct(c.env.CACHE, barcode);
  if (cached) {
    c.executionCtx.waitUntil(bumpScanCount(c.env.DB, barcode, hasImage(cached)));
    return c.json({ source: "cache", product: cached });
  }

  // Miss → Open Food Facts.
  let product = await fetchOFF(barcode).catch(() => null);
  if (!product) {
    // TODO: premium && OFF miss → Go-UPC fallback (then logFetch 'go_upc').
    return c.json({ error: "not_found" }, 404);
  }

  c.executionCtx.waitUntil(putProduct(c.env.CACHE, barcode, product));
  c.executionCtx.waitUntil(bumpScanCount(c.env.DB, barcode, hasImage(product)));
  return c.json({ source: "off", product });
});

// --- Personalized explanation --------------------------------------------
app.post("/explain", async (c) => {
  const body = await c.req.json<ExplainRequest>().catch(() => null);
  if (!body?.barcode || !body?.classHash) {
    return c.json({ error: "missing_barcode_or_classHash" }, 400);
  }

  const version = c.env.EXPLANATION_VERSION ?? "exp-v1";
  const key = explanationKey(version, body.barcode, body.classHash);

  // L2 cache hit.
  const cached = await getExplanation(c.env.CACHE, key);
  if (cached) return c.json({ source: "cache", explanation: cached });

  // Only spend a call when the personalization actually moved the score.
  if (Math.abs((body.your ?? 0) - (body.overall ?? 0)) < 5) {
    return c.json({ source: "skip", explanation: null });
  }

  const text = await generateExplanation(c.env, body).catch(() => null);
  if (text) {
    c.executionCtx.waitUntil(putExplanation(c.env.CACHE, key, text));
    c.executionCtx.waitUntil(logFetch(c.env.DB, "llm", body.barcode, "generate"));
  }
  return c.json({ source: text ? "llm" : "fallback", explanation: text });
});

export default app;
