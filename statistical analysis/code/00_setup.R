#' # Setup
#'
#' Shared configuration for every script in the pipeline: libraries, the
#' elicitation directory, and the helpers that enforce the two conventions the
#' whole analysis rests on — resampling **countries** (the unit we generalize
#' over) and resampling the *same* country set across models within each
#' replicate, so that between-model comparisons are paired rather than inflated
#' by the shared difficulty of particular countries.
#'
#' Source this first; every later script assumes these objects exist.

library(dplyr)
library(tidyr)
library(purrr)
library(readr)

#' ## Paths
#'
#' `ELICITATION_DIR` holds the raw model output, one JSONL per model × country.
#' Everything else is written to and read from the working directory.

ELICITATION_DIR <- Sys.getenv("FM_ELICITATION_DIR", unset = "data/elicitations")

#' ## Constants
#'
#' `B` and `SEED` are fixed across every resampling and permutation procedure in
#' the paper. The locked instrument is thirteen component variables: eight
#' loading on Dimension 1 (traditional vs. secular-rational) and five on
#' Dimension 2 (survival vs. self-expression), each with an orientation sign so
#' that higher values point toward the secular-rational and self-expression
#' poles.

B    <- 2000
SEED <- 42

DIM1_SIGNS <- c(F063 = -1, A029 = +1, A039 = +1, A040 = -1,
                A042 = -1, F120 = +1, G006 = +1, E018 = +1)
DIM2_SIGNS <- c(Y002 = +1, A008 = -1, F118 = +1, E025 = -1, A165 = -1)
SIGNS      <- c(DIM1_SIGNS, DIM2_SIGNS)
ITEMS      <- names(SIGNS)
DIM_OF     <- setNames(c(rep("Dim1", length(DIM1_SIGNS)),
                         rep("Dim2", length(DIM2_SIGNS))), ITEMS)

#' Display names and a colourblind-safe palette, ordered best-to-worst on
#' snapshot accuracy so that tables and figures agree on model order.

MODEL_LEVELS <- c("gemini-3.6-flash", "claude-opus-4-8", "gpt-5.5", "Qwen/Qwen3.6-Plus")
MODEL_PRETTY <- c("gemini-3.6-flash"  = "Gemini 3.6 Flash",
                  "claude-opus-4-8"   = "Claude Opus 4.8",
                  "gpt-5.5"           = "GPT-5.5",
                  "Qwen/Qwen3.6-Plus" = "Qwen3.6-Plus")
MODEL_COLS   <- c("Gemini 3.6 Flash" = "#009E73", "Claude Opus 4.8" = "#D55E00",
                  "GPT-5.5"          = "#0072B2", "Qwen3.6-Plus"    = "#CC79A7")

#' ## Helpers
#'
#' `ci()` returns the 2.5th, 50th, and 97.5th percentiles of a bootstrap
#' distribution. Intervals are reported at the 95% level throughout, and an
#' effect is described as clearing zero when its interval excludes zero.

ci <- function(x, digits = 3) round(quantile(x, c(.025, .5, .975), na.rm = TRUE), digits)

#' `boot_paired()` is the workhorse. It pivots a long `model × country × value`
#' frame into a country × model matrix, then resamples row indices — so every
#' model sees the identical resampled countries in each replicate. `stat` is
#' `mean` for signed biases and distances, `median` for ratio quantities like
#' `mag_ratio` whose distribution is skewed by near-zero denominators.

boot_paired <- function(df, value_col, stat = mean, seed = SEED, B. = B) {
  W <- df %>%
    select(model, country, .val = all_of(value_col)) %>%
    pivot_wider(names_from = model, values_from = .val) %>%
    arrange(country)
  M <- as.matrix(W[, -1]); n <- nrow(M)
  set.seed(seed)
  out <- matrix(NA_real_, B., ncol(M), dimnames = list(NULL, colnames(M)))
  for (b in seq_len(B.)) {
    idx <- sample.int(n, n, replace = TRUE)
    out[b, ] <- apply(M[idx, , drop = FALSE], 2, stat, na.rm = TRUE)
  }
  out
}

#' `report_ci()` prints one interval per model and flags whether it clears a
#' reference value — zero for biases and gaps, one for spread and magnitude
#' ratios.

report_ci <- function(bmat, label, vs = 0, digits = 3) {
  cat(sprintf("\n=== %s ===\n", label))
  g <- t(apply(bmat, 2, ci, digits = digits))
  verdict <- ifelse(g[, 3] < vs, "BELOW", ifelse(g[, 1] > vs, "ABOVE", "n.s."))
  print(data.frame(g, vs_ref = verdict))
  invisible(g)
}

#' `report_pairwise()` takes the differences between every pair of models on the
#' bootstrap distribution itself, which is what makes the comparison paired.

report_pairwise <- function(bmat, label, digits = 3) {
  cat(sprintf("\n=== %s: pairwise difference (row - col), 95%% CI; * = excludes 0 ===\n", label))
  mods <- colnames(bmat); prs <- combn(mods, 2)
  out <- as.data.frame(t(apply(prs, 2, function(p) ci(bmat[, p[1]] - bmat[, p[2]], digits))))
  names(out) <- c("lo2.5", "median", "hi97.5")
  out$sig <- ifelse(sign(out$lo2.5) == sign(out$hi97.5), "*", "")
  rownames(out) <- apply(prs, 2, paste, collapse = "  vs  ")
  print(out)
  invisible(out)
}

#' `latest_wave()` reduces a country-wave frame to each country's most recent
#' observation, which is the target for every snapshot comparison.

latest_wave <- function(df, by_model = TRUE) {
  g <- if (by_model) c("model", "country") else "country"
  df %>% group_by(across(all_of(g))) %>% filter(wave == max(wave)) %>% ungroup()
}
