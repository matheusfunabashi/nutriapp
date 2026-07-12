/// Worker bindings (see wrangler.toml + secrets).
export interface Env {
  CACHE: KVNamespace;
  DB: D1Database;
  OPENAI_API_KEY?: string;
  GOUPC_API_KEY?: string;
  EXPLANATION_VERSION?: string;
  FREE_DAILY_LIMIT?: string;
  GOUPC_MONTHLY_CAP?: string;   // hard spend cap on Go-UPC calls/month (0 = disabled)
  SAGE_API_KEY?: string;        // shared secret the app sends as X-Sage-Key (gate)
}

/// Body of POST /lookup.
export interface LookupRequest {
  barcode: string;
  deviceId?: string;   // for free-tier limiting (later: validated via App Attest)
  isPremium?: boolean;
  clientTag?: string;  // dev-phase device label, logged with paid calls (Go-UPC)
                       // so trial quota is attributable; DeviceCheck replaces it
}

/// Body of POST /search (free-text product name/brand search).
export interface SearchRequest {
  query: string;
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
  // The LOW/MOD/HIGH badge levels the user sees in the Breakdown card, e.g.
  // ["sugar: low (4g)", "sodium: high (800mg)"]. Ground truth the model must
  // never contradict — keeps the sentence consistent with the UI.
  nutrientLevels?: string[];
}
