import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { normalizeBarcodeForKroger, shouldAttemptKroger, krogerProductIdCandidates } from "./barcode.ts";
import { pickBestImage, fetchKrogerImage, DEFAULT_KROGER_BASE_URL } from "./kroger.ts";
import {
  resolveProductImage,
  metaKey,
  missKey,
  krogerBackoffKey,
  r2Key,
} from "./imageResolver.ts";
import { mockEnv, mockKV, mockR2 } from "./testHelpers.ts";
import type { OFFProduct } from "./off.ts";

// ---------------------------------------------------------------------------
describe("normalizeBarcodeForKroger", () => {
  it("pads UPC-A (12 digits) with a leading zero", () => {
    assert.equal(normalizeBarcodeForKroger("001111041600"), "0001111041600");
  });

  it("keeps EAN-13 / GTIN-13 as-is", () => {
    assert.equal(normalizeBarcodeForKroger("0001111041600"), "0001111041600");
    assert.equal(normalizeBarcodeForKroger("3017620422003"), "3017620422003");
  });

  it("matches live Kroger Jif UPC format (13-digit zero-padded)", () => {
    assert.equal(normalizeBarcodeForKroger("005150025516"), "0005150025516");
    assert.equal(normalizeBarcodeForKroger("0005150025516"), "0005150025516");
  });

  it("strips GTIN-14 leading zero", () => {
    assert.equal(normalizeBarcodeForKroger("00001111041600"), "0001111041600");
  });

  it("left-pads short numeric codes to 13", () => {
    assert.equal(normalizeBarcodeForKroger("123"), "0000000000123");
  });

  it("strips non-digits and rejects empty", () => {
    assert.equal(normalizeBarcodeForKroger("000-11110-41600"), "0001111041600");
    assert.equal(normalizeBarcodeForKroger(""), null);
    assert.equal(normalizeBarcodeForKroger("abc"), null);
  });
});

// ---------------------------------------------------------------------------
describe("krogerProductIdCandidates", () => {
  it("Triscuit scanned GTIN tries check-digit-stripped Kroger id", () => {
    // App/OFF: 0044000050986 — Kroger productId: 0004400005098
    assert.deepEqual(krogerProductIdCandidates("0044000050986"), [
      "0044000050986",
      "0004400005098",
    ]);
  });

  it("Coke Zero Sugar mini cans scanned string", () => {
    assert.deepEqual(krogerProductIdCandidates("0049000061048"), [
      "0049000061048",
      "0004900006104",
    ]);
  });

  it("Quaker OFF variant maps alt candidate to live Kroger id", () => {
    // Scanned/OFF 0030000010402 → alt 0003000001040 (known Kroger hit)
    assert.deepEqual(krogerProductIdCandidates("0030000010402"), [
      "0030000010402",
      "0003000001040",
    ]);
  });

  it("standard Quaker GTIN keeps primary first", () => {
    assert.deepEqual(krogerProductIdCandidates("0003000001040"), [
      "0003000001040",
      "0000300000104",
    ]);
  });
});

// ---------------------------------------------------------------------------
describe("shouldAttemptKroger", () => {
  it("allows UPC-A and zero-padded GTIN-13", () => {
    assert.equal(shouldAttemptKroger("005150025516"), true);
    assert.equal(shouldAttemptKroger("0005150025516"), true);
    assert.equal(shouldAttemptKroger("0009661901367"), true);
  });

  it("skips Brazilian / foreign EANs (no leading zero)", () => {
    assert.equal(shouldAttemptKroger("7891000100103"), false);
    assert.equal(shouldAttemptKroger("3017620422003"), false);
  });
});

// ---------------------------------------------------------------------------
describe("pickBestImage", () => {
  it("prefers front perspective and largest size ≤ 1000 (xlarge)", () => {
    const hit = pickBestImage([
      {
        perspective: "right",
        sizes: [{ size: "xlarge", url: "https://www.kroger.com/product/images/xlarge/right/0005150025516" }],
      },
      {
        perspective: "front",
        featured: true,
        sizes: [
          { size: "thumbnail", url: "https://www.kroger.com/product/images/thumbnail/front/0005150025516" },
          { size: "small", url: "https://www.kroger.com/product/images/small/front/0005150025516" },
          { size: "medium", url: "https://www.kroger.com/product/images/medium/front/0005150025516" },
          { size: "large", url: "https://www.kroger.com/product/images/large/front/0005150025516" },
          { size: "xlarge", url: "https://www.kroger.com/product/images/xlarge/front/0005150025516" },
        ],
      },
    ]);
    assert.ok(hit);
    assert.equal(hit!.url, "https://www.kroger.com/product/images/xlarge/front/0005150025516");
    assert.equal(hit!.isFrontImage, true);
    assert.equal(hit!.estimatedWidth, 1000);
  });

  it("returns null when images array is empty", () => {
    assert.equal(pickBestImage([]), null);
  });
});

