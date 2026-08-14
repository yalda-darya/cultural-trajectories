#' # 09 — Does naming the year help?
#'
#' Cultural prompting is the control strategy the field recommends, and naming a
#' country demonstrably works — script 05 shows it relocates the answer across
#' the map. This asks whether the same trick works in time: does supplying the
#' fieldwork year move a model's account of a country toward that year's true
#' position?
#'
#' The comparison is within-model and within-country. Each model is asked about
#' the same country twice, once with the fieldwork year of its most recent survey
#' and once with no year, and the question is whether the year brought the answer
#' closer to that year's true position. Positive means the year helped.
#'
#' Two tests because they answer slightly different questions: the paired country
#' bootstrap generalizes across countries, while the Wilcoxon signed-rank treats
#' the countries as fixed and asks about the median shift within this sample. A
#' result that appears in one but not the other is not a robust effect.
#'
#' If naming the year does not work, the failure cannot be corrected by users
#' through better prompting and has to be handled by developers — which is why
#' this small null carries weight in the discussion.
#'
#' **Inputs:** `c2_matched.rds`, `model_coords.rds`, `country_wave_coords.rds`
#' **Writes:** `year_prompt_effect.rds`

source("R/00_setup.R")

c2 <- readRDS("c2_matched.rds")
mc <- readRDS("model_coords.rds")
gt <- readRDS("country_wave_coords.rds") %>% transmute(country = iso, wave, gt1 = Dim1, gt2 = Dim2)

latest    <- latest_wave(c2)
latest_gt <- gt %>% group_by(country) %>% filter(wave == max(wave)) %>% ungroup()

c2d <- latest %>% transmute(model, country, dist_C2 = dist)

c1d <- mc %>% filter(condition == "C1") %>%
  group_by(model, country) %>%
  summarise(Dim1 = mean(Dim1), Dim2 = mean(Dim2), .groups = "drop") %>%
  inner_join(latest_gt, by = "country") %>%
  transmute(model, country, dist_C1 = sqrt((Dim1 - gt1)^2 + (Dim2 - gt2)^2))

pair <- inner_join(c1d, c2d, by = c("model", "country")) %>%
  mutate(improve = dist_C1 - dist_C2)

#' ## Paired country bootstrap

bm <- boot_paired(pair, "improve")
report_ci(bm, "C1 distance minus C2 distance (> 0 = naming the year improves placement)")

#' ## Wilcoxon signed-rank, per model

cat("\n=== Wilcoxon signed-rank (paired, per model), C1 vs C2 distance ===\n")
for (m in unique(pair$model)) {
  d <- pair %>% filter(model == m)
  w <- wilcox.test(d$dist_C1, d$dist_C2, paired = TRUE)
  cat(sprintf("  %-22s median improve = %+.3f   p = %.3f\n", m, median(d$improve), w$p.value))
}

#' ## Scale of the effect
#'
#' Any gain from the year should be read against the two quantities around it:
#' the distance still remaining between the model and the truth, and the distance
#' naming the *country* moves the answer. A year effect an order of magnitude
#' smaller than the residual error is not a correction.

reloc <- readRDS("c0_relocation.rds")$reloc %>%
  group_by(model) %>% summarise(mean_reloc = mean(reloc_dist), .groups = "drop")

cat("\n=== the year effect in context ===\n")
pair %>% group_by(model) %>%
  summarise(median_year_gain = median(improve), mean_remaining_dist = mean(dist_C2),
            .groups = "drop") %>%
  left_join(reloc, by = "model") %>%
  mutate(remaining_vs_gain = round(mean_remaining_dist / abs(median_year_gain), 1),
         country_move_vs_gain = round(mean_reloc / abs(median_year_gain), 1),
         across(where(is.numeric), ~ round(.x, 3))) %>% print()

saveRDS(pair, "year_prompt_effect.rds")
