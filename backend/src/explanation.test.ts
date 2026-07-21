import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  validateOverview,
  buildTemplateOverview,
} from "./explanation.ts";
import type { ExplainRequest } from "./types.ts";

const noIngredientInput: ExplainRequest = {
  barcode: "7898571520514",
  classHash: "test",
  productName: "Yogurt",
  objective: "eat healthier",
  overall: 43,
  your: 41,
  band: "Mediocre",
  confidence: 0.643,
  hasScoreableIngredientSignal: false,
  hasNutritionData: true,
  hasIngredientData: false,
  deltaValue: -2,
  deltaDrivers: [{ topic: "additives", direction: "down" }],
  rules: [
    {
      rule: "S1",
      topic: "additives",
      weight: 30,
      fraction: 0.2,
      contribution: 6,
      multiplier: 1.3,
      evidenceTier: "unknown-tier",
    },
    {
      rule: "S3",
      topic: "sugar",
      weight: 15,
      fraction: 1,
      contribution: 15,
      evidenceTier: "data",
    },
  ],
  topPositive: [{ topic: "sugar", contribution: 15, evidenceTier: "data" }],
  topNegative: [
    { topic: "additives", contribution: 6, evidenceTier: "unknown-tier", potentialLoss: 24 },
  ],
  nutrientLevels: ["sugar: low (2g)"],
  avoidMatches: [],
  detectedAdditives: [],
};

const confidentInput: ExplainRequest = {
  barcode: "0051500255162",
  classHash: "test",
  productName: "Jif",
  objective: "eat healthier",
  overall: 40,
  your: 39,
  band: "Mediocre",
  confidence: 1,
  hasScoreableIngredientSignal: true,
  hasNutritionData: true,
  hasIngredientData: true,
  deltaValue: -1,
  deltaDrivers: [{ topic: "degree of processing", direction: "down" }],
  rules: [
    {
      rule: "S2",
      topic: "degree of processing",
      weight: 26,
      fraction: 0,
      contribution: 0,
      multiplier: 1.5,
      evidenceTier: "data",
    },
  ],
  topPositive: [],
  topNegative: [
    { topic: "degree of processing", contribution: 0, evidenceTier: "data", potentialLoss: 26 },
  ],
  avoidMatches: ["Seed oils"],
  detectedAdditives: ["Mono- and diglycerides"],
  novaGroup: 4,
  knownRuleIds: ["S1", "S2", "wholeGrain", "flourOxidizers", "dairyLabels", "dairyProcessing"],
};

describe("validateOverview", () => {
  it("rejects additive presence claims when ingredient signal is missing", () => {
    const bad =
      "While this yogurt has good nutrition, the presence of riskier additives lowers its fit.";
    assert.equal(validateOverview(bad, noIngredientInput), "presence of");
  });

  it("accepts uncertainty wording", () => {
    const ok =
      "No ingredient list is available, so the score assumes uncertainty about additives.";
    assert.equal(validateOverview(ok, noIngredientInput), null);
  });

  it("rejects thin-data phrasing when confidence is high", () => {
    const bad =
      "Your score is 1 point below because processing weighs more, especially where data is thin.";
    assert.ok(
      ["data is thin", "where data is thin"].includes(
        validateOverview(bad, confidentInput) ?? ""
      )
    );
  });

  it("rejects em dashes and en dashes", () => {
    assert.equal(
      validateOverview("Held back by processing — ultra-processed.", confidentInput),
      "em dash"
    );
    assert.equal(
      validateOverview("Held back by processing – ultra-processed.", confidentInput),
      "en dash"
    );
  });

  it("rejects 1 points pluralization", () => {
    const bad = "Your score is 1 points below the overall because of processing.";
    assert.equal(validateOverview(bad, confidentInput), "1 points");
  });

  it("rejects internal rule ids and camelCase tokens", () => {
    assert.equal(
      validateOverview("It scores well on flourOxidizers.", confidentInput),
      "flourOxidizers"
    );
    assert.equal(
      validateOverview("Boosted by wholeGrain content.", confidentInput),
      "wholeGrain"
    );
  });

  it("rejects drafts that omit overallBindingCap attribution", () => {
    const capped: ExplainRequest = {
      ...confidentInput,
      overall: 35,
      your: 35,
      deltaValue: 0,
      overallBindingCap: {
        id: "freeSugarCeiling",
        value: 35,
        shortLabel: "free sugar",
        kind: "freeSugar",
        intensity: "full",
      },
    };
    assert.equal(
      validateOverview("It scores well on processing.", capped),
      "overallBindingCap"
    );
    assert.equal(
      validateOverview("As a concentrated sugar, its score is capped at 35.", capped),
      null
    );
  });

  it("rejects false list claims naming free sugar", () => {
    const capped: ExplainRequest = {
      ...confidentInput,
      avoidMatches: [],
      firedCaps: [],
      hardGate: null,
      overallBindingCap: {
        id: "freeSugarCeiling",
        value: 35,
        shortLabel: "free sugar",
        kind: "freeSugar",
      },
    };
    assert.match(
      validateOverview("Nice product (also on your list: free sugar).", capped) ?? "",
      /false list claim/
    );
  });

  it("rejects measured micronutrient deficiency when S13 is unknown-tier", () => {
    const input: ExplainRequest = {
      ...confidentInput,
      rules: [
        {
          rule: "S13",
          topic: "micronutrients",
          weight: 8,
          fraction: 0.5,
          contribution: 4,
          evidenceTier: "unknown-tier",
        },
      ],
    };
    assert.equal(
      validateOverview("Held back by micronutrients.", input),
      "micronutrients"
    );
  });
});

