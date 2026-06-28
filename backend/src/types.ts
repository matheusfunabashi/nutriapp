/// Worker bindings (see wrangler.toml + secrets).
export interface Env {
  CACHE: KVNamespace;
  DB: D1Database;
  OPENAI_API_KEY?: string;
  GOUPC_API_KEY?: string;
  EXPLANATION_VERSION?: string;
  FREE_DAILY_LIMIT?: string;
  GOUPC_MONTHLY_CAP?: string;   // hard spend cap on Go-UPC calls/month (0 = disabled)
}

/// Body of POST /lookup.
export interface LookupRequest {
  barcode: string;
  deviceId?: string;   // for free-tier limiting (later: validated via App Attest)
  isPremium?: boolean;
}

/// Body of POST /explain. The app computes scores locally (single source of
/// truth = the Swift ScoringEngine) and sends the factors for the prompt.
export interface ExplainRequest {
  barcode: string;
  classHash: string;       // opaque bucket key computed client-side
  productName?: string;
  objective?: string;
  overall: number;
  your: number;
  // Signed scoring drivers from the app's ScoringEngine. Prefix each with
  // "+ " if it raised the personalized score or "- " if it held it back, e.g.
  //   ["+ very low calorie density helps weight loss", "- high sugar"]
  factors?: string[];
}
