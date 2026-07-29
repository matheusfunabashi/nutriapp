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

/// Allowed onboarding attribution labels — must stay in sync with
/// `OnboardingAttributionOptions` in the iOS app.
export const ATTRIBUTION_SOURCES = [
  "TikTok",
  "Instagram",
  "From a friend",
  "App Store",
  "Other",
] as const;

export type AttributionSource = (typeof ATTRIBUTION_SOURCES)[number];

export function isAttributionSource(value: string): value is AttributionSource {
  return (ATTRIBUTION_SOURCES as readonly string[]).includes(value);
}

/// Append one onboarding attribution event.
export async function recordAttribution(
  db: D1Database,
  source: AttributionSource,
  clientTag: string | null,
  appVersion: string | null,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO attribution (source, client_tag, app_version, created_at)
       VALUES (?, ?, ?, ?)`,
    )
    .bind(source, clientTag, appVersion, new Date().toISOString())
    .run();
}

/// Counts by source for a quick channel breakdown.
export async function attributionSummary(
  db: D1Database,
): Promise<Array<{ source: string; count: number; last_at: string }>> {
  const res = await db
    .prepare(
      `SELECT source, COUNT(*) AS count, MAX(created_at) AS last_at
       FROM attribution
       GROUP BY source
       ORDER BY count DESC`,
    )
    .all<{ source: string; count: number; last_at: string }>();
  return res.results ?? [];
}