describe("buildTemplateOverview", () => {
  it("renders safe fallback for no-ingredient product", () => {
    const text = buildTemplateOverview(noIngredientInput);
    assert.match(text.toLowerCase(), /missing ingredient|can't verify additives|assumes uncertainty/);
    assert.doesNotMatch(text.toLowerCase(), /presence of/);
    assert.match(text, /2 points/);
    assert.doesNotMatch(text, /[\u2013\u2014]/);
  });

  it("mentions avoid match and uses 1 point for confident product", () => {
    const text = buildTemplateOverview(confidentInput);
    assert.match(text.toLowerCase(), /seed oils/);
    assert.match(text, /1 point/);
    assert.doesNotMatch(text.toLowerCase(), /data is thin|provisional|limited data/);
    assert.doesNotMatch(text, /[\u2013\u2014]/);
  });

  it("explains dietConflict hardGate instead of processing formula", () => {
    const gated: ExplainRequest = {
      ...confidentInput,
      overall: 44,
      your: 20,
      deltaValue: -24,
      hardGate: {
        kind: "dietConflict",
        detail: "conflicts with your low-sugar diet, which caps Your Score at 20",
        cappedTo: 20,
        intensity: "full",
        bindingCapId: "dietConflictCap",
        shortLabel: "low-sugar diet",
      },
      bindingCap: {
        id: "dietConflictCap",
        value: 20,
        shortLabel: "low-sugar diet",
        kind: "dietConflict",
        intensity: "full",
      },
      firedCaps: [
        {
          id: "dietConflictCap",
          value: 20,
          shortLabel: "low-sugar diet",
          kind: "dietConflict",
          intensity: "full",
        },
      ],
      deltaDrivers: [
        {
          topic: "conflicts with your low-sugar diet, which caps Your Score at 20",
          direction: "down",
        },
      ],
    };
    const text = buildTemplateOverview(gated);
    assert.match(text.toLowerCase(), /low-sugar|caps your score at 20/);
    assert.doesNotMatch(
      text,
      /weighs degree of processing more heavily, and that's where this product falls short/
    );
  });

  it("does not repeat the points gap parenthetical", () => {
    const input: ExplainRequest = {
      ...confidentInput,
      overall: 50,
      your: 46,
      deltaValue: -4,
      deltaDrivers: [{ topic: "degree of processing", direction: "down" }],
    };
    const text = buildTemplateOverview(input);
    assert.match(text, /4 points/);
    assert.doesNotMatch(text, /points gap/);
    assert.doesNotMatch(text, /\(\d+ points gap\)/);
  });

  it("leads with overallBindingCap and treats negatives as secondary", () => {
    const input: ExplainRequest = {
      ...confidentInput,
      overall: 35,
      your: 35,
      deltaValue: 0,
      overallBindingCap: {
        id: "freeSugarCeiling",
        value: 35,
        shortLabel: "free sugar",
        kind: "freeSugar",
        intensity: "full",
      },
      topPositive: [],
      topNegative: [
        { topic: "degree of processing", contribution: 0, evidenceTier: "data", potentialLoss: 26 },
      ],
    };
    const text = buildTemplateOverview(input);
    assert.match(text.toLowerCase(), /concentrated sugar|capped at 35/);
    assert.match(text.toLowerCase(), /secondary factors/);
    assert.doesNotMatch(text.toLowerCase(), /held back mainly by/);
  });
});
