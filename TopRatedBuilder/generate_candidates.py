#!/usr/bin/env python3
"""Generate candidates.json for TopRatedBuilder (ALTERNATIVES_SPEC.md §6).

Per Sage shelf, pulls popularity-ranked products for the shelf's OFF category
tags in one market via the OFF search API — an offline batch (run on ruleset
bumps + ~monthly), NOT the per-scan path — then writes the CandidatesFile shape
TopRatedBuilder consumes. TopRatedBuilder + the on-device engine do the real
data-quality gating; here we only flag a missing image (the one problem the
builder tolerates).

Usage:
  python3 generate_candidates.py [--out candidates.json] [--country us]
                                 [--per-shelf 50] [--shelves juice,yogurt]
"""
import argparse, json, sys, time, urllib.parse, urllib.request, urllib.error

# Shelf id (SageCategory.rawValue) → OFF category tags to pull. Coffee/water are
# intentionally omitted (shelf-excluded / unsupported — SPEC §7).
SHELF_TAGS = {
    "soda":      ["en:sodas"],
    "chocolate": ["en:chocolates"],
    "cookies":   ["en:biscuits"],
    "cereal":    ["en:breakfast-cereals"],
    "cheese":    ["en:cheeses"],
    "yogurt":    ["en:yogurts"],
    "bread":     ["en:breads"],
    "juice":     ["en:fruit-juices"],
    "chips":     ["en:crisps", "en:chips-and-fries"],
    "pasta":     ["en:pastas"],
    "iceCream":  ["en:ice-creams"],
    "babyFood":  ["en:baby-foods"],
}

COUNTRY_TAG = {"us": "en:united-states", "uk": "en:united-kingdom",
               "ca": "en:canada", "au": "en:australia"}

# The per-100g nutriment keys the app's OFFNutriments reads.
NUTRIMENT_KEYS = [
    "sugars_100g", "sodium_100g", "salt_100g", "saturated-fat_100g",
    "trans-fat_100g", "fiber_100g", "proteins_100g", "calcium_100g",
    "caffeine_100g", "energy-kcal_100g", "energy-kj_100g",
    "fruits-vegetables-nuts-estimate-from-ingredients_100g",
    "fruits-vegetables-legumes-estimate-from-ingredients_100g",
    "added-sugars_100g", "iron_100g", "potassium_100g", "magnesium_100g",
    "zinc_100g", "vitamin-c_100g",
]
FIELDS = ("code,product_name,brands,ingredients_text,additives_tags,nutriments,"
          "nutriscore_grade,nova_group,image_front_url,image_url,"
          "categories_tags,labels_tags")

BASE = "https://world.openfoodfacts.org/api/v2/search"


def fetch(tag, country_tag, page_size):
    q = urllib.parse.urlencode({
        "categories_tags": tag, "countries_tags": country_tag,
        "sort_by": "unique_scans_n", "page_size": page_size, "fields": FIELDS,
    })
    url = f"{BASE}?{q}"
    for attempt in range(6):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Sage-TopRated/1.0"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r).get("products", [])
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504):
                time.sleep(min(2 ** attempt, 30)); continue
            raise
        except Exception:
            time.sleep(min(2 ** attempt, 30)); continue
    return []


def nutriments(off):
    n = off.get("nutriments") or {}
    out = {}
    for k in NUTRIMENT_KEYS:
        v = n.get(k)
        if isinstance(v, (int, float)):
            out[k] = v
    return out or None


def entry(off):
    img = off.get("image_front_url") or off.get("image_url")
    problems = [] if img else ["no image"]
    return {
        "barcode": off.get("code"),
        "off_name": off.get("product_name"),
        "off_brands": off.get("brands"),
        "ingredients_text": off.get("ingredients_text") or None,
        "additives_tags": off.get("additives_tags") or [],
        "nutriments": nutriments(off),
        "nutriscore_grade": off.get("nutriscore_grade"),
        "nova_group": off.get("nova_group"),
        "image_url": img,
        "categories_tags": off.get("categories_tags") or [],
        "labels_tags": off.get("labels_tags") or [],
        "data_problems": problems,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="candidates.json")
    ap.add_argument("--country", default="us", choices=list(COUNTRY_TAG))
    ap.add_argument("--per-shelf", type=int, default=50)
    ap.add_argument("--shelves", default="", help="comma-separated subset; default all")
    args = ap.parse_args()

    country_tag = COUNTRY_TAG[args.country]
    shelves = [s for s in args.shelves.split(",") if s] or list(SHELF_TAGS)
    categories = {}
    for shelf in shelves:
        tags = SHELF_TAGS.get(shelf)
        if not tags:
            print(f"! unknown shelf {shelf}", file=sys.stderr); continue
        seen, rows = set(), []
        for tag in tags:
            for off in fetch(tag, country_tag, args.per_shelf):
                code = off.get("code")
                if not code or code in seen:
                    continue
                seen.add(code)
                rows.append(entry(off))
            time.sleep(0.5)
        categories[shelf] = rows
        print(f"{shelf}: {len(rows)} candidates")

    with open(args.out, "w") as f:
        json.dump({"categories": categories}, f, ensure_ascii=False, indent=2)
    print(f"wrote {args.out} ({sum(len(v) for v in categories.values())} total)")


if __name__ == "__main__":
    main()
