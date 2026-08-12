import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  walmartUPC,
  pickWalmartImage,
  fetchWalmartImage,
  DEFAULT_WALMART_BASE_URL,
  type WalmartCredentials,
} from "./walmart.ts";

// ---------------------------------------------------------------------------
describe("walmartUPC", () => {
  it("passes 12-digit UPC-A through", () => {
    assert.equal(walmartUPC("012000161155"), "012000161155");
  });

  it("strips the GTIN-13 leading zero", () => {
    assert.equal(walmartUPC("0012000161155"), "012000161155");
  });

  it("strips GTIN-14 double leading zero", () => {
    assert.equal(walmartUPC("00012000161155"), "012000161155");
  });

  it("left-pads 11 digits (dropped leading zero)", () => {
    assert.equal(walmartUPC("12000161155"), "012000161155");
  });

  it("rejects EAN-13 that is not a zero-padded UPC (e.g. EU Red Bull)", () => {
    assert.equal(walmartUPC("9002490100070"), null);
  });

  it("rejects short/empty codes", () => {
    assert.equal(walmartUPC("1234"), null);
    assert.equal(walmartUPC(""), null);
  });
});

// ---------------------------------------------------------------------------
describe("pickWalmartImage", () => {
  it("prefers the PRIMARY entity's large image", () => {
    const hit = pickWalmartImage({
      largeImage: "https://i5.walmartimages.com/generic-large.jpeg",
      imageEntities: [
        { entityType: "SECONDARY", largeImage: "https://i5.walmartimages.com/side.jpeg" },
        { entityType: "PRIMARY", largeImage: "https://i5.walmartimages.com/front.jpeg" },
      ],
    });
    assert.equal(hit?.url, "https://i5.walmartimages.com/front.jpeg");
    assert.equal(hit?.isFrontImage, true);
    assert.equal(hit?.estimatedWidth, 1000);
  });

  it("falls back to the item-level large image", () => {
    const hit = pickWalmartImage({ largeImage: "https://i5.walmartimages.com/item.jpeg" });
    assert.equal(hit?.url, "https://i5.walmartimages.com/item.jpeg");
  });

  it("falls back to medium when no large exists", () => {
    const hit = pickWalmartImage({ mediumImage: "https://i5.walmartimages.com/m.jpeg" });
    assert.equal(hit?.url, "https://i5.walmartimages.com/m.jpeg");
    assert.equal(hit?.estimatedWidth, 350);
  });

  it("returns null when the item has no images", () => {
    assert.equal(pickWalmartImage({}), null);
  });
});

// ---------------------------------------------------------------------------

async function testCredentials(): Promise<{ creds: WalmartCredentials; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256", modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]) },
    true, ["sign", "verify"],
  ) as CryptoKeyPair;
  const der = await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer;
  const b64 = btoa(String.fromCharCode(...new Uint8Array(der)));
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----`;
  return {
    creds: { consumerId: "test-consumer", privateKeyPem: pem, keyVersion: "2" },
    publicKey: pair.publicKey,
  };
}

describe("fetchWalmartImage", () => {
  it("is unavailable without credentials", async () => {
    const r = await fetchWalmartImage("012000161155", { credentials: null });
    assert.deepEqual(r, { kind: "unavailable" });
  });

  it("misses for non-UPC barcodes without calling the network", async () => {
    const { creds } = await testCredentials();
    let called = false;
    const r = await fetchWalmartImage("9002490100070", {
      credentials: creds,
      fetchFn: (async () => { called = true; return new Response("{}"); }) as typeof fetch,
    });
    assert.deepEqual(r, { kind: "miss" });
    assert.equal(called, false);
  });

  it("hits with signed headers and picks the primary image", async () => {
    const { creds, publicKey } = await testCredentials();
    let captured: Request | null = null;
    const body = {
      items: [{
        upc: "012000161155",
        largeImage: "https://i5.walmartimages.com/item-large.jpeg",
        imageEntities: [
          { entityType: "PRIMARY", largeImage: "https://i5.walmartimages.com/front.jpeg" },
        ],
      }],
    };
    const r = await fetchWalmartImage("0012000161155", {
      credentials: creds,
      now: () => 1_755_000_000_000,
      fetchFn: (async (input: RequestInfo | URL, init?: RequestInit) => {
        captured = new Request(input, init);
        return new Response(JSON.stringify(body), { status: 200 });
      }) as typeof fetch,
    });

    assert.equal(r.kind, "hit");
    if (r.kind === "hit") {
      assert.equal(r.image.url, "https://i5.walmartimages.com/front.jpeg");
    }

    const req = captured!;
    assert.ok(req.url.startsWith(`${DEFAULT_WALMART_BASE_URL}/api-proxy/service/affil/product/v2/items`));
    assert.ok(req.url.includes("upc=012000161155"));
    assert.equal(req.headers.get("WM_CONSUMER.ID"), "test-consumer");
    assert.equal(req.headers.get("WM_CONSUMER.INTIMESTAMP"), "1755000000000");
    assert.equal(req.headers.get("WM_SEC.KEY_VERSION"), "2");

    // The signature must verify over "{consumerId}\n{timestamp}\n{keyVersion}\n".
    const sigB64 = req.headers.get("WM_SEC.AUTH_SIGNATURE")!;
    const sig = Uint8Array.from(atob(sigB64), (c) => c.charCodeAt(0));
    const payload = new TextEncoder().encode("test-consumer\n1755000000000\n2\n");
    const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", publicKey, sig, payload);
    assert.equal(valid, true);
  });

  it("misses on 404 and rate-limits on 429/5xx", async () => {
    const { creds } = await testCredentials();
    const respond = (status: number) =>
      fetchWalmartImage("012000161155", {
        credentials: creds,
        fetchFn: (async () => new Response("", { status })) as typeof fetch,
      });
    assert.deepEqual(await respond(404), { kind: "miss" });
    assert.equal((await respond(429)).kind, "rate_limited");
    assert.equal((await respond(503)).kind, "rate_limited");
  });

  it("misses when the catalog item has no image", async () => {
    const { creds } = await testCredentials();
    const r = await fetchWalmartImage("012000161155", {
      credentials: creds,
      fetchFn: (async () =>
        new Response(JSON.stringify({ items: [{ upc: "012000161155" }] }), { status: 200 })
      ) as typeof fetch,
    });
    assert.deepEqual(r, { kind: "miss" });
  });
});
