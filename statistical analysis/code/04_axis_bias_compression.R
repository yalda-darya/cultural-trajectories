#' # 04 — Directional bias and map compression
#'
#' Distance is unsigned, so a model can be accurate on average while sitting
#' systematically off in one direction. This script decomposes the snapshot gap
#' two ways.
#'
#' **Signed per-axis bias** asks whether a model places countries too far toward
#' one pole. A displacement shared across models points to something common to
#' these systems rather than to any one training pipeline; a displacement where
#' models disagree in direction does not.
#'
#' **Spread ratio** asks whether models compress the map — making the world look
#' more uniform by pulling countries toward a common centre. This is the spatial
#' analogue of the flattening argument, and it matters for the paper's claim that
#' models preserve real between-country variation: a model that placed every
#' country at the global mean would post a modest mean distance while destroying
#' the differences the map exists to represent.
#'
#' Both are computed under C1 and C2. The spread bootstrap recomputes *both* SDs
#' inside each replicate, so the interval reflects uncertainty in numerator and
#' denominator rather than treating the ground-truth spread as fixed.
#'
#' **Inputs:** `model_coords.rds`, `country_wave_coords.rds`
#' **Writes:** `axis_bias_spread.rds`

source("R/00_setup.R")

model_coords <- readRDS("model_coords.rds")
coords       <- readRDS("country_wave_coords.rds")

latest_gt <- coords %>%
  transmute(country = as.character(iso), wave = as.numeric(wave),
            gt1 = Dim1, gt2 = Dim2) %>%
  group_by(country) %>% filter(wave == max(wave)) %>% ungroup() %>%
  select(country, gt1, gt2)

#' Build the latest-wave frame for a condition. C2 carries a wave column and is
#' reduced to each country's most recent; C1 has none and is compared directly to
#' the most recent truth.

get_latest <- function(cond) {
  df <- model_coords %>% filter(condition == cond) %>% mutate(country = as.character(country))
  if ("wave" %in% names(df) && any(!is.na(df$wave))) {
    df <- df %>% mutate(wave = as.numeric(wave)) %>%
      group_by(model, country) %>% filter(wave == max(wave, na.rm = TRUE)) %>% ungroup()
  }
  df %>% select(model, country, Dim1, Dim2) %>%
    inner_join(latest_gt, by = "country") %>%
    mutate(d1 = Dim1 - gt1, d2 = Dim2 - gt2)
}

#' Spread ratio: cross-country SD of model coordinates over cross-country SD of
#' the truth, on one axis. Below one is compression, above one expansion.

boot_spread <- function(df, axis) {
  mcol <- if (axis == 1) "Dim1" else "Dim2"
  gcol <- if (axis == 1) "gt1"  else "gt2"
  Wm <- df %>% select(model, country, val = all_of(mcol)) %>%
    pivot_wider(names_from = model, values_from = val) %>% arrange(country)
  G <- df %>% distinct(country, .keep_all = TRUE) %>%
    select(country, gtv = all_of(gcol)) %>% arrange(country)
  stopifnot(identical(Wm$country, G$country))
  M <- as.matrix(Wm[, -1]); g <- G$gtv; n <- nrow(M)
  set.seed(SEED)
  out <- matrix(NA_real_, B, ncol(M), dimnames = list(NULL, colnames(M)))
  for (b in seq_len(B)) {
    idx <- sample.int(n, n, replace = TRUE)
    out[b, ] <- apply(M[idx, , drop = FALSE], 2, sd, na.rm = TRUE) / sd(g[idx], na.rm = TRUE)
  }
  out
}

#' ## Run both conditions
#'
#' Dimension 1 is traditional vs. secular-rational, where a negative bias means
#' the model places countries too far toward the traditional pole. Dimension 2 is
#' survival vs. self-expression, where a positive bias means too far toward
#' self-expression.

res <- list()
for (cond in c("C1", "C2")) {
  df <- get_latest(cond)
  cat(sprintf("\n\n########## CONDITION %s (n countries = %d) ##########\n",
              cond, n_distinct(df$country)))

  b1 <- boot_paired(df, "d1")
  b2 <- boot_paired(df, "d2")
  report_ci(b1, sprintf("%s Dim1 signed bias (- = too traditional)", cond))
  report_pairwise(b1, sprintf("%s Dim1 bias", cond))
  report_ci(b2, sprintf("%s Dim2 signed bias (+ = too self-expressive)", cond))
  report_pairwise(b2, sprintf("%s Dim2 bias", cond))

  s1 <- boot_spread(df, 1)
  s2 <- boot_spread(df, 2)
  report_ci(s1, sprintf("%s Dim1 spread ratio (model SD / truth SD)", cond), vs = 1)
  report_ci(s2, sprintf("%s Dim2 spread ratio (model SD / truth SD)", cond), vs = 1)

  cat(sprintf("\n=== %s raw SDs, model vs truth ===\n", cond))
  df %>% group_by(model) %>%
    summarise(sd_model_D1 = round(sd(Dim1), 3), sd_truth_D1 = round(sd(gt1), 3),
              sd_model_D2 = round(sd(Dim2), 3), sd_truth_D2 = round(sd(gt2), 3),
              .groups = "drop") %>% print()

  res[[cond]] <- list(bias_d1 = b1, bias_d2 = b2, spread_d1 = s1, spread_d2 = s2)
}

saveRDS(res, "axis_bias_spread.rds")
