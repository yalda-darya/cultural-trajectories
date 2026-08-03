#!/usr/bin/env python3
"""
qc_completeness.py — is a leg (or every leg) fully and cleanly run?

"Complete" here means, for each country: the file exists, every expected
(condition x item x wave) cell is present, each cell has exactly k records, and no
rows are transient failures. Completeness (did every call run) is checked separately
from usability (how many parsed cleanly) — a dropped SUM_OUT_OF_RANGE draw is a
quality note, not an incompleteness.

Expectations are derived from the locked instrument, so this can't drift from it:
  * which countries and how many waves each has  -> config/c2_year_spine.csv
  * how many items, and how many are dropped in C0 -> config/item_bank_W4toW7.json

Expected cells per country = (n_items - n_excluded_from_C0)   # C0
                           +  n_items                          # C1
                           +  n_items * n_waves                # C2 (one per wave)

Usage:
  python scripts/qc_completeness.py                       # scan every leg in data/raw/
  python scripts/qc_completeness.py --provider openai --model gpt-5.5
Exit code is non-zero if any problem is found (so it can gate a commit or a resume).
"""
import argparse
import csv
import glob
import json
import os
import sys
from collections import Counter

FAIL_FLAGS = ("EMPTY", "REFUSAL", "MALFORMED_JSON")


def load_spine(path):
    waves = Counter()
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            waves[row["country"]] += 1
    return dict(waves)


def load_bank_counts(path):
    bank = json.load(open(path))
    items = bank["items"]
    n_items = len(items)
    n_excl = sum(1 for it in items if it.get("excluded_from_C0"))
    return n_items, n_excl


def check_leg(raw_dir, tag, waves, n_items, n_excl, k):
    """Return (n_ok, list_of_problem_strings) for one provider_model leg."""
    problems, n_ok = [], 0
    for iso, nw in sorted(waves.items()):
        f = os.path.join(raw_dir, tag, f"results_{iso}_{tag}.jsonl")
        if not os.path.exists(f):
            problems.append(f"{iso}: MISSING — never ran")
            continue
        rows = [json.loads(l) for l in open(f) if l.strip()]
        failed = sum(1 for r in rows
                     if r.get("flag") in FAIL_FLAGS or r.get("api_error"))
        cells = Counter((r["condition"], r["item_id"], r["wave"]) for r in rows)
        expected_cells = (n_items - n_excl) + n_items + n_items * nw
        underfilled = sum(1 for c in cells.values() if c < k)
        overfilled = sum(1 for c in cells.values() if c > k)

        issues = []
        if failed:
            issues.append(f"{failed} failed rows -> strip & resume")
        if len(cells) != expected_cells:
            issues.append(f"{len(cells)}/{expected_cells} cells present")
        if underfilled:
            issues.append(f"{underfilled} cells < k={k}")
        if overfilled:
            issues.append(f"{overfilled} cells > k (duplicates?)")
        if issues:
            problems.append(f"{iso}: " + "; ".join(issues))
        else:
            n_ok += 1
    return n_ok, problems


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--provider", help="check one leg (with --model); omit to scan all")
    ap.add_argument("--model")
    ap.add_argument("--k", type=int, default=10)
    ap.add_argument("--spine", default="config/c2_year_spine.csv")
    ap.add_argument("--bank", default="config/item_bank_W4toW7.json")
    ap.add_argument("--raw-dir", default=os.path.join("data", "raw"))
    args = ap.parse_args()

    waves = load_spine(args.spine)
    n_items, n_excl = load_bank_counts(args.bank)

    if args.provider and args.model:
        tags = [f"{args.provider}_{args.model.replace('/', '-')}"]
    else:
        tags = sorted(os.path.basename(d) for d in glob.glob(os.path.join(args.raw_dir, "*"))
                      if os.path.isdir(d))
        if not tags:
            sys.exit(f"no legs found under {args.raw_dir}/ (expected <provider>_<model> subdirs)")

    any_problem = False
    for tag in tags:
        print(f"\n===== {tag} =====")
        n_ok, problems = check_leg(args.raw_dir, tag, waves, n_items, n_excl, args.k)
        for p in problems:
            print(" ", p)
        total = len(waves)
        if problems:
            any_problem = True
            print(f"  -> {n_ok}/{total} clean; {len(problems)} need attention")
        else:
            print(f"  all {total} complete and clean")

    sys.exit(1 if any_problem else 0)


if __name__ == "__main__":
    main()
