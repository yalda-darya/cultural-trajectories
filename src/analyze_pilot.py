#!/usr/bin/env python3
"""
analyze_pilot.py — read a Frozen Mirrors results JSONL and report the two things
the pilot exists to tell you, using ONLY the Python standard library.

  (1) MALFORMED-OUTPUT / FLAG RATES, stratified by item_type and condition.

  (2) RUN-TO-RUN JITTER across the k replicates of each cell. IMPORTANT: jitter is
      measured on the quantity that actually enters the composite, not on raw output
      bins:
        - Types A and C  -> the stated distribution IS the estimand; jitter is the
          worst per-option SD across replicates, and the recommended k is set from
          these cells.
        - Type B (card sort) -> the estimand is NOT the 11 raw card percentages (7 of
          which are unused). It is the autonomy sub-composite
              Y003 = (A029 + A039) - (A040 + A042)
          on mention proportions (scored percentage / 100). Reported separately, in
          its own units. Its target is set later against the standardized Dimension-1
          scale (a ground-truth step), so it does NOT drive the pilot's recommended k.

Usage:
    python analyze_pilot.py results_TUR_anthropic_claude-opus-4-8.jsonl
    python analyze_pilot.py results_...jsonl --bank item_bank_W4toW7.json --target-sem 0.01

If --bank is omitted, the card sort falls back to raw-key jitter with a warning.
"""

import argparse, csv, json, math, statistics, sys
from collections import defaultdict, Counter

USABLE = {"OK", "NORMALIZED", "SUM_SOFT_OVER"}
CELL_KEYS = ["country", "condition", "item_id", "item_type", "wave", "year"]
AUTONOMY = ("A029", "A039", "A040", "A042")   # signs +, +, -, -


def load(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    if not rows:
        sys.exit(f"No records in {path}")
    return rows


def load_scored_keys(bank_path):
    """Return {wave:int -> {card_number:str -> component:str}} for the card sort."""
    try:
        bank = json.load(open(bank_path))
    except Exception as e:
        print(f"warning: could not read bank ({e}); card sort will use raw-key jitter.")
        return {}
    for it in bank.get("items", []):
        if it.get("type") == "B":
            return {int(w): d["scored_key"] for w, d in it["deck_by_wave"].items()}
    return {}


def _prop(val, item_type):
    return val / 100.0 if item_type == "B" else val


def cardsort_y003(parsed, scored_key):
    """(A029+A039) - (A040+A042) on mention proportions; None if a component missing."""
    comp = {}
    for cardnum, name in scored_key.items():
        v = parsed.get(str(cardnum))
        if v is None:
            return None
        comp[name] = float(v) / 100.0
    if not all(a in comp for a in AUTONOMY):
        return None
    return (comp["A029"] + comp["A039"]) - (comp["A040"] + comp["A042"])


def percentile(vals, p):
    if not vals:
        return float("nan")
    s = sorted(vals)
    if len(s) == 1:
        return float(s[0])
    k = (len(s) - 1) * (p / 100.0)
    lo, hi = math.floor(k), math.ceil(k)
    if lo == hi:
        return float(s[int(k)])
    return s[lo] * (hi - k) + s[hi] * (k - lo)


def _fmt_table(rows, headers):
    str_rows = [[str(c) for c in r] for r in rows]
    widths = [len(h) for h in headers]
    for r in str_rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(c))
    line = lambda r: "  ".join(str(c).ljust(w) for c, w in zip(r, widths))
    return "\n".join([line(headers), "  ".join("-" * w for w in widths)] +
                     [line(r) for r in str_rows])


