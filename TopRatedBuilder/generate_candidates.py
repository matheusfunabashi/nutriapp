#!/usr/bin/env python3
"""Generate candidates.json for TopRatedBuilder (ALTERNATIVES_SPEC.md §6).

Per Sage shelf, pulls popularity-ranked products for the shelf's OFF category
tags in one or more markets via the OFF search API — an offline batch (run on
ruleset bumps + ~monthly), NOT the per-scan path — then writes the CandidatesFile
shape TopRatedBuilder consumes. TopRatedBuilder + the on-device engine do the
real data-quality gating; here we only flag a missing image (the one problem the
builder tolerates).

Each candidate is stamped with `countries` (e.g. ["us"], ["br"], or both when
the same barcode appears in multiple market pulls). TopRatedBuilder keeps the
top 25 *per country* per shelf.

Usage:
  python3 generate_candidates.py [--out candidates.json] [--countries us,br]
                                 [--per-shelf 50] [--shelves juice,yogurt]

Two-country regeneration (default):
  python3 generate_candidates.py --countries us,br --out fixtures/candidates.json
"""
import argparse, json, re, sys, time, urllib.parse, urllib.request, urllib.error

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
    # en:chips-and-fries deliberately not pulled — it is where frozen oven
    # fries come from; the US "chips" shelf means crisps.
    "chips":     ["en:crisps"],
    "pasta":     ["en:pastas"],
    "iceCream":  ["en:ice-creams"],
    "babyFood":  ["en:baby-foods"],
    "nutButtersAndSpreads": [
        "en:peanut-butters", "en:nut-butters", "en:almond-butters",
        "en:hazelnut-spreads", "en:chocolate-spreads",
    ],
    "snackBars": [
        "en:cereal-bars", "en:granola-bars", "en:protein-bars",
    ],
    "milks": [
        "en:milks", "en:plant-milks", "en:almond-milks", "en:oat-milks",
        "en:soy-milks", "en:rice-milks",
    ],
    "fatsAndOils": [
        "en:butters", "en:margarines", "en:olive-oils", "en:vegetable-oils",
        "en:coconut-oils",
    ],
    # en:noodles / en:dried-meals deliberately not pulled — OFF's hierarchy
    # funnels ordinary dry pasta through en:noodles, duplicating the pasta shelf.
    "instantNoodles": ["en:instant-noodles"],
    "energyDrinks": ["en:energy-drinks"],
}

# Shelf id → OFF tags that DISQUALIFY a candidate even though the pull query
# matched it. OFF's category hierarchy is community-tagged and leaks siblings:
# skyr shows up under cheeses, squash concentrate under sodas, coffee creamer
# under plant-milks. A candidate carrying any of these tags is dropped from
# that shelf (it can still appear on its own shelf via its own pull).
SHELF_EXCLUDE = {
    "soda": [
        "en:syrups", "en:concentrates", "en:squashes", "en:kombuchas",
        "en:fruit-juices", "en:energy-drinks", "en:teas", "en:iced-teas",
        "en:waters", "en:tea-based-beverages",
    ],
    "juice": [
        "en:syrups", "en:concentrates", "en:squashes", "en:sodas",
        "en:applesauces", "en:compotes", "en:plant-milks", "en:almond-milks",
    ],
    "milks": [
        "en:creamers", "en:coffee-whiteners", "en:condensed-milks",
        "en:evaporated-milks", "en:milkshakes", "en:protein-shakes",
        "en:meal-replacements",
    ],
    "energyDrinks": [
        "en:waters", "en:flavored-waters", "en:sports-drinks",
        "en:protein-shakes", "en:dairy-drinks", "en:meal-replacements",
    ],
    "cheese": [
        "en:yogurts", "en:skyrs", "en:quarks", "en:sauces", "en:pasta-sauces",
        "en:crisps", "en:salty-snacks", "en:desserts",
    ],
    "yogurt": ["en:cheeses"],
    # US crackers are tagged en:crackers-appetizers, not en:crackers; Ready
    # Brek-style breakfast biscuits carry en:breakfasts.
    "cookies": ["en:crackers", "en:crackers-appetizers", "en:crispbreads",
                "en:breakfast-cereals", "en:breakfasts"],
    "bread": ["en:crispbreads", "en:crackers", "en:bread-crumbs"],
    "cereal": ["en:cereal-bars", "en:granola-bars", "en:biscuits", "en:cookies"],
    "snackBars": ["en:granolas", "en:breakfast-cereals"],
    "pasta": ["en:instant-noodles"],
    # NOTE: instantNoodles must NOT exclude en:pastas or en:soups — OFF's
    # hierarchy puts en:instant-noodles under en:pastas, and real instant ramen
    # (Maruchan, Nissin) legitimately carries en:soups. The name rule below
    # handles noodle-less soup cups. Pulling only en:instant-noodles is the
    # shelf filter.
    "iceCream": ["en:cheeses", "en:fresh-cheeses"],
    "fatsAndOils": ["en:sugars", "en:sweeteners"],
    "chips": ["en:french-fries", "en:frozen-french-fries", "en:frozen-foods"],
}

