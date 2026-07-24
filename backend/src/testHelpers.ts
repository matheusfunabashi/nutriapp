/**
 * In-memory stand-ins for Worker bindings used by image-resolution tests.
 * No live network — callers inject a `fetchFn`.
 */

export function mockKV(): KVNamespace {
  const store = new Map<string, { value: string; expiresAt?: number }>();
  const now = () => Date.now();

  return {
    async get(key: string, type?: string) {
      const row = store.get(key);
      if (!row) return null;
      if (row.expiresAt != null && row.expiresAt <= now()) {
        store.delete(key);
        return null;
      }
      if (type === "json") {
        try { return JSON.parse(row.value); } catch { return null; }
      }
      return row.value;
    },
    async put(key: string, value: string, opts?: { expirationTtl?: number }) {
      const expiresAt = opts?.expirationTtl
        ? now() + opts.expirationTtl * 1000
        : undefined;
      store.set(key, { value, expiresAt });
    },
    async delete(key: string) {
      store.delete(key);
    },
    async list() { return { keys: [], list_complete: true, cacheStatus: null }; },
    async getWithMetadata() { return { value: null, metadata: null, cacheStatus: null }; },
  } as unknown as KVNamespace;
}

type R2Obj = {
  body: ArrayBuffer;
  httpMetadata?: { contentType?: string };
  customMetadata?: Record<string, string>;
  size: number;
  httpEtag: string;
};

export function mockR2(): R2Bucket & { _store: Map<string, R2Obj> } {
  const store = new Map<string, R2Obj>();
  const bucket = {
    _store: store,
    async put(key: string, value: ArrayBuffer | ArrayBufferView | string | Blob | ReadableStream,
              opts?: { httpMetadata?: { contentType?: string }; customMetadata?: Record<string, string> }) {
      let bytes: ArrayBuffer;
      if (value instanceof ArrayBuffer) bytes = value;
      else if (ArrayBuffer.isView(value)) {
        bytes = value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength) as ArrayBuffer;
      } else if (typeof value === "string") bytes = new TextEncoder().encode(value).buffer;
      else throw new Error("unsupported put type in mock");
      store.set(key, {
        body: bytes,
        httpMetadata: opts?.httpMetadata,
        customMetadata: opts?.customMetadata,
        size: bytes.byteLength,
        httpEtag: `"${key}-${bytes.byteLength}"`,
      });
      return null;
    },
    async get(key: string) {
      const obj = store.get(key);
      if (!obj) return null;
      return {
        body: obj.body,
        httpMetadata: obj.httpMetadata,
        customMetadata: obj.customMetadata,
        size: obj.size,
        httpEtag: obj.httpEtag,
        async arrayBuffer() { return obj.body; },
      };
    },
    async head(key: string) {
      const obj = store.get(key);
      if (!obj) return null;
      return { size: obj.size, httpEtag: obj.httpEtag, httpMetadata: obj.httpMetadata };
    },
    async delete(key: string) { store.delete(key); },
  };
  return bucket as unknown as R2Bucket & { _store: Map<string, R2Obj> };
}

export function mockEnv(overrides: Partial<{
  CACHE: KVNamespace;
  IMAGES: R2Bucket;
  KROGER_CLIENT_ID: string;
  KROGER_CLIENT_SECRET: string;
}> = {}): import("./types.ts").Env {
  return {
    CACHE: overrides.CACHE ?? mockKV(),
    DB: {} as D1Database,
    IMAGES: overrides.IMAGES ?? mockR2(),
    KROGER_CLIENT_ID: overrides.KROGER_CLIENT_ID ?? "test-client",
    KROGER_CLIENT_SECRET: overrides.KROGER_CLIENT_SECRET ?? "test-secret",
  };
}
