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
