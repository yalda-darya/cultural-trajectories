#' # 06 — The implicit temporal anchor
#'
#' Every published alignment estimate carries a year without examining it. This
#' script recovers it: given a query naming the country but no year (C1), which
#' survey wave does the model's placement most resemble, and how far behind the
#' present does that sit?
#'
#' Restricted to the countries that actually moved. For a society that barely
#' changed, all its waves sit in nearly the same place, so the nearest-wave
#' assignment carries no information and the lag is undefined in substance even
#' where it is defined arithmetically.
#'
#' Two answers are reported, and the reason they differ matters. The *continuous*
#' curve — mean distance to each wave position — is minimised at the present for
#' every model. The *argmin* assignment, which wave actually wins per country,
#' puts a minority of countries at the present for two of the four models. The
#' most recent wave finishes a close second almost everywhere it does not finish
#' first, so it wins the average without winning many countries.
#'
#' **Inputs:** `model_coords.rds`, `country_wave_coords.rds`, `classification.rds`,
#' `c2_year_spine.csv`
#' **Writes:** `implicit_anchor.rds`

source("R/00_setup.R")

model_coords <- readRDS("model_coords.rds")
coords       <- readRDS("country_wave_coords.rds")
clsf         <- readRDS("classification.rds") %>% select(country = iso, class)

cat("condition labels present:", paste(unique(model_coords$condition), collapse = ", "), "\n")

#' Waves are unevenly spaced, so a lag in years could reflect nothing more than
#' long gaps between fieldwork rounds. The year spine assigns each country-wave
#' its modal fieldwork year; the wave-step version at the end is the robustness
#' check against exactly that confound.

spine <- read.csv("c2_year_spine.csv") %>%
  transmute(country = as.character(country), wave = as.numeric(wave), year = as.numeric(year))

gt <- coords %>%
  transmute(country = iso, wave = as.numeric(wave), gt1 = Dim1, gt2 = Dim2) %>%
  left_join(spine, by = c("country", "wave"))
stopifnot(!any(is.na(gt$year)))

#' Distance from each model's unprompted placement to every one of that
#' country's true wave positions.

c1 <- model_coords %>% filter(condition == "C1") %>%
  group_by(model, country) %>%
  summarise(m1 = mean(Dim1), m2 = mean(Dim2), .groups = "drop")

anchor <- c1 %>% inner_join(gt, by = "country") %>%
  mutate(dist = sqrt((m1 - gt1)^2 + (m2 - gt2)^2))

#' ## Nearest wave and lag in years

nearest <- anchor %>%
  group_by(model, country) %>%
  summarise(anchor_wave = wave[which.min(dist)],
            anchor_year = year[which.min(dist)],
            recent_wave = max(wave),
            recent_year = year[which.max(wave)],
            n_waves = n(), .groups = "drop") %>%
  mutate(lag_years = recent_year - anchor_year,
         anchored_recent = anchor_wave == recent_wave) %>%
  left_join(clsf, by = "country")

moved <- nearest %>% filter(class != "stable")

describe_anchor <- function(df, label) {
  cat(sprintf("\n=== implicit anchor and lag, %s ===\n", label))
  df %>% group_by(model) %>%
    summarise(n = n(), median_lag = median(lag_years), mean_lag = round(mean(lag_years), 2),
              frac_anchored_recent = round(mean(anchored_recent), 2), .groups = "drop") %>%
    print()
}

describe_anchor(nearest, "all 40 countries")
describe_anchor(moved,   "moved countries only (anchor is meaningful)")

cat("\n=== which wave gets anchored to, country counts, moved only ===\n")
moved %>% count(model, anchor_wave) %>%
  pivot_wider(names_from = anchor_wave, values_from = n, values_fill = 0) %>% print()

report_ci(boot_paired(moved, "lag_years"),
          "mean lag in years, 95% CI (clears 0 = systematic lag)", digits = 2)

#' ## The continuous anchor curve
#'
#' Mean C1-distance to each wave *position* (0 = each country's most recent),
#' which is robust to argmin jitter when two waves sit almost equally close.

cat("\n=== mean C1-distance by wave position (0 = most recent) ===\n")
anchor %>% left_join(clsf, by = "country") %>% filter(class != "stable") %>%
  group_by(model, country) %>% mutate(rel = dense_rank(desc(wave)) - 1) %>%
  group_by(model, rel) %>%
  summarise(mean_dist = round(mean(dist), 3), n = n(), .groups = "drop") %>%
  pivot_wider(names_from = rel, values_from = mean_dist, names_prefix = "pos_") %>% print()

#' ## Robustness: lag in wave-steps
#'
#' Counting in waves rather than calendar years removes any dependence on
#' fieldwork spacing. If the lag still clears zero here, the year-based result is
#' not a spacing artefact.

step <- anchor %>%
  left_join(clsf, by = "country") %>% filter(class != "stable") %>%
  group_by(model, country) %>%
  mutate(rel = dense_rank(desc(wave)) - 1) %>%
  slice_min(dist, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(model, country, anchor_rel = rel)

cat("\n=== implicit anchor lag in wave-steps (0 = present), moved countries ===\n")
step %>% group_by(model) %>%
  summarise(median_steps = median(anchor_rel), mean_steps = round(mean(anchor_rel), 2),
            frac_present = round(mean(anchor_rel == 0), 2), .groups = "drop") %>% print()

report_ci(boot_paired(step, "anchor_rel"),
          "mean wave-step lag, 95% CI (clears 0 = anchors before present)", digits = 2)

saveRDS(list(anchor = anchor, nearest = nearest, step = step), "implicit_anchor.rds")
