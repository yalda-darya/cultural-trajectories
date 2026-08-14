#' # 03 — Snapshot alignment
#'
#' Snapshot alignment is the Euclidean distance in the map plane between a
#' model's coordinate for a country and that country's most recent surveyed
#' position. This is the half of cultural evaluation the field already does, and
#' establishing that models do it well is what makes the temporal failure in
#' scripts 06–08 informative rather than a symptom of general incompetence.
#'
#' Reported for **C1** (country named, no year), which carries the model's
#' unprompted present-tense representation, with **C2** (country and fieldwork
#' year) as a matched comparison. Both are computed here so the year effect in
#' script 09 has both sides on identical footing.
#'
#' All forty countries enter. Nine rest on a reduced indicator base and are less
#' precisely estimated; they are retained because the bootstrap generalizes over
#' countries and dropping the least precisely estimated cases would narrow the
#' very variation the interval is meant to capture.
#'
#' **Inputs:** `model_coords.rds`, `country_wave_coords.rds`
#' **Writes:** `c2_matched.rds`, `level_bootstrap.rds`

source("R/00_setup.R")

model_coords <- readRDS("model_coords.rds")
coords       <- readRDS("country_wave_coords.rds")

gt <- coords %>% transmute(country = iso, wave, gt1 = Dim1, gt2 = Dim2)

#' ## The matched backbone
#'
#' For every country-wave, the model's C2 coordinate joined to the true
#' coordinate for that same wave, with signed per-axis gaps and Euclidean
#' distance. Every later change analysis reads from this table, because C2 is the
#' only condition matched to the ground truth on both country and year.

c2_matched <- model_coords %>%
  filter(condition == "C2") %>%
  inner_join(gt, by = c("country", "wave")) %>%
  mutate(d1 = Dim1 - gt1,          # signed gap, tradition–secular
         d2 = Dim2 - gt2,          # signed gap, survival–self-expression
         dist = sqrt(d1^2 + d2^2)) %>%
  select(model, country, wave, Dim1, Dim2, gt1, gt2, d1, d2, dist)
saveRDS(c2_matched, "c2_matched.rds")

c2_latest <- latest_wave(c2_matched)

#' C1 has no wave dimension — the model was asked about the country with no year
#' — so it is compared against each country's most recent truth.

latest_gt <- gt %>% group_by(country) %>% filter(wave == max(wave)) %>% ungroup()

c1_latest <- model_coords %>%
  filter(condition == "C1") %>%
  select(model, country, Dim1, Dim2) %>%
  inner_join(latest_gt, by = "country") %>%
  mutate(d1 = Dim1 - gt1, d2 = Dim2 - gt2, dist = sqrt(d1^2 + d2^2))

#' ## Point estimates
#'
#' Two features of the coordinate system set the scale for every distance below:
#' country coordinates fall roughly within ±0.7 standardized units on each axis,
#' and the average country sits 0.40 units from the global centroid.

summarise_level <- function(df, label) {
  cat(sprintf("\n=== %s: distance to most-recent snapshot ===\n", label))
  df %>% group_by(model) %>%
    summarise(n = n(), mean_dist = mean(dist), median_dist = median(dist),
              bias_Dim1 = mean(d1), bias_Dim2 = mean(d2), .groups = "drop") %>%
    mutate(across(where(is.numeric), ~ round(.x, 3))) %>% print()
}

summarise_level(c1_latest, "C1 (country only, no year)")
summarise_level(c2_latest, "C2 (country and fieldwork year)")

cat("\naverage country distance from the global centroid:\n")
latest_gt %>% summarise(centroid_dist = round(mean(sqrt((gt1 - mean(gt1))^2 +
                                                        (gt2 - mean(gt2))^2)), 3)) %>% print()

#' ## Paired country bootstrap
#'
#' Resamples the forty countries with replacement, the same resampled set across
#' all models within each replicate. This captures uncertainty from generalizing
#' across countries, which dominates in this design; it does not separately
#' propagate the within-cell variability of the ten elicitations.

boot_level <- function(df, label) {
  bd <- boot_paired(df, "dist")
  report_ci(bd, sprintf("%s mean distance, 95%% CI (lower = closer)", label))
  report_pairwise(bd, sprintf("%s accuracy", label))
  bd
}

bd_c1 <- boot_level(c1_latest, "C1")
bd_c2 <- boot_level(c2_latest, "C2")

saveRDS(list(C1 = bd_c1, C2 = bd_c2, c1_latest = c1_latest, c2_latest = c2_latest),
        "level_bootstrap.rds")

#' ## Per-country placement error
#'
#' Accuracy varies more across countries than across models, so this is the more
#' informative cut. Averaged over the four models to describe the country rather
#' than any one system.

by_country <- c1_latest %>%
  group_by(country) %>% summarise(mean_err = round(mean(dist), 3), .groups = "drop") %>%
  arrange(mean_err)

cat("\n=== per-country mean placement error (C1), best and worst eight ===\n")
print(head(by_country, 8)); print(tail(by_country, 8))

#' Sensitivity: the pre-specified indicator-coverage rule would drop Iraq and
#' Hong Kong from the snapshot comparisons. Re-run without them to confirm the
#' model ranking and every significance verdict are unchanged.

c1_38 <- c1_latest %>% filter(!country %in% c("IRQ", "HKG"))
cat("\n=== sensitivity: C1 excluding IRQ and HKG (n =", n_distinct(c1_38$country), ") ===\n")
bd_38 <- boot_paired(c1_38, "dist")
report_ci(bd_38, "C1 mean distance, 38 countries")
report_pairwise(bd_38, "C1 accuracy, 38 countries")
