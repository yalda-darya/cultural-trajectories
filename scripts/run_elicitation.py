#!/usr/bin/env python3
"""
run_elicitation.py — one driver for every model in the panel.

This is the parameterized version of the per-model notebook loop. The point of a
single script is the claim it makes: every model went through the *identical*
pipeline, and only the provider/model/k changed. The per-model differences that
matter (reasoning-off mechanism, streaming, Type C band) live in the runner's client
classes and validator, not here — see src/frozen_mirrors_runner.py and
docs/model_panel.md.

The exact invocations used for the study are recorded in the README and docs/run_log.md.

Behaviour:
  * Resumable. The runner is idempotent (keyed on call_id), so re-running fills only
    gaps. Safe to Ctrl-C and restart, or to re-run after a rate-limit cutoff.
  * Self-healing. Before the loop it strips failed rows (EMPTY / REFUSAL /
    MALFORMED_JSON / api_error) from this leg's existing files, so a resume *refills*
    those calls instead of skipping them as already-done. Disable with --no-clean.

Usage:
  python scripts/run_elicitation.py --provider openai --model gpt-5.5 --k 10
"""
import argparse
import glob
import json
import os
import subprocess
import sys
import time

# The 40-country order, fixed for the study: canary first, then focal cells
# (reversal / directional / stable) so partial completion still yields the analytic
# core, ambiguous residual last. Order does not affect results (idempotent), only
# fail-fast behaviour.
ORDER = [
    "ARG",                                                                  # canary
    "IDN", "IND", "JOR", "JPN", "KOR", "ZWE",                               # reversal (verified)
    "DEU", "THA", "TWN", "CAN", "KGZ", "ROU", "TUR", "SRB", "BRA", "NLD",   # directional
    "RUS", "COL", "PHL", "CYP",                                             # low-change / stable
    "EGY", "IRQ", "MAR", "MYS", "HKG", "CHL", "PAK", "IRN", "CHN", "AUS",
    "UKR", "USA", "NGA", "MEX", "VNM", "NZL", "PER", "URY", "SGP",          # ambiguous residual
]
assert len(ORDER) == len(set(ORDER)) == 40

FAIL_FLAGS = ("EMPTY", "REFUSAL", "MALFORMED_JSON")


def strip_failed(path):
    """Drop retry-worthy failed rows so a resume refills them. Keeps all usable rows
    (incl. NORMALIZED / SUM_SOFT_OVER). Returns count dropped."""
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
    ap.add_argument("--provider", required=True,
                    choices=["anthropic", "openai", "google", "together", "meta"])
    ap.add_argument("--model", required=True, help="API model id")
    ap.add_argument("--k", type=int, default=10, help="draws per cell (default 10)")
    ap.add_argument("--runner", default="src/frozen_mirrors_runner.py")
    ap.add_argument("--spine", default="config/c2_year_spine.csv")
    ap.add_argument("--out-dir", default=None,
                    help="default: data/raw/<provider>_<model-tag>")
    ap.add_argument("--sleep", type=float, default=1.0,
                    help="seconds between countries (eases rate limits)")
    ap.add_argument("--no-clean", action="store_true",
                    help="do NOT strip failed rows before running")
    ap.add_argument("--countries", nargs="+", default=ORDER,
                    help="subset of ISO3s (default: all 40 in study order)")
    args = ap.parse_args()

    tag = f"{args.provider}_{args.model.replace('/', '-')}"
    out_dir = args.out_dir or os.path.join("data", "raw", tag)
    os.makedirs(out_dir, exist_ok=True)

    # --- self-heal: strip failed rows so resume refills them ---
    if not args.no_clean:
        cleaned = 0
        for fp in glob.glob(os.path.join(out_dir, f"results_*_{tag}.jsonl")):
            if fp.endswith(".bak") or any(s in fp for s in ("_PILOT", "_PREPATCH", "_BROKEN")):
                continue
            d = strip_failed(fp)
            if d:
                print(f"[clean] {os.path.basename(fp)}: dropped {d} failed rows")
                cleaned += d
        if cleaned:
            print(f"[clean] {cleaned} failed rows removed; resume will refill them\n")

    # --- run ---
    failed, t0 = [], time.time()
    for i, iso in enumerate(args.countries, 1):
        print(f"\n{'=' * 60}\n[{i}/{len(args.countries)}] {iso}  ({args.provider}/{args.model}, k={args.k})\n{'=' * 60}", flush=True)
        r = subprocess.run(
            [sys.executable, args.runner,
             "--country", iso,
             "--provider", args.provider,
             "--model", args.model,
             "--n-samples", str(args.k),
             "--spine", args.spine,
             "--out-dir", out_dir],
            check=False,
        )
        if r.returncode != 0:
            print(f"  !! {iso} exited {r.returncode} — continuing; re-run to resume.")
            failed.append(iso)
        time.sleep(args.sleep)

    # --- summary ---
    IN = OUT = recs = 0
    for fp in glob.glob(os.path.join(out_dir, f"results_*_{tag}.jsonl")):
        if fp.endswith(".bak") or any(s in fp for s in ("_PILOT", "_PREPATCH", "_BROKEN")):
            continue
        for line in open(fp):
            if not line.strip():
                continue
            u = (json.loads(line).get("usage") or {})
            recs += 1
            IN += u.get("input_tokens", 0)
            OUT += u.get("output_tokens", 0)
    print(f"\n{'=' * 60}\nDONE in {(time.time() - t0) / 60:.1f} min | "
          f"records: {recs:,} | tokens: {IN:,} in / {OUT:,} out")
    print(f"output: {out_dir}/")
    print(f"failed countries: {failed or 'none'}")
    if failed:
        print("  -> re-run the same command to resume (failed rows auto-stripped).")


if __name__ == "__main__":
    main()