// ---------------------------------------------------------------------------
describe("fetchKrogerImage — token refresh on 401", () => {
  it("drops cached token and retries once after 401", async () => {
    const kv = mockKV();
    await kv.put(
      "kroger:oauth:product.compact",
      JSON.stringify({ access_token: "stale", expires_at: Date.now() + 3_600_000 }),
    );

    let tokenCalls = 0;
    let productCalls = 0;
    const fetchFn = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      assert.ok(url.startsWith(DEFAULT_KROGER_BASE_URL), `unexpected host ${url}`);
      if (url.includes("/connect/oauth2/token")) {
        tokenCalls++;
        return new Response(
          JSON.stringify({ access_token: "fresh", expires_in: 1800, token_type: "bearer" }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      }
      if (url.includes("/v1/products/")) {
        productCalls++;
        const auth = (init?.headers as Record<string, string>)?.Authorization
          ?? (init?.headers instanceof Headers
            ? init.headers.get("Authorization")
            : undefined);
        if (auth === "Bearer stale") {
          return new Response("unauthorized", { status: 401 });
        }
        return new Response(
          JSON.stringify({
            data: {
              productId: "0005150025516",
              upc: "0005150025516",
              images: [{
                perspective: "front",
                featured: true,
                sizes: [{ size: "large", url: "https://www.kroger.com/product/images/large/front/0005150025516" }],
              }],
            },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      }
      return new Response("nope", { status: 404 });
    }) as typeof fetch;

    const result = await fetchKrogerImage("005150025516", {
      kv,
      credentials: { clientId: "id", clientSecret: "secret" },
      baseUrl: DEFAULT_KROGER_BASE_URL,
      fetchFn,
    });

    assert.equal(result.kind, "hit");
    if (result.kind === "hit") {
      assert.equal(result.image.url, "https://www.kroger.com/product/images/large/front/0005150025516");
    }
    assert.equal(tokenCalls, 1);
    assert.equal(productCalls, 2);
  });

  it("treats empty-body 404 as miss (live not-found shape)", async () => {
    const kv = mockKV();
    const fetchFn = (async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/connect/oauth2/token")) {
        return new Response(
          JSON.stringify({ access_token: "tok", expires_in: 1800, token_type: "bearer" }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      }
      return new Response("", { status: 404 });
    }) as typeof fetch;

    const result = await fetchKrogerImage("0004400000323", {
      kv,
      credentials: { clientId: "id", clientSecret: "secret" },
      fetchFn,
    });
    assert.equal(result.kind, "miss");
  });
});

// ---------------------------------------------------------------------------
describe("resolveProductImage chain", () => {
  const origin = "https://sage.test";
  const barcode = "0005150025516";
  const offWithFront: OFFProduct = {
    product_name: "Jif",
    image_front_url:
      "https://images.openfoodfacts.org/images/products/000/515/002/5516/front_en.1.400.jpg",
    images: {
      front_en: { rev: "1", sizes: { full: { w: 800, h: 800 } } },
    },
    selected_images: {
      front: {
        display: {
          en: "https://images.openfoodfacts.org/images/products/000/515/002/5516/front_en.1.400.jpg",
        },
      },
    },
  };

  it("Kroger hit short-circuits OFF", async () => {
    const kv = mockKV();
    const r2 = mockR2();
    const env = mockEnv({ CACHE: kv, IMAGES: r2 });
    const krogerUrl = "https://www.kroger.com/product/images/xlarge/front/0005150025516";
    const bytes = new TextEncoder().encode("KROGER-JPEG").buffer;
    let offDownloadAttempts = 0;

    const fetchFn = (async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/connect/oauth2/token")) {
        return json({ access_token: "tok", expires_in: 1800, token_type: "bearer" });
      }
      if (url.includes("api.kroger.com/v1/products")) {
        return json({
          data: {
            productId: "0005150025516",
            upc: "0005150025516",
            images: [{
              perspective: "front",
              featured: true,
              sizes: [{ size: "xlarge", url: krogerUrl }],
            }],
          },
        });
      }
      if (url === krogerUrl) {
        return new Response(bytes, {
          status: 200,
          headers: { "content-type": "image/jpeg" },
        });
      }
      if (url.includes("openfoodfacts.org")) {
        offDownloadAttempts++;
        return new Response("should-not-fetch", { status: 200 });
      }
      return new Response("nope", { status: 404 });
    }) as typeof fetch;

    const result = await resolveProductImage(env, barcode, offWithFront, {
      origin,
      fetchFn,
      waitUntil: () => {},
    });

    assert.ok(result);
    assert.equal(result!.source, "kroger");
    assert.equal(result!.url, `${origin}/images/${barcode}?v=3`);
    assert.equal(result!.isFrontImage, true);
    assert.equal(offDownloadAttempts, 0);
    assert.ok(r2._store.has(r2Key(barcode)));
    const meta = await kv.get(metaKey(barcode), "json") as { source: string };
    assert.equal(meta.source, "kroger");
  });

  it("Kroger product-without-image falls through to OFF", async () => {
    const kv = mockKV();
    const r2 = mockR2();
    const env = mockEnv({ CACHE: kv, IMAGES: r2 });
    const bytes = new TextEncoder().encode("OFF-JPEG").buffer;

    const fetchFn = (async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/connect/oauth2/token")) {
        return json({ access_token: "tok", expires_in: 1800, token_type: "bearer" });
      }
      if (url.includes("api.kroger.com/v1/products")) {
        return json({ data: { productId: barcode, upc: barcode, images: [] } });
      }
      if (url.includes("front_en.1")) {
        return new Response(bytes, {
          status: 200,
          headers: { "content-type": "image/jpeg" },
        });
      }
      return new Response("nope", { status: 404 });
    }) as typeof fetch;

    const result = await resolveProductImage(env, barcode, offWithFront, {
      origin,
      fetchFn,
      waitUntil: () => {},
    });

    assert.ok(result);
    assert.equal(result!.source, "off");
    const meta = await kv.get(metaKey(barcode), "json") as { source: string };
    assert.equal(meta.source, "off");
  });

  it("total miss returns null and writes negative cache", async () => {
    const kv = mockKV();
    const env = mockEnv({ CACHE: kv, IMAGES: mockR2() });

    const fetchFn = (async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/connect/oauth2/token")) {
        return json({ access_token: "tok", expires_in: 1800, token_type: "bearer" });
      }
      return new Response("", { status: 404 });
    }) as typeof fetch;

    const result = await resolveProductImage(env, barcode, { product_name: "X" }, {
      origin,
      fetchFn,
      waitUntil: () => {},
    });

    assert.equal(result, null);
    assert.equal(await kv.get(missKey(barcode)), "1");

    let calls = 0;
    const blocked = (async () => {
      calls++;
      return new Response("blocked", { status: 500 });
    }) as typeof fetch;
    const again = await resolveProductImage(env, barcode, null, {
      origin,
      fetchFn: blocked,
      waitUntil: () => {},
    });
    assert.equal(again, null);
    assert.equal(calls, 0);
  });

  it("429 from Kroger sets backoff and still uses OFF", async () => {
    const kv = mockKV();
    const r2 = mockR2();
    const env = mockEnv({ CACHE: kv, IMAGES: r2 });
    const bytes = new TextEncoder().encode("OFF").buffer;

    const fetchFn = (async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/connect/oauth2/token")) {
        return json({ access_token: "tok", expires_in: 1800, token_type: "bearer" });
      }
      if (url.includes("api.kroger.com")) {
        return new Response("slow down", { status: 429 });
      }
      if (url.includes("front_en.1")) {
        return new Response(bytes, {
          status: 200,
          headers: { "content-type": "image/jpeg" },
        });
      }
      return new Response("nope", { status: 404 });
    }) as typeof fetch;

    const result = await resolveProductImage(env, barcode, offWithFront, {
      origin,
      fetchFn,
      waitUntil: () => {},
    });

    assert.ok(result);
    assert.equal(result!.source, "off");
    assert.equal(await kv.get(krogerBackoffKey(barcode)), "1");
  });

  it("skips Kroger entirely for Brazilian EAN (no network call)", async () => {
    const br = "7891000100103";
    const kv = mockKV();
    const r2 = mockR2();
    const env = mockEnv({ CACHE: kv, IMAGES: r2 });
    let krogerCalls = 0;
    const bytes = new TextEncoder().encode("OFF-BR").buffer;
    const offProduct: OFFProduct = {
      product_name: "BR product",
      image_front_url:
        "https://images.openfoodfacts.org/images/products/789/100/010/0103/front_pt.1.400.jpg",
      images: {
        front_pt: { rev: "1", sizes: { full: { w: 900, h: 900 } } },
      },
      selected_images: {
        front: {
          display: {
            pt: "https://images.openfoodfacts.org/images/products/789/100/010/0103/front_pt.1.400.jpg",
          },
        },
      },
      lang: "pt",
    };

    const fetchFn = (async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("kroger.com")) {
        krogerCalls++;
        return new Response("should-not-call", { status: 500 });
      }
      if (url.includes("front_pt.1")) {
        return new Response(bytes, {
          status: 200,
          headers: { "content-type": "image/jpeg" },
        });
      }
      return new Response("nope", { status: 404 });
    }) as typeof fetch;

    const result = await resolveProductImage(env, br, offProduct, {
      origin,
      fetchFn,
      preferredLanguages: ["pt", "en"],
      waitUntil: () => {},
    });

    assert.equal(krogerCalls, 0);
    assert.ok(result);
    assert.equal(result!.source, "off");
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
