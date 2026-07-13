/// Worker bindings (see wrangler.toml + secrets).
export interface Env {
  CACHE: KVNamespace;
  DB: D1Database;
  OPENAI_API_KEY?: string;
  USDA_API_KEY?: string;        // api.data.gov FoodData Central key (OFF backfill)
  EXPLANATION_VERSION?: string;
  SAGE_API_KEY?: string;        // shared secret the app sends as X-Sage-Key (gate)
}

/// Body of POST /lookup. Scans are unlimited and USDA backfill is free +
/// public-domain, so there is no device identity or premium gate here; premium
/// gates top-rated-product access client-side.
export interface LookupRequest {
  barcode: string;
  clientTag?: string;  // stable per-install label, logged with USDA calls so
                       // dev-phase budget usage is attributable per device
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
