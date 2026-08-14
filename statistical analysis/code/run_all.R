#' # Run the full pipeline
#'
#' Scripts are in dependency order. Each writes its outputs to disk, so once a
#' stage has run you can source any later script alone.
#'
#' Stages 01 and 02 rebuild the coordinate system and rescore the model panel
#' from the raw elicitation files; they need the WVS subset and the elicitation
#' JSONL. If you only have the derived objects (`model_coords.rds`,
#' `country_wave_coords.rds`, `classification.rds`, `c2_year_spine.csv`), set
#' `SKIP_BUILD <- TRUE` and start at stage 03.

SKIP_BUILD <- FALSE

scripts <- c(
  if (!SKIP_BUILD) "R/01_standardization_params.R",
  if (!SKIP_BUILD) "R/02_score_models.R",
  "R/03_snapshot_alignment.R",     # snapshot alignment, C1 and C2
  "R/04_axis_bias_compression.R",  # directional bias, map compression
  "R/05_c0_baseline_relocation.R", # country-agnostic baseline, relocation
  "R/06_implicit_anchor.R",        # which wave the model resembles, and the lag
  "R/07_change_alignment.R",       # rate, direction, drift-free timing signal
  "R/08_reversals.R",              # reversal reproduction, magnitude-guarded
  "R/09_year_prompt_effect.R",     # temporal steerability
  "R/10_figures.R"
)

for (s in scripts) {
  cat("\n\n", strrep("=", 78), "\n>>> ", s, "\n", strrep("=", 78), "\n", sep = "")
  source(s, echo = FALSE)
}

cat("\n\npipeline complete\n")
sessionInfo()
