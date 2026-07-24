/**
 * Normalize a barcode from OFF (EAN-13 / UPC-A) to the 13-digit GTIN that
 * Kroger's Products API often accepts (zero-padded UPC-A, including check digit).
 *
 * Live API (`api.kroger.com`) returns `productId` / `upc` as 13-digit strings.
 * Many US items use the standard form `0` + UPC-A (e.g. Quaker `0003000001040`).
 * Others omit the UPC check digit and pad with an extra leading zero
 * (e.g. Triscuit scanned `0044000050986` → Kroger `0004400005098`).
 * Callers should try {@link krogerProductIdCandidates} in order.
 */
export function normalizeBarcodeForKroger(raw: string): string | null {
  const digits = String(raw ?? "").replace(/\D/g, "");
  if (!digits) return null;

  if (digits.length === 12) {
    // UPC-A → GTIN-13 with leading zero
    return `0${digits}`;
  }
  if (digits.length === 13) {
    return digits;
  }
  if (digits.length === 14 && digits.startsWith("0")) {
    // GTIN-14 with leading packaging indicator 0
    return digits.slice(1);
  }
  if (digits.length < 12) {
    // Short codes (e.g. truncated scans) — left-pad to 13
    return digits.padStart(13, "0");
  }
  // Longer than 13: keep the trailing 13 digits (common GTIN-14 without leading 0)
  return digits.slice(-13);
}

/**
 * Ordered Kroger `productId` candidates for a scanned / OFF barcode.
 *
 * 1. Standard GTIN-13 (0 + UPC-A with check digit)
 * 2. UPC-A without check digit, left-padded to 13 (Kroger's alternate form)
 *
 * Deduped; empty when the input isn't usable.
 */
export function krogerProductIdCandidates(raw: string): string[] {
  const digits = String(raw ?? "").replace(/\D/g, "");
  if (!digits) return [];

  const out: string[] = [];
  const push = (id: string | null | undefined) => {
    if (id && !out.includes(id)) out.push(id);
  };

  push(normalizeBarcodeForKroger(digits));

  // Alternate: drop UPC-A check digit, pad to 13.
  let upc12: string | null = null;
  if (digits.length === 12) {
    upc12 = digits;
  } else if (digits.length === 13 && digits.startsWith("0")) {
    upc12 = digits.slice(1);
  } else if (digits.length === 14 && digits.startsWith("00")) {
    upc12 = digits.slice(2);
  }
  if (upc12 && upc12.length === 12) {
    push(upc12.slice(0, 11).padStart(13, "0"));
  }

  return out;
}

/**
 * Whether this barcode is worth sending to Kroger.
 *
 * Kroger's catalog is US retail (UPC-A). Zero-padded UPC-A becomes a GTIN-13
 * starting with `0`. Foreign EANs (e.g. Brazilian `789…`) are skipped entirely
 * so we never burn a Products API call that will 404.
 */
export function shouldAttemptKroger(raw: string): boolean {
  const digits = String(raw ?? "").replace(/\D/g, "");
  if (!digits) return false;
  if (digits.length === 12) return true; // UPC-A
  if (digits.length === 13 && digits.startsWith("0")) return true;
  if (digits.length === 14 && digits.startsWith("00")) return true;
  return false;
}
