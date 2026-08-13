import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  goupcCode,
  fetchGoUPCImage,
  DEFAULT_GOUPC_BASE_URL,
} from "./goupc.ts";

// ---------------------------------------------------------------------------
describe("goupcCode", () => {
  it("passes GTIN lengths through (UPC-A, EAN-13, EAN-8, GTIN-14)", () => {
    assert.equal(goupcCode("012000161155"), "012000161155");
    assert.equal(goupcCode("5000181030938"), "5000181030938");
    assert.equal(goupcCode("20531805"), "20531805");
    assert.equal(goupcCode("00012000161155"), "00012000161155");
  });

  it("strips non-digits", () => {
    assert.equal(goupcCode("012-000-161155"), "012000161155");
  });

  it("rejects codes that are too short or too long", () => {
    assert.equal(goupcCode("1234"), null);
    assert.equal(goupcCode("012000161155999"), null);
    assert.equal(goupcCode(""), null);
  });
});

// ---------------------------------------------------------------------------
describe("fetchGoUPCImage", () => {
  const key = "test-key";

  it("is unavailable without an API key", async () => {
    const r = await fetchGoUPCImage("012000161155", { apiKey: null });
    assert.deepEqual(r, { kind: "unavailable" });
  });

  it("misses malformed codes without spending a lookup", async () => {
    let called = false;
    const r = await fetchGoUPCImage("12", {
      apiKey: key,
      fetchFn: (async () => { called = true; return new Response("{}"); }) as typeof fetch,
    });
    assert.deepEqual(r, { kind: "miss" });
    assert.equal(called, false);
  });

  it("hits with a bearer token and returns the catalog image", async () => {
    let captured: Request | null = null;
    const body = {
      code: "012000161155",
      codeType: "UPC-A",
      product: {
        name: "Sparkling Water",
        brand: "Example",
        imageUrl: "https://go-upc.s3.amazonaws.com/images/457684399.jpeg",
      },
    };
    const r = await fetchGoUPCImage("012000161155", {
      apiKey: key,
      fetchFn: (async (input: RequestInfo | URL, init?: RequestInit) => {
        captured = new Request(input, init);
        return new Response(JSON.stringify(body), { status: 200 });
      }) as typeof fetch,
    });

    assert.equal(r.kind, "hit");
    if (r.kind === "hit") {
      assert.equal(r.image.url, "https://go-upc.s3.amazonaws.com/images/457684399.jpeg");
      assert.equal(r.image.isFrontImage, true);
    }
    const req = captured!;
    assert.equal(req.url, `${DEFAULT_GOUPC_BASE_URL}/code/012000161155`);
    assert.equal(req.headers.get("Authorization"), `Bearer ${key}`);
  });

  it("treats an inferred (guessed) record as a miss", async () => {
    // Go-UPC returns `inferred: true` when it guesses rather than matching its
    // catalog — that image is not reliably *this* product.
    const r = await fetchGoUPCImage("012000161155", {
      apiKey: key,
      fetchFn: (async () => new Response(JSON.stringify({
        inferred: true,
        product: { name: "Guess", imageUrl: "https://go-upc.s3.amazonaws.com/x.jpeg" },
      }), { status: 200 })) as typeof fetch,
    });
    assert.deepEqual(r, { kind: "miss" });
  });

  it("misses when the record carries no usable image", async () => {
    const noImage = async (product: unknown) => fetchGoUPCImage("012000161155", {
      apiKey: key,
      fetchFn: (async () =>
        new Response(JSON.stringify({ product }), { status: 200 })
      ) as typeof fetch,
    });
    assert.deepEqual(await noImage({ name: "No image" }), { kind: "miss" });
    assert.deepEqual(await noImage({ name: "Blank", imageUrl: "  " }), { kind: "miss" });
    // Non-https URLs are rejected rather than ingested.
    assert.deepEqual(
      await noImage({ name: "Insecure", imageUrl: "http://example.com/a.jpg" }),
      { kind: "miss" },
    );
  });

  it("maps status codes: 404/400 miss, 401/403 unavailable, 429/5xx rate limited", async () => {
    const respond = (status: number) =>
      fetchGoUPCImage("012000161155", {
        apiKey: key,
        fetchFn: (async () => new Response("", { status })) as typeof fetch,
      });
    assert.deepEqual(await respond(404), { kind: "miss" });
    assert.deepEqual(await respond(400), { kind: "miss" });
    // A rejected key must not be retried per-barcode.
    assert.deepEqual(await respond(401), { kind: "unavailable" });
    assert.deepEqual(await respond(403), { kind: "unavailable" });
    assert.equal((await respond(429)).kind, "rate_limited");
    assert.equal((await respond(503)).kind, "rate_limited");
  });

  it("treats a transport error as rate limited (backoff, not a permanent miss)", async () => {
    const r = await fetchGoUPCImage("012000161155", {
      apiKey: key,
      fetchFn: (async () => { throw new Error("network down"); }) as typeof fetch,
    });
    assert.equal(r.kind, "rate_limited");
  });
});
