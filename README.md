# Frozen Mirrors

An audit of whether frontier large language models represent national cultures as
**static snapshots** (level alignment) or as **dynamic trajectories of change**
(trajectory fidelity), benchmarked against the World Values Survey (WVS) /
Inglehart–Welzel cultural map across Waves 4–7.

The central distinction: *level alignment* is closeness to a recent cultural
snapshot; *trajectory fidelity* is whether a model reproduces the direction, rate,
and reversals of a society's change over time. Recency anchoring — reproducing a
present-day snapshot regardless of the year asked about — is treated as a **failure
to represent change**, not as evidence of temporal competence.

> Status: elicitation complete for the four-model panel; statistical analysis in progress.
> This repository is the code and data of record for the study. Findings are not yet peer reviewed.

## Research questions

- **RQ1** — Level alignment vs. trajectory fidelity.
- **RQ2** — Implicit temporal anchor and lag (which year a model behaves as if it is describing).
- **RQ3** — Differential temporal fidelity; the focal cell is high-change × low-representation societies.
- **RQ4** — Temporal steerability (whether prompting for a specific year moves the stated distribution).

## Model panel

Four frontier models spanning four labs and both closed and open weights, each run
in a **single-pass (non-reasoning)** configuration so the elicited object is the
model's stated distribution rather than a deliberated one. See
[`docs/model_panel.md`](docs/model_panel.md) for the per-model settings, the exact
mechanism each used to reach single-pass, and the precision/generation caveats.

| Lab | Model | Weights | Single-pass mechanism |
|-----|-------|---------|-----------------------|
| Anthropic | Claude Opus 4.8 | closed | native (no thinking) |
| OpenAI | GPT-5.5 | closed | `reasoning_effort="none"` |
| Google | Gemini 3.6 Flash | closed | `thinking_level="minimal"` (floor, not true off) |
| Alibaba | Qwen3.6-Plus (via Together) | open | `enable_thinking=false` |

Meta was evaluated and **excluded**: its current model (Muse Spark 1.1) is
reasoning-only and cannot be run single-pass, and its non-reasoning line (Llama) is
discontinued. See `docs/model_panel.md` for the full rationale.

## Design (locked)

- **Estimand:** mean stated distribution over **k = 10** default-temperature draws
  per cell. No temperature is sent; each provider's default is used.
- **Conditions:** C0 (no year anchor), C1, C2 (year-anchored). English. No perturbation arms in this phase.
- **Instrument:** ten-indicator core item bank, `PROMPT_VERSION 2026-07-20.1`
  (`config/item_bank_W4toW7.json`). Elicitation asks all ten items every wave; the
  ground-truth side drops items not fielded in a given country-wave.
- **Ground truth:** Inglehart–Welzel two composite dimensions read from underlying
  WVS index scores, Waves 4–7.
- **Countries:** 40 (134 country-waves: 26 three-wave, 14 four-wave), selected on
  representation (high/low) × trajectory profile (directional / stable / reversal / ambiguous).
- **Normalization:** Type A sum band 0.10; Type C sum band 0.30 (applied uniformly
  across all models — see `scripts/reflag_type_c.py` and `docs/schema.md`).

## Repository layout

```
config/     frozen instrument: item bank + country-wave year spine
src/        the runner, pilot analyzer, ground-truth builder
scripts/    orchestration + QC (elicitation loops, completeness, cleaning, reflag)
data/
  raw/            elicitation JSONL, one dir per model (DATA OF RECORD — committed)
  wvs_source/     WVS microdata (.rds) — NOT committed; download separately
  ground_truth/   derived IW dimensions + standardization_params.csv
  derived/        mean distributions, jitter tables, scored outputs
results/    figures/ and tables/
docs/       proposal, pilot report, model panel, JSONL schema, locked decisions
```

## Reproduce

1. `pip install -r requirements.txt` (plus R with the packages noted there for the ground-truth build).
2. Copy `.env.example` to `.env` and fill in the API keys you have. **Never commit `.env`.**
3. Download the WVS trend microdata into `data/wvs_source/` (see that folder's README; the data is not redistributed here).
4. Elicit: `python scripts/run_elicitation.py --provider <lab> --model <id> --k 10`
   (writes idempotent, resumable JSONL to `data/raw/`).
5. QC: `python scripts/qc_completeness.py` then `python scripts/qc_strip_failed.py` on any flagged files; then `python scripts/reflag_type_c.py` across all providers for uniform Type C handling.
6. Ground truth: `Rscript src/build_ground_truth.R`.
7. Score and analyze (see `docs/` for the analysis plan).

## Data, licensing, and citation

- **Elicitation JSONL is primary data.** These models are updated or deprecated over
  time and stochastic elicitation does not regenerate identically, so the committed
  JSONL is the record. A citable snapshot will be deposited to OSF/Zenodo for a DOI;
  see the release linked here once available.
- **WVS microdata is not redistributed.** It carries its own license; obtain it from
  the World Values Survey and place it in `data/wvs_source/`. Only derived aggregates
  (where WVS terms permit) are included here.
- Code is released under the terms in `LICENSE`. Cite via `CITATION.cff`.

## Author

Yalda Daryani — PhD researcher, social psychology, University of Southern California;
research / AI-governance intern, Center for Democracy & Technology.
