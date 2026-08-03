#!/usr/bin/env python3
"""
qc_strip_failed.py — drop transient-failure rows so a resume refills them.

The runner writes a record for every call, including failures (EMPTY / REFUSAL /
MALFORMED_JSON, or any row carrying an api_error). Because resume is keyed on
call_id, those failed rows would be treated as "done" and skipped forever. Stripping
them removes the call_ids so the next run re-issues exactly those calls.

Safe by construction: only the failure flags above are dropped. All usable rows —
including NORMALIZED and SUM_SOFT_OVER — are kept, as are SUM_OUT_OF_RANGE rows
(those are a normalization decision, not a failure). No-op on a clean leg.

(run_elicitation.py does this automatically before each run; this is the standalone
tool for cleaning without launching a run.)

Usage:
  python scripts/qc_strip_failed.py --provider google --model gemini-3.6-flash
  python scripts/qc_strip_failed.py --files "data/raw/**/results_*.jsonl"
"""
import argparse
import glob
import json
import os
import sys

FAIL_FLAGS = ("EMPTY", "REFUSAL", "MALFORMED_JSON")
SKIP = (".bak",)
SKIP_SUBSTR = ("_PILOT", "_PREPATCH", "_BROKEN")


def strip_failed(path):
    rows = [json.loads(l) for l in open(path) if l.strip()]
    good = [r for r in rows
            if r.get("flag") not in FAIL_FLAGS and not r.get("api_error")]
    dropped = len(rows) - len(good)
    if dropped:
        with open(path, "w") as fh:
            for r in good:
                fh.write(json.dumps(r) + "\n")
    return dropped


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--provider", help="clean one leg (with --model)")
    ap.add_argument("--model")
    ap.add_argument("--files", help="glob of files to clean (overrides provider/model)")
    ap.add_argument("--raw-dir", default=os.path.join("data", "raw"))
    args = ap.parse_args()

    if args.files:
        paths = glob.glob(args.files, recursive=True)
    elif args.provider and args.model:
        tag = f"{args.provider}_{args.model.replace('/', '-')}"
        paths = glob.glob(os.path.join(args.raw_dir, tag, f"results_*_{tag}.jsonl"))
    else:
        # default: every leg under raw-dir
        paths = glob.glob(os.path.join(args.raw_dir, "*", "results_*.jsonl"))

    if not paths:
        sys.exit("no matching files found")

    total = 0
    for f in sorted(paths):
        if f.endswith(SKIP) or any(s in f for s in SKIP_SUBSTR):
            continue
        d = strip_failed(f)
        if d:
            print(f"{f}: dropped {d}")
            total += d
    print(f"\ncleaned {total} failed rows across {len(paths)} file(s)")
    print("-> re-run the affected leg to refill the dropped calls." if total
          else "-> nothing to clean.")


if __name__ == "__main__":
    main()
