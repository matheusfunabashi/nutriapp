// D1 helpers: free-tier usage, product popularity/metadata, paid-call log.

function utcDay(): string {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
}

/// Returns true if the scan is allowed (and records it), false if over the daily limit.
/// NOTE: deviceId should be a validated App Attest / DeviceCheck identity (TODO).
/// Until then a missing deviceId is allowed through so dev/testing isn't blocked.
export async function checkAndIncrementUsage(
  db: D1Database,
  deviceId: string | undefined,
  limit: number,
): Promise<boolean> {
  if (!deviceId) return true;
  const day = utcDay();

  const row = await db
    .prepare("SELECT count FROM usage WHERE device_id = ? AND day = ?")
    .bind(deviceId, day)
    .first<{ count: number }>();

  if (row && row.count >= limit) return false;

  await db
    .prepare(
      `INSERT INTO usage (device_id, day, count) VALUES (?, ?, 1)
       ON CONFLICT(device_id, day) DO UPDATE SET count = count + 1`,
    )
    .bind(deviceId, day)
    .run();

  return true;
}

/// Bump popularity + record whether OFF had an image (feeds the image-backfill job).
export async function bumpScanCount(
  db: D1Database,
  barcode: string,
  hasImage: boolean,
): Promise<void> {
  const now = new Date().toISOString();
  const img = hasImage ? 1 : 0;
  await db
    .prepare(
      `INSERT INTO product_meta (barcode, scan_count, has_off_image, updated_at)
       VALUES (?, 1, ?, ?)
       ON CONFLICT(barcode) DO UPDATE SET
         scan_count = scan_count + 1,
         has_off_image = ?,
         updated_at = ?`,
    )
    .bind(barcode, img, now, img, now)
    .run();
}

/// Append a paid-call record (for cost tracking + image-backfill counters).
export async function logFetch(
  db: D1Database,
  api: "llm" | "go_upc",
  barcode: string | null,
  reason: string | null,
): Promise<void> {
  await db
    .prepare("INSERT INTO fetch_log (api, barcode, reason, ts) VALUES (?, ?, ?, ?)")
    .bind(api, barcode, reason, new Date().toISOString())
    .run();
}

/// Total Go-UPC calls this calendar month (fallback + image). This is the shared
/// quota usage — premium fallbacks and the image backfill draw from the same pool.
export async function goUpcCallsThisMonth(db: D1Database): Promise<number> {
  const month = new Date().toISOString().slice(0, 7); // YYYY-MM
  const row = await db
    .prepare("SELECT COUNT(*) AS n FROM fetch_log WHERE api = 'go_upc' AND substr(ts, 1, 7) = ?")
    .bind(month)
    .first<{ n: number }>();
  return row ? Number(row.n) : 0;
}

/// Mark a product as Go-UPC-sourced so it can be purged on subscription end (ToS).
export async function markGoUpcSourced(db: D1Database, barcode: string): Promise<void> {
  const now = new Date().toISOString();
  await db
    .prepare(
      `INSERT INTO product_meta (barcode, scan_count, has_off_image, go_upc_fetched, updated_at)
       VALUES (?, 0, 0, 1, ?)
       ON CONFLICT(barcode) DO UPDATE SET go_upc_fetched = 1, updated_at = ?`,
    )
    .bind(barcode, now, now)
    .run();
}

/// Store an App Attest registration blob. Verification against Apple is deferred
/// until DEVICE_CHECK_* secrets are configured on the Worker.
export async function storeAppAttestRegistration(
  db: D1Database,
  keyId: string,
  attestation: string,
  challenge: string,
  verified: boolean,
): Promise<void> {
  const now = new Date().toISOString();
  await db
    .prepare(
      `INSERT INTO app_attest_devices (key_id, attestation, challenge, verified, created_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(key_id) DO UPDATE SET
         attestation = excluded.attestation,
         challenge = excluded.challenge,
         verified = excluded.verified,
         created_at = excluded.created_at`,
    )
    .bind(keyId, attestation, challenge, verified ? 1 : 0, now)
    .run();
}

/// True when the DeviceCheck private key is present — attestation verification can run.
export function deviceCheckConfigured(env: {
  DEVICE_CHECK_TEAM_ID?: string;
  DEVICE_CHECK_KEY_ID?: string;
  DEVICE_CHECK_PRIVATE_KEY?: string;
}): boolean {
  return Boolean(
    env.DEVICE_CHECK_TEAM_ID &&
      env.DEVICE_CHECK_KEY_ID &&
      env.DEVICE_CHECK_PRIVATE_KEY,
  );
}
