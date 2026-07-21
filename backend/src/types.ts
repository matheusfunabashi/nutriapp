/// Worker bindings (see wrangler.toml + secrets).
export interface Env {
  CACHE: KVNamespace;
  DB: D1Database;
  OPENAI_API_KEY?: string;
  USDA_API_KEY?: string;
  EXPLANATION_VERSION?: string;
  SAGE_API_KEY?: string;
}

export interface LookupRequest {
  barcode: string;
  clientTag?: string;
}

export interface SearchRequest {
  query: string;
}

export interface ExplainMultiplierSource {
  source: string;
  selection: string;
  factor: number;
}

export interface ExplainRule {
  rule: string;
  topic: string;
  weight: number;
  fraction: number;
  contribution: number;
  multiplier?: number | null;
  multiplierSources?: ExplainMultiplierSource[] | null;
  evidenceTier: "data" | "unknown-tier";
  driverKind?: "merit" | "hygiene" | string;
}

export interface ExplainContributor {
  topic: string;
  contribution: number;
  evidenceTier: "data" | "unknown-tier";
  potentialLoss?: number | null;
}

export interface ExplainDeltaDriver {
  topic: string;
  direction: "up" | "down" | string;
}

export interface ExplainHardGate {
  kind: string;
  detail: string;
  cappedTo: number;
  intensity?: "full" | "partial" | string;
  bindingCapId?: string;
  shortLabel?: string;
}

export interface ExplainFiredCap {
  id: string;
  value: number;
  shortLabel: string;
  kind: string;
  intensity?: string | null;
}

/// Body of POST /explain — structured v4 scoring context for overview generation.
export interface ExplainRequest {
  barcode: string;
  classHash: string;
  productName?: string;
  objective?: string;
  overall: number;
  your: number;
  band?: string;
  confidence?: number;
  hasScoreableIngredientSignal?: boolean;
  hasNutritionData?: boolean;
  hasIngredientData?: boolean;
  rules?: ExplainRule[];
  topPositive?: ExplainContributor[];
  topNegative?: ExplainContributor[];
  nutrientLevels?: string[];
  deltaValue?: number;
  deltaDrivers?: ExplainDeltaDriver[];
  avoidMatches?: string[];
  detectedAdditives?: string[];
  novaGroup?: number | null;
  hardGate?: ExplainHardGate | null;
  bindingCap?: ExplainFiredCap | null;
  firedCaps?: ExplainFiredCap[];
  /** Overall health cap that limited the universal score (freeSugar / transFat / nns). */
  overallBindingCap?: ExplainFiredCap | null;
  overallFiredCaps?: ExplainFiredCap[];
  knownRuleIds?: string[];
  nutrientNudge?: number | null;
  nutrientNudgeDriver?: string | null;
}

export type OverviewContext = ExplainRequest;
