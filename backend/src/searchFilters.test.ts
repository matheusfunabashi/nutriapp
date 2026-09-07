import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  isAllowedMarket,
  isUnsupportedCategory,
  isScorableForSearch,
  nameRelevance,
  dataRichness,
  offCompleteness,
  rankHits,
} from "./off.ts";

describe("search filters", () => {
  it("requires an English-speaking market (US, UK, or Canada)", () => {
    assert.equal(isAllowedMarket({ countries_tags: ["en:united-states"] }), true);
    assert.equal(isAllowedMarket({ countries_tags: ["en:united-kingdom"] }), true);
    assert.equal(isAllowedMarket({ countries_tags: ["en:canada"] }), true);
    assert.equal(isAllowedMarket({ countries_tags: ["en:brazil"] }), false);
    assert.equal(isAllowedMarket({ countries_tags: ["en:france", "en:united-states"] }), true);
    assert.equal(isAllowedMarket({}), false);
  });

  it("rejects water and alcohol categories", () => {
    assert.equal(isUnsupportedCategory({
      categories_tags: ["en:beverages", "en:waters"],
    }), true);
    assert.equal(isUnsupportedCategory({
      categories_tags: ["en:alcoholic-beverages", "en:beers"],
    }), true);
    assert.equal(isUnsupportedCategory({
      categories_tags: ["en:sodas", "en:soft-drinks"],
    }), false);
    assert.equal(isUnsupportedCategory({
      categories_tags: ["en:drinking-waters"],
    }), true);
  });

  it("scores with ≥3 core nutrients", () => {
    assert.equal(isScorableForSearch({
      nutriments: {
        "energy-kcal_100g": 100,
        "sugars_100g": 5,
        "proteins_100g": 3,
      },
    }), true);
    assert.equal(isScorableForSearch({
      nutriments: { "energy-kcal_100g": 100, "sugars_100g": 5 },
    }), false);
  });

  it("scores with NOVA or additives when nutrition is thin", () => {
    assert.equal(isScorableForSearch({ nova_group: 4 }), true);
    assert.equal(isScorableForSearch({ additives_tags: ["en:e330"] }), true);
    assert.equal(isScorableForSearch({
      ingredients_text: "water, sugar",
    }), false);
  });
});

describe("name relevance", () => {
  it("ranks exact > prefix > word > substring", () => {
    assert.equal(nameRelevance("cheetos", "Cheetos", ""), 100);          // exact name
    assert.equal(nameRelevance("cheetos", "Crunchy", "Cheetos"), 100);   // exact brand
    assert.equal(nameRelevance("cheetos", "Cheetos Crunchy", ""), 90);   // name prefix
    assert.equal(nameRelevance("cheetos", "Crunchy", "Cheetos Snacks"), 80); // brand prefix
    assert.equal(nameRelevance("cheetos", "Flamin Hot Cheetos", ""), 70);    // whole word in name
    assert.equal(nameRelevance("cheetos", "Value Cheetosnacks", ""), 50);    // substring in name
    assert.equal(nameRelevance("cheetos", "Some Dip", "Frito-Lay"), 0);      // no match
  });

  it("is case-insensitive and trims the query", () => {
    assert.equal(nameRelevance("  CHEETOS ", "cheetos", ""), 100);
  });

  it("credits multi-word queries when all tokens are present", () => {
    assert.equal(nameRelevance("hot cheetos", "Cheetos Flamin Hot", ""), 20);
  });
});

describe("data richness", () => {
  it("counts populated data fields 0–5", () => {
    assert.equal(dataRichness({}), 0);
    assert.equal(dataRichness({
      nutriments: {
        "energy-kcal_100g": 100, "sugars_100g": 5, "proteins_100g": 3,
      },
      ingredients_text: "corn, oil, salt",
      additives_tags: ["en:e330"],
      nova_group: 4,
      image_front_url: "https://x/y.jpg",
    }), 5);
  });

  it("ignores an empty ingredients string and thin nutrition", () => {
    assert.equal(dataRichness({
      nutriments: { "energy-kcal_100g": 100, "sugars_100g": 5 },
      ingredients_text: "   ",
    }), 0);
  });
});

describe("offCompleteness", () => {
  it("reads OFF's 0–1 score, defaulting to 0", () => {
    assert.equal(offCompleteness({ completeness: 0.75 }), 0.75);
    assert.equal(offCompleteness({}), 0);
    assert.equal(offCompleteness({ completeness: "bad" }), 0);
  });
});

describe("rankHits", () => {
  const hit = (name: string) => ({
    code: name, name, brand: "", quantity: null, imageURL: null,
  });

  it("orders by relevance, then richness, then completeness", () => {
    const out = rankHits([
      { hit: hit("weak-match-rich"), relevance: 50, richness: 5, completeness: 0.9 },
      { hit: hit("prefix-sparse"),   relevance: 90, richness: 1, completeness: 0.1 },
      { hit: hit("prefix-rich"),     relevance: 90, richness: 4, completeness: 0.5 },
    ]);
    assert.deepEqual(out.map((h) => h.code), [
      "prefix-rich", "prefix-sparse", "weak-match-rich",
    ]);
  });

  it("breaks a relevance+richness tie with completeness", () => {
    const out = rankHits([
      { hit: hit("less-complete"), relevance: 90, richness: 4, completeness: 0.4 },
      { hit: hit("more-complete"), relevance: 90, richness: 4, completeness: 0.8 },
    ]);
    assert.deepEqual(out.map((h) => h.code), ["more-complete", "less-complete"]);
  });
});
