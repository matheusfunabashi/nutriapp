#!/usr/bin/env python3
"""Annotate alternatives.json candidates with an image_quality verdict.

For each candidate, fetches the image the app will actually display — the
Worker pack-shot slot (`/images/{barcode}`), falling back to the dataset's
OFF url — and classifies it:

  good    — pack-shot-like: clean/light border, adequate resolution
  low     — busy background (user photo), tiny, or very dark
  missing — neither URL yields a decodable image

Top Rated fills its list from `good` first, so community kitchen-counter
photos stop reaching the top 10 while the data still ships (detail screens
and alternatives keep working regardless of verdict).

Run after TopRatedBuilder, before installing:
  .venv with Pillow required, e.g.:
  python3 -m venv .imgenv && .imgenv/bin/pip install pillow
  .imgenv/bin/python annotate_image_quality.py fixtures/alternatives.json
"""
import io, json, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

BACKEND = "https://sage-backend.sage-app1710.workers.dev"
IMAGE_CACHE_VERSION = 4

MIN_LONGEST_SIDE = 200          # below this it can't fill a detail header cleanly
BORDER_FRACTION = 0.08          # outer frame sampled for background analysis
LIGHT_LEVEL = 205               # channel floor for a "light" border pixel
LIGHT_BORDER_MIN = 0.60         # ≥60% light border → studio background
UNIFORM_STD_MAX = 22.0          # or a very uniform border of any color

# Tiers whose images are catalog pack shots by construction. Provenance beats
# pixels: the border heuristic below assumes a margin of background around the
# product, but retailer shots are often cropped tight to the package (an
# 800×800 Nature Valley box fills the frame, so its "border" is the box), which
# the heuristic would wrongly call a user photo. Only community-uploaded OFF
# images need pixel screening.
TRUSTED_SOURCES = {"curated", "kroger", "walmart", "goupc"}


def fetch(url, timeout=25):
    """Bytes, or None. See fetch_with_source when provenance matters."""
    return fetch_with_source(url, timeout)[0]


def fetch_with_source(url, timeout=25):
    """(bytes|None, source|None) — source from the Worker's X-Sage-Image-Source."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Sage-ImageQA/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            if r.status != 200:
                return None, None
            return r.read(), r.headers.get("X-Sage-Image-Source")
    except Exception:
        return None, None


def classify(data):
    """'good' | 'low' for decodable bytes, None if undecodable."""
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except Exception:
        return None

    w, h = img.size
    if max(w, h) < MIN_LONGEST_SIDE:
        return "low"

    # Curated cutouts: meaningful transparency = professionally prepared.
    if img.mode in ("RGBA", "LA", "PA"):
        alpha = img.getchannel("A").resize((32, 32))
        if min(alpha.getdata()) < 128:
            return "good"

    rgb = img.convert("RGB")
    rgb.thumbnail((128, 128))
    w, h = rgb.size
    bw, bh = max(1, int(w * BORDER_FRACTION)), max(1, int(h * BORDER_FRACTION))
    px = rgb.load()
    border = []
    for x in range(w):
        for y in list(range(bh)) + list(range(h - bh, h)):
            border.append(px[x, y])
    for y in range(bh, h - bh):
        for x in list(range(bw)) + list(range(w - bw, w)):
            border.append(px[x, y])

    n = len(border)
    light = sum(1 for p in border if min(p) >= LIGHT_LEVEL) / n
    means = [sum(c[i] for c in border) / n for i in range(3)]
    var = sum((c[i] - means[i]) ** 2 for c in border for i in range(3)) / (3 * n)
    std = var ** 0.5

    if light >= LIGHT_BORDER_MIN or std <= UNIFORM_STD_MAX:
        return "good"
    return "low"


def verdict(cand):
    """'good' | 'low' | 'missing' for the image the app will actually show."""
    barcode = str(cand.get("barcode") or "").strip()
    urls = []
    if barcode:
        urls.append(f"{BACKEND}/images/{barcode}?v={IMAGE_CACHE_VERSION}")
    if cand.get("image_url"):
        # The dataset's own OFF url — the app's fallback, community-uploaded.
        urls.append(cand["image_url"])
    for url in urls:
        data, source = fetch_with_source(url)
        if data is None:
            continue
        # A retailer/aggregator tier served it → pack shot by construction;
        # only size disqualifies. Everything else gets pixel screening.
        if source in TRUSTED_SOURCES:
            try:
                img = Image.open(io.BytesIO(data))
                img.load()
            except Exception:
                continue
            return "good" if max(img.size) >= MIN_LONGEST_SIDE else "low"
        result = classify(data)
        if result is not None:
            return result
    return "missing"


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "fixtures/alternatives.json"
    d = json.load(open(path))
    shelves = d.get("shelves", {})
    work = [c for rows in shelves.values() for c in rows]
    print(f"annotating {len(work)} candidates…")
    with ThreadPoolExecutor(8) as ex:
        results = list(ex.map(verdict, work))
    for cand, res in zip(work, results):
        cand["image_quality"] = res
    for shelf in sorted(shelves):
        rows = shelves[shelf]
        counts = {}
        for c in rows:
            counts[c["image_quality"]] = counts.get(c["image_quality"], 0) + 1
        print(f"  {shelf}: {counts}")
    json.dump(d, open(path, "w"), ensure_ascii=False, indent=2)
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