def flag_tables(rows):
    print("=" * 72)
    print("(1) MALFORMED-OUTPUT / FLAG RATES")
    print("=" * 72)
    total = len(rows)
    all_flags = sorted({r["flag"] for r in rows})
    for by in ("item_type", "condition"):
        groups = defaultdict(Counter)
        for r in rows:
            groups[r[by]][r["flag"]] += 1
        headers = [by] + all_flags + ["N", "usable_%"]
        table = []
        for g in sorted(groups):
            c = groups[g]; n = sum(c.values())
            usable = sum(c[f] for f in c if f in USABLE)
            table.append([g] + [c.get(f, 0) for f in all_flags] + [n, f"{usable/n*100:.1f}"])
        print(f"\nby {by}:")
        print(_fmt_table(table, headers))
    bad = [r for r in rows if r["flag"] not in USABLE]
    if bad:
        bad_flags = sorted({r["flag"] for r in bad})
        groups = defaultdict(Counter)
        for r in bad:
            groups[r["item_id"]][r["flag"]] += 1
        headers = ["item_id"] + bad_flags + ["N_bad"]
        table = [[g] + [groups[g].get(f, 0) for f in bad_flags] + [sum(groups[g].values())]
                 for g in sorted(groups)]
        print("\nnon-usable records by item_id x flag:")
        print(_fmt_table(table, headers))
    else:
        print("\nno non-usable records.")
    usable_n = sum(1 for r in rows if r["flag"] in USABLE)
    print(f"\noverall usable: {usable_n}/{total} ({usable_n/total*100:.1f}%)")


