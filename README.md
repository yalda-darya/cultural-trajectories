# Cultural trajectories: do LLMs represent cultural change?

Code and data of record for **"Accurate in space, unreliable in time: how LLMs
represent national cultural change"** (Daryani, Bogen, & Daepp).

An audit of whether frontier large language models represent national cultures as
**static snapshots** or as **dynamic trajectories of change**, benchmarked against
the World Values Survey (WVS) / Inglehart–Welzel cultural map across Waves 4–7.

The central distinction: *snapshot alignment* is closeness to a recent cultural
position; *change alignment* is whether a model reproduces the direction, rate, and
reversals of a society's movement over time. Recency anchoring — reproducing a
present-day position regardless of the year asked about — is treated as a **failure
to represent change**, not as evidence of temporal competence.

> Status: elicitation and statistical analysis complete; manuscript in preparation.
> Findings are not yet peer reviewed.

## Research questions

- **RQ1** — Snapshot alignment vs. change alignment: does a model place a society
  correctly today while failing to recover how it got there?
- **RQ2** — Implicit temporal anchor and lag: with no year specified, which survey
  wave does a model's placement most resemble?
- **RQ3** — Temporal steerability: does naming a fieldwork year move a model's
  account of a country toward that year's true position?

## Model panel

Four frontier models spanning four labs and both closed and open weights, each run
in a **single-pass (non-reasoning)** configuration so the elicited object is the
model's stated distribution rather than a deliberated one. Per-model settings, the
exact mechanism each used to reach single-pass, and precision caveats are in
[`model_panel.md`](model_panel.md).

| Lab | Model | Weights | Single-pass mechanism |
|-----|-------|---------|-----------------------|
| Anthropic | Claude Opus 4.8 | closed | native (no thinking) |
| OpenAI | GPT-5.5 | closed | `reasoning_effort="none"` |
| Google | Gemini 3.6 Flash | closed | `thinking_level="minimal"` (floor, not true off) |
| Alibaba | Qwen3.6-Plus (via Together) | open | `enable_thinking=false` |

Meta was evaluated and **excluded**: its current model (Muse Spark 1.1) is
reasoning-only and cannot be run single-pass, and its non-reasoning line (Llama) is
discontinued. Full rationale in `model_panel.md`.

## Design (locked)

- **Estimand:** mean stated distribution over **k = 10** default-temperature draws
  per cell. No temperature is sent; each provider's default is used.
- **Conditions:** C0 names neither country nor year (country-agnostic baseline);
  C1 names the country only (unprompted, present-tense representation); C2 names
  the country and the fieldwork year of a given wave. English, no perturbation arms.
- **Instrument:** ten-indicator core item bank, `PROMPT_VERSION 2026-07-20.1`
  (`config/item_bank_W4toW7.json`), decomposed into thirteen component variables —
  eight on Dimension 1, five on Dimension 2. Elicitation asks all ten items every
  wave; the ground-truth side drops items not fielded in a given country-wave.
- **Ground truth:** Inglehart–Welzel two composite dimensions, Waves 4–7, computed
  from the microdata as equal-weight composites of z-scored component items — a
  standardized-composite proxy, not the published `tradrat5` / `survself` factor
  scores. The identical rule is applied to model outputs, which is what makes the
  two directly comparable.
- **Countries:** 40 (134 country-waves: 26 three-wave, 14 four-wave), selected on
  representation (high/low) × trajectory profile (directional / stable / reversal /
  ambiguous).
- **Normalization:** Type A sum band 0.10; Type C sum band 0.30, applied uniformly
  across models (see `schema.md`).
- **Resampling:** bootstrap over **countries**, the unit of generalization, B = 2,000,
  seed 42, with the same resampled country set across models within each replicate
  so between-model comparisons are paired.

## Repository layout

