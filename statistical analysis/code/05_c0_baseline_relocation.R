#' # 05 — The country-agnostic baseline
#'
#' C0 names neither country nor year — it asks about "a population of adults" —
#' and gives one coordinate per model. It answers two questions.
#'
#' First, it scales the snapshot result. Placing countries 0.15 to 0.24 units
#' from the truth means little without knowing what a country-blind answer
#' scores; the gap between C0 and C1 is how much work naming the country does.
#'
#' Second, and more interesting, the countries the C0 point *already* resembles
#' are the societies the model's default answer describes. This reproduces, from
#' our own data, the default-skew finding the cultural-alignment literature
#' reports from other instruments.
#'
#' **Caveat carried forward:** national pride (G006) is undefined without a
#' country and is omitted from C0, so C0 rests on twelve components against
#' thirteen for C1. Part of any C0→C1 distance is therefore the indicator base
#' changing rather than the model relocating. G006 loads on Dimension 1, so the
#' contamination is asymmetric across axes. The sensitivity block at the end
#' recomputes the relocation on the shared twelve-item base.
#'
#' **Inputs:** `model_coords.rds`, `country_wave_coords.rds`, `model_item_values.rds`
#' **Writes:** `c0_relocation.rds`

source("R/00_setup.R")

model_coords <- readRDS("model_coords.rds")
coords       <- readRDS("country_wave_coords.rds")

latest_gt <- coords %>%
  transmute(country = as.character(iso), wave = as.numeric(wave), gt1 = Dim1, gt2 = Dim2) %>%
  group_by(country) %>% filter(wave == max(wave)) %>% ungroup() %>%
  select(country, gt1, gt2)

#' ## The C0 point
#'
#' One coordinate per model. Where it lands is itself descriptive: a
#' mid-secular, high-self-expression position is not a neutral origin.

c0 <- model_coords %>%
  filter(condition == "C0") %>%
  group_by(model) %>%
  summarise(c0_1 = mean(Dim1, na.rm = TRUE), c0_2 = mean(Dim2, na.rm = TRUE), .groups = "drop")
cat("\n=== C0 coordinate per model (country-agnostic) ===\n"); print(c0)

c1 <- model_coords %>%
  filter(condition == "C1") %>%
  transmute(model, country = as.character(country), c1_1 = Dim1, c1_2 = Dim2)

#' Three quantities per model × country: how far the country-blind answer sits
#' from that country's truth, how far the country-named answer sits from it, and
#' how far naming the country moved the answer.

reloc <- c1 %>%
  inner_join(c0, by = "model") %>%
  inner_join(latest_gt, by = "country") %>%
  mutate(base_dist  = sqrt((c0_1 - gt1)^2 + (c0_2 - gt2)^2),
         c1_dist    = sqrt((c1_1 - gt1)^2 + (c1_2 - gt2)^2),
         reloc_dist = sqrt((c1_1 - c0_1)^2 + (c1_2 - c0_2)^2),
         improve    = base_dist - c1_dist)

cat("\n=== point estimates ===\n")
reloc %>% group_by(model) %>%
  summarise(n = n(), mean_base = round(mean(base_dist), 3),
            mean_c1 = round(mean(c1_dist), 3), mean_reloc = round(mean(reloc_dist), 3),
            .groups = "drop") %>% print()

b_base  <- boot_paired(reloc, "base_dist")
b_reloc <- boot_paired(reloc, "reloc_dist")
b_impr  <- boot_paired(reloc, "improve")

report_ci(b_base,  "C0 baseline distance to truth, 95% CI")
report_ci(b_reloc, "relocation, distance C0 to C1, 95% CI")

#' The improvement interval is the one that supports the claim that naming the
#' country makes the answer *better*. The relocation interval cannot: distance is
#' non-negative, so an interval excluding zero there is guaranteed and tests
#' nothing.

report_ci(b_impr, "accuracy gain from naming the country (C0 dist - C1 dist), 95% CI")

#' ## Which societies does the default answer already resemble?
#'
#' Ranked within each model, since the C0 point differs by model.

ranked <- reloc %>%
  select(model, country, reloc_dist) %>%
  group_by(model) %>%
  mutate(rank_least_moved = rank(reloc_dist, ties.method = "min")) %>%
  ungroup()

cat("\n=== five least-moved countries per model ===\n")
ranked %>% filter(rank_least_moved <= 5) %>% arrange(model, rank_least_moved) %>%
  mutate(reloc_dist = round(reloc_dist, 3)) %>% as.data.frame() %>% print(row.names = FALSE)

cat("\n=== how many models put each country in its bottom five ===\n")
ranked %>% filter(rank_least_moved <= 5) %>% count(country, name = "n_models") %>%
  arrange(desc(n_models), country) %>% as.data.frame() %>% print(row.names = FALSE)

cat("\n=== relocation by country, averaged over models (ten smallest) ===\n")
ranked %>% group_by(country) %>%
  summarise(mean_reloc = round(mean(reloc_dist), 3),
            min_reloc = round(min(reloc_dist), 3), .groups = "drop") %>%
  arrange(mean_reloc) %>% head(10) %>% as.data.frame() %>% print(row.names = FALSE)

cat(sprintf("\nsmallest single relocation: %.3f | mean: %.3f | median: %.3f\n",
            min(ranked$reloc_dist), mean(ranked$reloc_dist), median(ranked$reloc_dist)))

saveRDS(list(reloc = reloc, ranked = ranked, boot_base = b_base,
             boot_reloc = b_reloc, boot_improve = b_impr), "c0_relocation.rds")

#' ## Sensitivity: shared twelve-item base
#'
#' Rescores C1 without G006 so both conditions rest on the same components, and
#' recomputes the relocation. If the ordering and magnitude survive, the
#' relocation result is not an artefact of the missing item.

vals   <- readRDS("model_item_values.rds")
params <- read_csv("standardization_params.csv", show_col_types = FALSE)
base   <- read_csv("item_base_by_country.csv",   show_col_types = FALSE)

coords_12 <- vals %>%
  filter(item != "G006", condition %in% c("C0", "C1")) %>%
  left_join(params, by = "item") %>%
  left_join(base,   by = c("country" = "iso", "item")) %>%
  filter(keep) %>%
  mutate(z = sign * (value - mu) / sd) %>%
  group_by(model, country, condition, dim) %>%
  summarise(score = mean(z), .groups = "drop") %>%
  pivot_wider(names_from = dim, values_from = score)

c0_12 <- coords_12 %>% filter(condition == "C0") %>%
  group_by(model) %>% summarise(c0_1 = mean(Dim1), c0_2 = mean(Dim2), .groups = "drop")

reloc_12 <- coords_12 %>% filter(condition == "C1") %>%
  transmute(model, country = as.character(country), c1_1 = Dim1, c1_2 = Dim2) %>%
  inner_join(c0_12, by = "model") %>%
  mutate(reloc_dist = sqrt((c1_1 - c0_1)^2 + (c1_2 - c0_2)^2))

cat("\n=== sensitivity: relocation on the shared 12-item base (G006 dropped from both) ===\n")
report_ci(boot_paired(reloc_12, "reloc_dist"), "relocation, 12-item base, 95% CI")