# Shelf id → product-name regex that disqualifies. Last resort for products
# whose OFF tags carry nothing distinguishing (community mis-tags): protein
# shakes filed as energy drinks, taco shells filed as cookies, split-pea soup
# cups filed as instant noodles.
SHELF_NAME_EXCLUDE = {
    "energyDrinks": re.compile(r"protein|collagen|powder|sticks", re.I),
    "bread": re.compile(r"taco shell|bread ?crumbs|panko", re.I),
    "cookies": re.compile(r"taco shell", re.I),
    "juice": re.compile(r"apple ?sauce", re.I),
    # Still/flavored waters mis-tagged en:sodas ("Organic Lemon Water"). The
    # \b keeps Watermelon sodas alive.
    "soda": re.compile(r"\bwater\b", re.I),
    # Soups without noodles ("Vegan Split Pea Soup") are mis-tagged; noodle
    # soups ("Ramen Noodle Soup") are the genre itself.
    "instantNoodles": re.compile(r"^(?!.*(noodle|ramen)).*soup", re.I | re.S),
}

# Never a beverage regardless of shelf tags ("Original Canola Spray" has been
# seen tagged en:sodas, with all-zero nutrition to boot).
DRINK_NAME_EXCLUDE = re.compile(r"\bspray\b|\boil\b", re.I)

# Shelf id → brand substrings that disqualify (lowercased match). Sports-drink
# and shake brands blanket-tagged as energy drinks; almond milk vandal-tagged
# as squeezed orange juice.
SHELF_BRAND_EXCLUDE = {
    "energyDrinks": ("powerade", "body armor", "bodyarmor", "gatorade",
                     "glaceau", "vitaminwater", "oikos", "vital proteins"),
    "juice": ("almond breeze",),
}

# A "drink" denser than ~150 kcal/100ml is not a drink — heavy cream tops out
# around 100–120; a mis-tagged pizza clocks 238. Applied per 100 g/ml.
DRINK_SHELVES = {"soda", "juice", "milks", "energyDrinks"}
MAX_DRINK_KCAL_100 = 150


def entry_allowed(shelf, e):
    """Shelf-hygiene verdict for a candidate entry (also usable offline)."""
    # Non-English label → drop: the additive detector reads English, so a
    # Turkish cola sails past S1 and "outscores" its US twin, and these rows
    # are OFF countries-tag pollution with foreign pack shots anyway. (Revisit
    # per-market if a non-English market is ever added.)
    lang = e.get("lang")
    if lang not in (None, "en"):
        return False
    if set(SHELF_EXCLUDE.get(shelf, ())) & set(e.get("categories_tags") or ()):
        return False
    name = e.get("off_name") or ""
    rx = SHELF_NAME_EXCLUDE.get(shelf)
    if rx and rx.search(name):
        return False
    brands = (e.get("off_brands") or "").lower()
    if any(b in brands for b in SHELF_BRAND_EXCLUDE.get(shelf, ())):
        return False
    if shelf in DRINK_SHELVES:
        if DRINK_NAME_EXCLUDE.search(name):
            return False
        kcal = (e.get("nutriments") or {}).get("energy-kcal_100g")
        if isinstance(kcal, (int, float)) and kcal > MAX_DRINK_KCAL_100:
            return False
    return True

COUNTRY_TAG = {
    "us": "en:united-states",
    "br": "en:brazil",
    "uk": "en:united-kingdom",
    "ca": "en:canada",
    "au": "en:australia",
}

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
          "categories_tags,labels_tags,lang")

BASE = "https://world.openfoodfacts.org/api/v2/search"


# The API caps page_size at 100; larger pulls page through.
PAGE_SIZE = 100


class PullFailed(Exception):
    """A page still failed after all retries — the caller must not silently
    ship a shelf with a missing market (that is how cereal/us once went to
    production empty)."""


def fetch_page(tag, country_tag, page):
    q = urllib.parse.urlencode({
        "categories_tags": tag, "countries_tags": country_tag,
        "sort_by": "unique_scans_n", "page_size": PAGE_SIZE, "page": page,
        "fields": FIELDS,
    })
    url = f"{BASE}?{q}"
    for attempt in range(8):
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
    raise PullFailed(f"{tag} × {country_tag} page {page} failed after retries")