def jitter_tables(rows, target_sem, out_prefix, scored_keys):
    cells = defaultdict(list)
    meta = {}
    for r in rows:
        if r["flag"] not in USABLE or not r.get("parsed"):
            continue
        key = tuple(r[k] for k in CELL_KEYS)
        cells[key].append(r["parsed"])
        meta[key] = (r["item_type"], r["wave"])

    ac_cells, b_cells, mean_rows = [], [], []
    for key, draws in cells.items():
        itype, wave = meta[key]
        k = len(draws)
        rec = dict(zip(CELL_KEYS, key)); rec["k"] = k

        if itype == "B" and scored_keys:
            sk = scored_keys.get(int(wave), {})
            y = [cardsort_y003(d, sk) for d in draws]
            y = [v for v in y if v is not None]
            if len(y) >= 1:
                m = statistics.fmean(y)
                sd = statistics.stdev(y) if len(y) > 1 else 0.0
                rec.update(y003_mean=round(m, 4), y003_sd=round(sd, 4),
                           y003_sem=round(sd / math.sqrt(len(y)), 4) if len(y) > 1 else 0.0,
                           k_used=len(y))
                b_cells.append(rec)
            for kk in sorted({x for d in draws for x in d}):
                col = [float(d.get(kk, 0.0)) / 100.0 for d in draws]
                mr = dict(zip(CELL_KEYS, key))
                mr.update(option=kk, mean_value=round(statistics.fmean(col) * 100.0, 6), k=k)
                mean_rows.append(mr)
            continue

        allkeys = sorted({kk for d in draws for kk in d})
        sds = []
        for kk in allkeys:
            col = [_prop(float(d.get(kk, 0.0)), itype) for d in draws]
            sds.append(statistics.stdev(col) if k > 1 else 0.0)
            mr = dict(zip(CELL_KEYS, key))
            native = statistics.fmean(col) * (100.0 if itype == "B" else 1.0)
            mr.update(option=kk, mean_value=round(native, 6), k=k)
            mean_rows.append(mr)
        max_sd = max(sds) if sds else 0.0
        rec.update(max_key_sd=round(max_sd, 4),
                   max_key_sem=round(max_sd / math.sqrt(k), 4) if k > 1 else 0.0,
                   k_needed_for_target=int(math.ceil((max_sd / target_sem) ** 2)) if max_sd > 0 else 1)
        ac_cells.append(rec)

    print("\n" + "=" * 72)
    print("(2) RUN-TO-RUN JITTER")
    print("=" * 72)

    if ac_cells:
        ks = sorted({c["k"] for c in ac_cells})
        print(f"\nType A/C cells (estimand = stated distribution): {len(ac_cells)}   k: {ks}")
        by_type = defaultdict(list)
        for c in ac_cells:
            by_type[c["item_type"]].append(c)
        headers = ["item_type", "n_cells", "med_max_sd", "p90_max_sd",
                   "med_k_needed", "max_k_needed"]
        table = []
        for it in sorted(by_type):
            cs = by_type[it]
            sds = [c["max_key_sd"] for c in cs]
            kns = [c["k_needed_for_target"] for c in cs]
            table.append([it, len(cs), round(statistics.median(sds), 4),
                          round(percentile(sds, 90), 4),
                          int(statistics.median(kns)), max(kns)])
        print(f"\nper-key dispersion by item_type (target max-SEM = {target_sem}):")
        print(_fmt_table(table, headers))
        worst = sorted(ac_cells, key=lambda c: c["max_key_sd"], reverse=True)[:6]
        print("\nnoisiest A/C cells:")
        print(_fmt_table([[c["condition"], c["item_id"], c["item_type"], c["wave"],
                           c["max_key_sd"], c["max_key_sem"], c["k_needed_for_target"]]
                          for c in worst],
                         ["condition", "item_id", "type", "wave",
                          "max_key_sd", "max_key_sem", "k_needed"]))
        all_kn = [c["k_needed_for_target"] for c in ac_cells]
        rec_k = max(1, int(math.ceil(percentile(all_kn, 90))))
        print(f"\nRECOMMENDED k (from A/C) = {rec_k}  (90% of A/C cells at max-SEM <= "
              f"{target_sem}; worst {max(all_kn)}). Lock on OSF.")

    if b_cells:
        print("\n" + "-" * 72)
        print("CARD SORT — autonomy sub-composite  Y003 = (A029+A039) - (A040+A042)")
        print("mention-proportion units, range [-2, +2]; 1 of 5 Dimension-1 indicators")
        print("-" * 72)
        table = [[c["condition"], c["wave"], c.get("k_used", c["k"]),
                  c["y003_mean"], c["y003_sd"], c["y003_sem"]]
                 for c in sorted(b_cells, key=lambda c: (c["condition"], c["wave"]))]
        print(_fmt_table(table, ["condition", "wave", "k", "y003_mean", "y003_sd", "y003_sem"]))
        sds = [c["y003_sd"] for c in b_cells]
        print(f"\nY003 replicate SD: median {round(statistics.median(sds),4)}, "
              f"max {round(max(sds),4)}. Judge against Turkey's CROSS-WAVE Y003 movement "
              f"(from the ground truth): jitter matters only relative to the trajectory signal.")
    elif not scored_keys:
        print("\n(card sort scored on raw keys — pass --bank to score Y003 instead)")

    if ac_cells:
        cj = f"{out_prefix}_cell_jitter.csv"
        with open(cj, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(ac_cells[0].keys()))
            w.writeheader(); w.writerows(ac_cells)
        print(f"\nwrote: {cj}  ({len(ac_cells)} A/C cells)")
    if b_cells:
        bj = f"{out_prefix}_cardsort_autonomy.csv"
        with open(bj, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(b_cells[0].keys()))
            w.writeheader(); w.writerows(b_cells)
        print(f"wrote: {bj}  ({len(b_cells)} card-sort cells, Y003)")
    if mean_rows:
        md = f"{out_prefix}_mean_distributions.csv"
        with open(md, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(mean_rows[0].keys()))
            w.writeheader(); w.writerows(mean_rows)
        print(f"wrote: {md}  ({len(mean_rows)} cell-option rows = averaged estimand)")


def main():
    ap = argparse.ArgumentParser(description="Analyze a Frozen Mirrors pilot JSONL.")
    ap.add_argument("results")
    ap.add_argument("--bank", default="item_bank_W4toW7.json",
                    help="item bank, for scoring the card sort to Y003 (default: item_bank_W4toW7.json)")
    ap.add_argument("--target-sem", type=float, default=0.01)
    ap.add_argument("--out-prefix", default=None)
    args = ap.parse_args()

    rows = load(args.results)
    scored_keys = load_scored_keys(args.bank)
    prefix = args.out_prefix or args.results.rsplit(".jsonl", 1)[0]
    flag_tables(rows)
    jitter_tables(rows, args.target_sem, prefix, scored_keys)


if __name__ == "__main__":
    main()
