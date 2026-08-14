#' # 08 — Reversal reproduction
#'
#' The hardest test of temporal representation. Where a society's path doubles
#' back, timing is the whole signal and a model running on a smooth modernization
#' prior has no way to bend. Net displacement is useless here — an out-and-back
#' path nets to nearly nothing — so the measure is the turn angle at the vertex
#' where the path bends, where 180° is a complete about-face.
#'
#' Two quantities, and the distinction between them is the finding. **Angle**
#' asks whether the model bent at the right moment. **Magnitude** asks whether it
#' travelled while bending. Turn angle is scale-free, so a sharp angle between
#' two negligible steps looks identical to a real reversal; every apparent hit is
#' therefore guarded by requiring the model's summed step length at the bend to
#' be at least half the truth's.
#'
#' With six countries, three of them observed at three waves and so contributing
#' a single interior vertex, this is reported as a descriptive case series rather
#' than a powered comparison, and models are not ranked on it.
#'
#' **Inputs:** `c2_matched.rds`, `classification.rds`
#' **Writes:** `reversal_turns.rds`, `reversal_hits.rds`

source("R/00_setup.R")

c2 <- readRDS("c2_matched.rds")

#' The verified reversal set. Stage 2 of the classification yielded seven
#' candidates; the set below is the post-verification classification after
#' inspecting trajectory geometry against the independent Welzel indices.
#' Edit here if the verified set changes, and record the change on OSF.

REV_ISO <- c("IDN", "IND", "JOR", "JPN", "KOR", "ZWE")

#' At an interior vertex: the angle between incoming and outgoing steps, and the
#' summed length of those two steps.

bend_stats <- function(P, i) {
  a <- P[i, ] - P[i - 1, ]; b <- P[i + 1, ] - P[i, ]
  na <- sqrt(sum(a^2)); nb <- sqrt(sum(b^2))
  ang <- if (na == 0 || nb == 0) NA_real_ else acos(pmax(pmin(sum(a * b) / (na * nb), 1), -1)) * 180 / pi
  c(turn = ang, mag = na + nb)
}

turns_of <- function(P) {
  k <- nrow(P); if (k < 3) return(numeric(0))
  sapply(2:(k - 1), function(i) bend_stats(P, i)["turn"])
}

build_turns <- function(df, id) {
  df %>% arrange(country, wave) %>% group_by(country) %>% group_split() %>%
    map_dfr(function(d) {
      P <- as.matrix(d[, c("Dim1", "Dim2")])
      tv <- turns_of(P)
      if (!length(tv)) return(NULL)
      tibble(source = id, country = d$country[1],
             vertex_wave = d$wave[2:(nrow(d) - 1)], turn_deg = tv)
    })
}

#' ## Turn profiles, both sides built by identical code

truth_df <- c2 %>% filter(country %in% REV_ISO) %>%
  distinct(country, wave, Dim1 = gt1, Dim2 = gt2) %>% arrange(country, wave)
truth_turns <- build_turns(truth_df, "truth")

model_turns <- c2 %>% filter(country %in% REV_ISO) %>%
  select(model, country, wave, Dim1, Dim2) %>%
  group_by(model) %>% group_split() %>%
  map_dfr(function(d) build_turns(d, d$model[1]) %>% mutate(model = d$model[1]))

saveRDS(list(truth = truth_turns, model = model_turns), "reversal_turns.rds")

#' The true reversal for each country is the vertex with the largest turn in the
#' ground truth. That wave is the target each model must hit.

truth_peak <- truth_df %>% group_by(country) %>% group_split() %>%
  map_dfr(function(d) {
    P <- as.matrix(d[, c("Dim1", "Dim2")]); k <- nrow(P)
    st <- t(sapply(2:(k - 1), function(i) bend_stats(P, i)))
    j <- which.max(st[, "turn"])
    tibble(country = d$country[1], true_bend_wave = d$wave[1 + j],
           true_turn = round(st[j, "turn"]), true_mag = st[j, "mag"],
           k_waves = k)
  })

cat("\n=== true reversals: the target each model must reproduce ===\n")
print(truth_peak %>% arrange(desc(true_turn)))

#' ## Each model's turn at the true bend wave

model_bend <- c2 %>% filter(country %in% REV_ISO) %>%
  select(model, country, wave, Dim1, Dim2) %>% arrange(model, country, wave) %>%
  group_by(model, country) %>% group_split() %>%
  map_dfr(function(d) {
    P <- as.matrix(d[, c("Dim1", "Dim2")]); k <- nrow(P); if (k < 3) return(NULL)
    st <- data.frame(vertex_wave = d$wave[2:(k - 1)],
                     t(sapply(2:(k - 1), function(i) bend_stats(P, i))))
    tibble(model = d$model[1], country = d$country[1], st = list(st))
  }) %>%
  inner_join(truth_peak, by = "country") %>%
  mutate(row = map2(st, true_bend_wave, ~ .x[.x$vertex_wave == .y, ][1, ])) %>%
  transmute(model, country, true_turn, true_mag,
            model_max_turn = map_dbl(st, ~ round(max(.x$turn, na.rm = TRUE))),
            model_turn = round(map_dbl(row, "turn")),
            model_mag  = map_dbl(row, "mag"),
            mag_ratio  = round(model_mag / true_mag, 2))

#' ## Verdict
#'
#' A genuine reproduction requires both a sharp turn (≥ 120°) and a journey at
#' least half as long as the real one. The intermediate category — sharp but tiny
#' — is the one that matters interpretively: the shape of the reversal is there,
#' the movement is not.

comp <- model_bend %>%
  mutate(hit = case_when(
    model_turn >= 120 & mag_ratio >= 0.5 ~ "REAL reversal",
    model_turn >= 120 & mag_ratio <  0.5 ~ "sharp but TINY (noise)",
    model_turn <  120 & model_turn >= 60 ~ "partial bend",
    TRUE                                 ~ "no bend")) %>%
  arrange(country, model)
saveRDS(comp, "reversal_hits.rds")

cat("\n=== reversal hits with magnitude guard ===\n")
print(comp %>% mutate(true_mag = round(true_mag, 2), model_mag = round(model_mag, 2)), n = Inf)

cat("\n=== which sharp turns survive the magnitude guard? ===\n")
comp %>% filter(model_turn >= 120) %>%
  select(country, model, model_turn, mag_ratio, hit) %>% print(n = Inf)

cat("\n=== reproduction count, out of", nrow(comp), "country-model cases ===\n")
comp %>% count(hit) %>% print()

#' Distance, not direction, is what fails: across all cases the models move a
#' fraction of the true distance through the bend, the same halving of the rate
#' seen in script 07, appearing at exactly the moment when a country's movement
#' is what makes the reversal a reversal.

cat("\n=== median turn and median magnitude ratio at the true bend, by model ===\n")
comp %>% group_by(model) %>%
  summarise(median_turn = median(model_turn, na.rm = TRUE),
            median_mag_ratio = round(median(mag_ratio, na.rm = TRUE), 2),
            max_turn = max(model_turn, na.rm = TRUE), .groups = "drop") %>% print()
cat("true median turn:", median(truth_peak$true_turn), "\n")
cat("median mag_ratio across all cases:", round(median(comp$mag_ratio, na.rm = TRUE), 2), "\n")
