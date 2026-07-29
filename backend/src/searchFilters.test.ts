import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  isUSProduct,
  isUnsupportedCategory,
  isScorableForSearch,
} from "./off.ts";

describe("search filters", () => {
  it("requires en:united-states", () => {
    assert.equal(isUSProduct({ countries_tags: ["en:united-states"] }), true);
    assert.equal(isUSProduct({ countries_tags: ["en:brazil"] }), false);
    assert.equal(isUSProduct({ countries_tags: ["en:france", "en:united-states"] }), true);
    assert.equal(isUSProduct({}), false);
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
