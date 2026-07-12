-- App Attest device registrations (keyId + attestation blob until Apple verification lands).

CREATE TABLE IF NOT EXISTS app_attest_devices (
  key_id       TEXT PRIMARY KEY,
  attestation  TEXT NOT NULL,          -- base64 attestation object from the device
  challenge    TEXT NOT NULL,          -- base64 server challenge used during attestation
  verified     INTEGER NOT NULL DEFAULT 0,  -- 1 once validated against Apple
  created_at   TEXT NOT NULL
);