def fetch(tag, country_tag, per_shelf):
    out = []
    pages = max(1, -(-per_shelf // PAGE_SIZE))  # ceil
    for page in range(1, pages + 1):
        try:
            batch = fetch_page(tag, country_tag, page)
        except PullFailed:
            if out:
                # Page 1 landed; a flaky later page must not void the pull.
                print(f"! {tag} × {country_tag}: page {page} failed, "
                      f"keeping {len(out)} rows", file=sys.stderr)
                break
            raise
        out.extend(batch)
        if len(batch) < PAGE_SIZE:  # last page
            break
        time.sleep(1.0)
    return out[:per_shelf]


def nutriments(off):
    n = off.get("nutriments") or {}
    out = {}
    for k in NUTRIMENT_KEYS:
        v = n.get(k)
        if isinstance(v, (int, float)):
            out[k] = v
    return out or None


def entry(off, country_code):
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
        "lang": off.get("lang"),
        "data_problems": problems,
        "countries": [country_code],
    }


def merge_entry(existing, new):
    """Same barcode in another market → union countries; keep richer fields."""
    countries = sorted(set(existing.get("countries") or []) | set(new.get("countries") or []))
    keep = existing
    # Prefer the row that has an image + ingredients when merging.
    def richness(e):
        return (
            (1 if e.get("image_url") else 0)
            + (1 if e.get("ingredients_text") else 0)
            + (1 if e.get("nutriments") else 0)
        )
    if richness(new) > richness(existing):
        keep = new
    out = dict(keep)
    out["countries"] = countries
    return out


def pull_shelf(shelf, tags, country_code, country_tag, per_shelf):
    seen, rows = set(), []
    dropped = 0
    for tag in tags:
        for off in fetch(tag, country_tag, per_shelf):
            code = off.get("code")
            if not code or code in seen:
                continue
            seen.add(code)
            row = entry(off, country_code)
            if not entry_allowed(shelf, row):
                dropped += 1
                continue
            rows.append(row)
        time.sleep(1.0)
    if dropped:
        print(f"{shelf}/{country_code}: dropped {dropped} off-shelf products "
              f"(shelf hygiene)")
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="candidates.json")
    ap.add_argument("--countries", default="us,br",
                    help="comma-separated market codes (default us,br)")
    ap.add_argument("--country", default="",
                    help="deprecated single-country alias; prefer --countries")
    ap.add_argument("--per-shelf", type=int, default=50)
    ap.add_argument("--shelves", default="", help="comma-separated subset; default all")
    args = ap.parse_args()

    if args.country:
        country_codes = [args.country]
    else:
        country_codes = [c.strip() for c in args.countries.split(",") if c.strip()]
    for c in country_codes:
        if c not in COUNTRY_TAG:
            print(f"! unknown country {c}", file=sys.stderr)
            sys.exit(1)

    shelves = [s for s in args.shelves.split(",") if s] or list(SHELF_TAGS)
    categories = {}
    failures = []
    for shelf in shelves:
        tags = SHELF_TAGS.get(shelf)
        if not tags:
            print(f"! unknown shelf {shelf}", file=sys.stderr); continue
        by_barcode = {}
        for code in country_codes:
            try:
                rows = pull_shelf(shelf, tags, code, COUNTRY_TAG[code], args.per_shelf)
            except PullFailed as e:
                failures.append(f"{shelf}/{code}: {e}")
                print(f"! {shelf}/{code}: PULL FAILED — {e}", file=sys.stderr)
                continue
            if not rows:
                failures.append(f"{shelf}/{code}: 0 rows")
                print(f"! {shelf}/{code}: pulled 0 rows", file=sys.stderr)
            print(f"{shelf}/{code}: {len(rows)} pulled")
            for row in rows:
                bc = row["barcode"]
                if bc in by_barcode:
                    by_barcode[bc] = merge_entry(by_barcode[bc], row)
                else:
                    by_barcode[bc] = row
        categories[shelf] = list(by_barcode.values())
        print(f"{shelf}: {len(categories[shelf])} unique candidates "
              f"({', '.join(country_codes)})")

    with open(args.out, "w") as f:
        json.dump({"categories": categories, "countries": country_codes},
                  f, ensure_ascii=False, indent=2)
    print(f"wrote {args.out} ({sum(len(v) for v in categories.values())} total)")
    if failures:
        # A shelf×market that came back empty must fail the run — shipping it
        # would silently blank that market's shelf (cereal/us, July 2026).
        print("\nPULL FAILURES — do not ship this file:", file=sys.stderr)
        for f_ in failures:
            print(f"  {f_}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
