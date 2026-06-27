-- Sage backend — initial D1 schema.
-- Product snapshots and explanations live in KV; D1 holds counters + logs.

-- Free-tier usage: one row per device per UTC day.
CREATE TABLE IF NOT EXISTS usage (
  device_id TEXT NOT NULL,
  day       TEXT NOT NULL,            -- 'YYYY-MM-DD' (UTC)
  count     INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device_id, day)
);

-- Product popularity + image-backfill metadata (keyed by barcode).
CREATE TABLE IF NOT EXISTS product_meta (
  barcode        TEXT PRIMARY KEY,
  scan_count     INTEGER NOT NULL DEFAULT 0,
  has_off_image  INTEGER NOT NULL DEFAULT 0,   -- 0/1
  go_upc_fetched INTEGER NOT NULL DEFAULT 0,   -- 0/1
  quality_flag   TEXT,                          -- NULL | 'low_quality' | 'ok'
  updated_at     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_product_meta_scan ON product_meta (scan_count DESC);

-- Append-only log of every PAID external call (cost tracking + image counters).
CREATE TABLE IF NOT EXISTS fetch_log (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  api     TEXT NOT NULL,                        -- 'llm' | 'go_upc'
  barcode TEXT,
  reason  TEXT,
  ts      TEXT NOT NULL                         -- ISO-8601 UTC
);
CREATE INDEX IF NOT EXISTS idx_fetch_log_ts ON fetch_log (ts);
