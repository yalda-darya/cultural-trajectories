# Accurate in space, unreliable in time

Analysis code for *Accurate in space, unreliable in time: how LLMs represent
national cultural change* (Daryani, Bogen, & Daepp).

We compare four language models' representations of national culture against
repeated World Values Survey measurements of the same societies, separating
**snapshot alignment** (does the model place a society near its most recent
surveyed position?) from **change alignment** (does the model reproduce the
direction, rate, and reversals of that society's path across waves?).

Panel: Claude Opus 4.8, GPT-5.5, Gemini 3.6 Flash, Qwen3.6-Plus.
Ground truth: WVS Waves 4–7, 40 countries, 134 country-waves.

## Running the pipeline

```r
source("run_all.R")
```

Scripts are numbered in dependency order and each writes its outputs to disk,
so any script can be re-run alone once its inputs exist. Each is also
`knitr::spin()`-able into a standalone HTML report:

```r
knitr::spin("R/03_snapshot_alignment.R")
```

## Scripts

| Script | What it does | Writes |
|---|---|---|
| `R/00_setup.R` | Paths, libraries, shared helpers (`ci()`, paired bootstrap, model labels) | — |
| `R/01_standardization_params.R` | Freezes the per-item μ, σ, orientation sign, and dimension that define the coordinate system; verifies exact reproduction of the saved ground-truth coordinates | `standardization_params.csv` |
| `R/02_score_models.R` | Reads the elicitation JSONL, collapses k=10 replicates per cell, converts stated distributions to WVS-comparable item values, and projects them onto the IW axes using the survey's own scoring rule | `model_cells_long.rds`, `model_item_values.rds`, `item_base_by_country.csv`, `model_coords.rds` |
| `R/03_snapshot_alignment.R` | Distance from each model's coordinate to the country's most recent surveyed position, under C1 and C2, with paired country bootstrap, pairwise model differences, and per-country placement error | `c2_matched.rds`, `level_bootstrap.rds` |
| `R/04_axis_bias_compression.R` | Signed per-axis bias and cross-country spread ratios (model SD / truth SD), bootstrapped, under both conditions | `axis_bias_spread.rds` |
| `R/05_c0_baseline_relocation.R` | The country-agnostic C0 baseline, how far naming the country relocates the answer, and which societies the default answer already resembles | `c0_relocation.rds` |
| `R/06_implicit_anchor.R` | Which survey wave each model's unprompted (C1) placement most resembles, and the resulting lag in years and in wave-steps | `implicit_anchor.rds` |
| `R/07_change_alignment.R` | Net displacement (rate and direction), step-level alignment against a shuffled-year permutation null, and the bootstrapped drift-free timing signal | `trajectory_net.rds`, `trajectory_stepcos.rds` |
| `R/08_reversals.R` | Turn angles at each path vertex for truth and models, the true bend wave, and reproduction guarded by a step-magnitude criterion | `reversal_turns.rds`, `reversal_hits.rds` |
| `R/09_year_prompt_effect.R` | Whether naming the fieldwork year moves a model's placement toward that year's true position | `year_prompt_effect.rds` |
| `R/10_figures.R` | Anchor curve and lag distribution figures | `RQ2_anchor_curve.pdf`, `RQ2_lag_distribution.pdf` |

## Inputs not built here

Two upstream artefacts are produced by the ground-truth build and are treated
as given by every script in this repo:

- `WVS_subset_40countries_W4toW7.rds` — WVS trend-file subset. Not
  redistributable; obtain from the World Values Survey Association
  (worldvaluessurvey.org) and subset to the 40 countries in `country_list.csv`.
- `country_wave_coords.rds` — country × wave coordinates on the two
  Inglehart–Welzel dimensions.
- `classification.rds` — trajectory class per country (directional, reversal,
  low-change/stable, ambiguous) from the locked two-stage rule.
- `c2_year_spine.csv` — modal fieldwork year per country-wave, used both to date
  trajectories and to fill the year in the C2 prompt.

`R/01_standardization_params.R` verifies that the coordinate system used to
score the models reproduces `country_wave_coords.rds` exactly (max coordinate
difference = 0), which is the check that the two sides of the comparison share
one scale.

## Conventions

- **Resampling unit is the country**, the level at which we generalize. All
  bootstraps use B = 2,000 and `set.seed(42)`, and resample the *same* country
  set across models within each replicate so between-model differences are
  paired.
- **Conditions.** C0 names neither country nor year; C1 names the country only;
  C2 names the country and the fieldwork year of a given wave. Snapshot results
  are reported for C1 with C2 as a matched comparison; the anchor analysis uses
  C1; the change analyses use C2, the only condition matched to the ground truth
  on both country and year.
- **Coordinates** are equal-weight composites of z-scored component items, not
  the published `tradrat5` / `survself` factor scores. This is a deliberate
  standardized-composite proxy: the identical rule can be applied to the model
  side, which is what makes model and survey coordinates directly comparable.
- **Indicator base.** A component is retained for a country only if non-missing
  for more than half of respondents in all of that country's waves. Nine
  countries rest on a reduced base; the model side is restricted to the same
  per-country base so both sides average over the same items.

## Citation

Daryani, Y., Bogen, M., & Daepp, M. (2026). Accurate in space, unreliable in
time: how LLMs represent national cultural change.
