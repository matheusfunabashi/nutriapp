#!/usr/bin/env python3
"""Measure real Go-UPC coverage before committing to a paid plan.

Samples candidates from alternatives.json whose current image is `low` or
`missing` — the actual gap the tier is meant to close — looks each up through
the Go-UPC API, and reports the hit rate plus how many returned images our
own quality classifier would accept.

Usage (needs a venv with Pillow, same one annotate_image_quality.py uses):
  GOUPC_API_KEY=... .imgenv/bin/python check_goupc_coverage.py [--n 40] \
      [--market us] [--file fixtures/alternatives.json]

Costs one lookup per sampled barcode — a trial key's quota is plenty for
`--n 40`. Stays under Go-UPC's documented 2 req/s ceiling.
"""
import argparse, json, os, random, sys, time, urllib.error, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from annotate_image_quality import classify, fetch as fetch_bytes  # noqa: E402

API = "https://go-upc.com/api/v1/code/"
REQUEST_GAP_SECONDS = 0.6  # < 2 req/s


def lookup(code, key):
    """(status, product dict|None) for one barcode."""
    req = urllib.request.Request(
        f"{API}{code}",
        headers={"Authorization": f"Bearer {key}", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception as e:
        print(f"  ! transport error: {e}", file=sys.stderr)
        return 0, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default="fixtures/alternatives.json")
    ap.add_argument("--n", type=int, default=40)
    ap.add_argument("--market", default="us", help="market filter, or 'any'")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    key = os.environ.get("GOUPC_API_KEY")
    if not key:
        print("set GOUPC_API_KEY", file=sys.stderr)
        sys.exit(1)

    d = json.load(open(args.file))
    gap = []
    for shelf, rows in d.get("shelves", {}).items():
        for c in rows:
            if c.get("image_quality") not in ("low", "missing"):
                continue
            countries = c.get("countries") or []
            if args.market != "any" and args.market not in countries:
                continue
            gap.append({
                "shelf": shelf, "barcode": c["barcode"],
                "name": f"{c.get('brand') or ''} {c['name']}".strip(),
            })

    if not gap:
        print("no gap candidates — run annotate_image_quality.py first?")
        return
    random.seed(args.seed)
    sample = random.sample(gap, min(args.n, len(gap)))
    print(f"{len(gap)} gap candidates (market={args.market}); sampling {len(sample)}\n")

    found = with_image = good_image = 0
    inferred = 0
    for i, s in enumerate(sample, 1):
        status, body = lookup(s["barcode"], key)
        if status == 429:
            print("  ! quota/rate limit hit — stopping early", file=sys.stderr)
            break
        if status in (401, 403):
            print("  ! key rejected", file=sys.stderr)
            sys.exit(1)

        product = (body or {}).get("product") or {}
        is_inferred = bool((body or {}).get("inferred"))
        url = (product.get("imageUrl") or "").strip()
        verdict = "-"
        if status == 200 and not is_inferred:
            found += 1
            if url:
                with_image += 1
                data = fetch_bytes(url)
                verdict = classify(data) if data else "unfetchable"
                if verdict == "good":
                    good_image += 1
        if is_inferred:
            inferred += 1
        label = "HIT " if status == 200 and not is_inferred else (
            "infer" if is_inferred else f"{status}")
        print(f"{i:3}. {label:5} img:{'y' if url else 'n'} q:{verdict:11} "
              f"{s['shelf']:12} {s['name'][:44]}")
        time.sleep(REQUEST_GAP_SECONDS)

    n = i
    print(f"\nsampled {n}")
    print(f"  catalog hits      {found}/{n}  ({found / n:.0%})")
    print(f"  with an image     {with_image}/{n}  ({with_image / n:.0%})  <- headline coverage")
    print(f"  passes pixel QA   {good_image}/{n}  ({good_image / n:.0%})  (advisory only)")
    if inferred:
        print(f"  inferred (skipped) {inferred}")
    print(
        "\nNote: the pixel classifier assumes a margin of background around the\n"
        "product and under-counts tight-cropped catalog shots, so 'with an image'\n"
        "is the number to judge coverage by. In the live chain these images are\n"
        "trusted by provenance (X-Sage-Image-Source), not re-screened."
    )


if __name__ == "__main__":
    main()