```
cultural-trajectories/
├── README.md
├── LICENSE                          # code license
├── .gitignore
├── .env.example                     # names the keys, holds none of them
├── requirements.txt                 # Python deps
├── sessionInfo.txt                  # R environment of record
├── model_panel.md                   # per-model methods table and exclusions
├── schema.md                        # JSONL record format + flag taxonomy
│
├── config/                          # the FROZEN instrument
│   ├── item_bank_W4toW7.json        # PROMPT_VERSION 2026-07-20.1
│   └── c2_year_spine.csv            # modal fieldwork year per country-wave
│
├── src/
│   ├── runner.py                    # multi-provider elicitation runner
│   └── analyze_pilot.py
│
├── scripts/                         # orchestration + QC
│   ├── run_elicitation.py
│   ├── qc_completeness.py
│   ├── qc_strip_failed.py
│   └── run_log.md
│
├── data/                            # elicitation JSONL, one dir per model
│   ├── anthropic_claude-opus-4-8/
│   ├── google_gemini-3.6-flash/
│   ├── openai_gpt-5.5/
│   └── together_Qwen-Qwen3.6-Plus/
│
└── statistical analysis/
    ├── code/                        # the R pipeline (see below)
    ├── data/                        # derived coordinates, CSV + RDS
    └── output/                      # knitted reports and figures
```

## The statistical pipeline

Scripts in `statistical analysis/code/` are numbered in dependency order. Each
writes its outputs to disk, so any script can be re-run alone once its inputs
exist. Each is also `knitr::spin()`-able into a standalone HTML report.

**Working directory must be `statistical analysis/`**, with the scripts in a
`code/` subfolder — every script calls `source("code/00_setup.R")` and reads its
inputs by bare filename.

| Script | What it does |
|---|---|
| `00_setup.R` | Paths, libraries, shared bootstrap helpers, model labels |
| `01_standardization_params.R` | Freezes the per-item μ, σ, sign, and dimension defining the coordinate system; verifies exact reproduction of the saved coordinates |
| `02_score_models.R` | Reads elicitation JSONL, collapses k=10 replicates, converts stated distributions to WVS-comparable item values, projects onto the IW axes |
| `03_snapshot_alignment.R` | Distance to each country's most recent surveyed position, C1 and C2, with paired bootstrap and per-country error |
| `04_axis_bias_compression.R` | Signed per-axis bias and cross-country spread ratios, both conditions |
| `05_c0_baseline_relocation.R` | Country-agnostic baseline, how far naming the country relocates the answer, which societies the default already resembles |
| `06_implicit_anchor.R` | Which wave the unprompted placement most resembles; lag in years and in wave-steps |
| `07_change_alignment.R` | Net displacement, step-level alignment against a shuffled-year permutation null, drift-free timing signal |
| `08_reversals.R` | Turn angles at each path vertex; reversal reproduction guarded by a step-magnitude criterion |
| `09_year_prompt_effect.R` | Whether naming the fieldwork year improves placement |
| `10_figures.R` | Anchor curve and lag distribution |

Run the whole thing with `source("run_all.R")`.

## Reproduce

1. `pip install -r requirements.txt`. R packages are recorded in `sessionInfo.txt`.
2. Copy `.env.example` to `.env` and fill in the API keys you have. **Never commit `.env`.**
3. Download the WVS trend microdata and place it at the path expected by
   `00_build_ground_truth.R`. The data is not redistributed here.
4. Elicit: `python scripts/run_elicitation.py --provider <lab> --model <id> --k 10`
   (writes idempotent, resumable JSONL to `data/`).
5. QC: `python scripts/qc_completeness.py`, then `python scripts/qc_strip_failed.py`
   on any flagged files.
6. Analysis: from `statistical analysis/`, `source("run_all.R")`.

**Starting from the derived data.** If you don't have the WVS microdata, the
aggregate coordinates in `statistical analysis/data/` are enough to reproduce every
result from script 03 onward. Set `SKIP_BUILD <- TRUE` in `run_all.R`.

## Data, licensing, and citation

- **Elicitation JSONL is primary data.** These models are updated or deprecated over
  time and stochastic elicitation does not regenerate identically, so the committed
  JSONL is the record. A citable snapshot will be deposited to OSF/Zenodo for a DOI.
- **WVS microdata is not redistributed.** It carries its own license; obtain it from
  the World Values Survey Association (worldvaluessurvey.org). Only derived
  aggregates, where WVS terms permit, are included here.
- Code is released under the terms in `LICENSE`.

## Authors

Yalda Daryani — PhD researcher, social psychology, University of Southern California;
research / AI-governance intern, Center for Democracy & Technology.
