-- Data-source overhaul (2026-07): scans are unlimited (premium gates top-rated
-- products client-side), App Attest / DeviceCheck removed, and the premium
-- Go-UPC fallback replaced by the free USDA FoodData Central backfill.

-- Free-tier scan counters — no scan limit any more.
DROP TABLE IF EXISTS usage;

-- App Attest device registrations — device identity no longer needed.
DROP TABLE IF EXISTS app_attest_devices;

-- product_meta: drop the Go-UPC ToS-purge flag, add a data-source stamp
-- ('off' | 'usda' | 'off+usda') for observability. USDA is public-domain, so
-- no purge-on-cancel bookkeeping is required.
ALTER TABLE product_meta DROP COLUMN go_upc_fetched;
ALTER TABLE product_meta ADD COLUMN source TEXT;

-- fetch_log.api now carries 'llm' | 'usda' (was 'llm' | 'go_upc'); the column
-- is untyped TEXT so no schema change is needed. Historical 'go_upc' rows are
-- left in place as an audit trail.
