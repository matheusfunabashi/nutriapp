-- Marketing attribution from onboarding ("How did you hear about Sage?").
-- One append-only row per report. No PII — only the option label + a stable
-- per-install clientTag already used by /lookup's USDA backfill log.

CREATE TABLE IF NOT EXISTS attribution (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  source       TEXT NOT NULL,          -- option id, e.g. 'TikTok'
  client_tag   TEXT,                   -- optional install label (ios-xxxxxxxx)
  app_version  TEXT,
  created_at   TEXT NOT NULL            -- ISO-8601 UTC
);

CREATE INDEX IF NOT EXISTS idx_attribution_source ON attribution (source);
CREATE INDEX IF NOT EXISTS idx_attribution_created ON attribution (created_at);
