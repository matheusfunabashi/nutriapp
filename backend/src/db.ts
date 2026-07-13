// D1 helpers: product popularity/metadata + external-call log.
//
// No free-tier scan limit any more (scans are unlimited; premium gates
// top-rated products client-side), and no device identity — so the `usage`
// and `app_attest_devices` tables are gone. `fetch_log` now tracks LLM + USDA
// calls; USDA is free but rate-limited (api.data.gov 1000/hr), so logging it
// keeps that budget observable the same way Go-UPC's trial quota was.

/// Bump popularity, record whether the snapshot has an image, and stamp the
/// data source ('off' | 'usda' | 'off+usda') for observability.
export async function bumpScanCount(
  db: D1Database,
  barcode: string,
  hasImage: boolean,
  source: string = "off",
): Promise<void> {
  const now = new Date().toISOString();
  const img = hasImage ? 1 : 0;
  await db
    .prepare(
      `INSERT INTO product_meta (barcode, scan_count, has_off_image, source, updated_at)
       VALUES (?, 1, ?, ?, ?)
       ON CONFLICT(barcode) DO UPDATE SET
         scan_count = scan_count + 1,
         has_off_image = ?,
         source = ?,
         updated_at = ?`,
    )
    .bind(barcode, img, source, now, img, source, now)
    .run();
}

/// Append an external-call record (cost/budget tracking). `usda` is free but
/// rate-limited; `llm` is paid.
export async function logFetch(
  db: D1Database,
  api: "llm" | "usda",
  barcode: string | null,
  reason: string | null,
): Promise<void> {
  await db
    .prepare("INSERT INTO fetch_log (api, barcode, reason, ts) VALUES (?, ?, ?, ?)")
    .bind(api, barcode, reason, new Date().toISOString())
    .run();
}
