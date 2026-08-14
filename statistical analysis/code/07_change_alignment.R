#' # 07 — Change alignment
#'
#' The core of the paper. Placing a country correctly today says nothing about
#' how a model represents the way it got there, and this script measures the
#' difference in three passes of increasing severity.
#'
#' **Net displacement** compares start-to-end vectors. It is the easy measure and
#' models do well on it — but nearly every country in this window drifts the same
#' way, toward the secular and self-expression poles, and so does every model. A
#' system that ignored the country entirely and pushed all forty societies along
#' that common arc would score just as well. Net displacement also cancels out
#' paths that double back, which is exactly the case reversals present.
#'
#' **Step-level alignment against a permutation null** is the real test. Shuffling
#' the model's steps into the wrong periods leaves its overall direction untouched
#' and destroys only the match between its timing and the country's. A model that
#' tracks timing should score worse shuffled; one that knows only the general
#' direction scores the same either way.
#'
#' **Drift-free alignment** is the observed step-cosine minus its own permutation
#' null mean, bootstrapped over countries. Deliberately conservative: it removes
#' any tracking that coincides with a country's dominant direction, so a value
#' near zero indicates no timing information *beyond* the modernization trend
#' rather than the absence of any representation of change.
#'
#' All change analyses use C2 and are conditioned on countries that actually
#' moved — a society with no trajectory has no trajectory to miss.
#'
#' **Inputs:** `c2_matched.rds`, `classification.rds`
#' **Writes:** `trajectory_net.rds`, `trajectory_stepcos.rds`

source("R/00_setup.R")

c2   <- readRDS("c2_matched.rds")
clsf <- readRDS("classification.rds") %>% select(country = iso, class)

#' ## Pass 1 — Net displacement
#'
#' `mag_ratio` below one means the model under-travels; `dir_cos` near one means
#' it moved the right way.

net <- c2 %>%
  group_by(model, country) %>%
  summarise(t1 = gt1[wave == max(wave)] - gt1[wave == min(wave)],
            t2 = gt2[wave == max(wave)] - gt2[wave == min(wave)],
            m1 = Dim1[wave == max(wave)] - Dim1[wave == min(wave)],
            m2 = Dim2[wave == max(wave)] - Dim2[wave == min(wave)],
            n_waves = n_distinct(wave), .groups = "drop") %>%
  mutate(T_mag = sqrt(t1^2 + t2^2),
         M_mag = sqrt(m1^2 + m2^2),
         mag_ratio = M_mag / T_mag,
         dir_cos = (t1 * m1 + t2 * m2) / (T_mag * M_mag),
         angle_deg = acos(pmax(pmin(dir_cos, 1), -1)) * 180 / pi) %>%
  left_join(clsf, by = "country")
saveRDS(net, "trajectory_net.rds")

moved  <- net %>% filter(class != "stable")
stable <- net %>% filter(class == "stable")

cat("\n=== trajectory fidelity, moving countries ===\n")
moved %>% group_by(model) %>%
  summarise(n = n(),
            med_mag_ratio  = median(mag_ratio),   # ~1 tracks the rate, ~0 frozen
            med_dir_cos    = median(dir_cos),
            frac_right_dir = mean(dir_cos > 0),      # correct side of the map
            frac_within45  = mean(dir_cos > 0.707),  # the tightened criterion
            .groups = "drop") %>%
  mutate(across(where(is.numeric), ~ round(.x, 3))) %>% print()

#' The mirror check: where the survey records little movement, does the model
#' also stay put? Movement appearing where none should is the second failure
#' mode, and with four low-change countries this is a description rather than a
#' tested effect.

cat("\n=== low-change countries: model movement vs true movement ===\n")
stable %>% group_by(model) %>%
  summarise(n = n(), med_model_move = median(M_mag), med_truth_move = median(T_mag),
            .groups = "drop") %>%
  mutate(across(where(is.numeric), ~ round(.x, 3))) %>% print()

#' Rate flattening with intervals. Bootstrapped on the **median** because
#' `mag_ratio` has a near-zero denominator for reversals and a skewed
#' distribution. Run twice: all movers, and directional countries only, where net
#' displacement approximates path length so the ratio is well-behaved.

cat("\n=== median mag_ratio, all movers (upper CI < 1 = under-moves) ===\n")
report_ci(boot_paired(moved, "mag_ratio", stat = median), "mag_ratio, all movers", vs = 1)

cat("\n=== sensitivity: directional countries only ===\n")
report_ci(boot_paired(net %>% filter(class == "directional"), "mag_ratio", stat = median),
          "mag_ratio, directional only", vs = 1)

#' ## Pass 2 — Step-level alignment vs. a shuffled-year null

steps <- c2 %>% arrange(model, country, wave) %>%
  group_by(model, country) %>%
  mutate(ts1 = gt1 - lag(gt1), ts2 = gt2 - lag(gt2),
         ms1 = Dim1 - lag(Dim1), ms2 = Dim2 - lag(Dim2)) %>%
  filter(!is.na(ts1)) %>% ungroup()

step_cos <- function(d) {
  num <- d$ts1 * d$ms1 + d$ts2 * d$ms2
  den <- sqrt(d$ts1^2 + d$ts2^2) * sqrt(d$ms1^2 + d$ms2^2)
  mean(num / den, na.rm = TRUE)
}

#' The null keeps the model's steps and shuffles which true step they pair with.
#' Countries surveyed three times give two steps, which can be shuffled only by
#' swapping them, so per-country tests are underpowered by construction and
#' inference relies on the aggregate.

perm_null <- function(d, n = B) {
  k <- nrow(d); if (k < 2) return(NA_real_)
  replicate(n, {
    p <- sample(k)
    num <- d$ts1[p] * d$ms1 + d$ts2[p] * d$ms2
    den <- sqrt(d$ts1[p]^2 + d$ts2[p]^2) * sqrt(d$ms1^2 + d$ms2^2)
    mean(num / den, na.rm = TRUE)
  })
}

set.seed(SEED)
res <- steps %>% group_by(model, country) %>% group_split() %>%
  map_dfr(function(d) {
    obs <- step_cos(d); null <- perm_null(d)
    tibble(model = d$model[1], country = d$country[1], n_steps = nrow(d),
           obs_cos = obs, null_mean = mean(null, na.rm = TRUE),
           p_perm = mean(null >= obs, na.rm = TRUE))
  }) %>% left_join(clsf, by = "country")
saveRDS(res, "trajectory_stepcos.rds")

moved_steps <- res %>% filter(class != "stable")

cat("\n=== step-level alignment vs permutation null, moving countries ===\n")
moved_steps %>% group_by(model) %>%
  summarise(n = n(), med_obs_cos = median(obs_cos, na.rm = TRUE),
            med_null_cos = median(null_mean, na.rm = TRUE),
            frac_beats_null = mean(p_perm < 0.5, na.rm = TRUE),
            frac_sig = mean(p_perm < 0.1, na.rm = TRUE), .groups = "drop") %>%
  mutate(across(where(is.numeric), ~ round(.x, 3))) %>% print()

#' ## Pass 3 — Drift-free alignment, bootstrapped
#'
#' The per-country gap between observed and null. This is the headline timing
#' result: an interval clearing zero is genuine tracking beyond the shared
#' modernization trend.

gaps <- res %>% filter(class != "stable") %>% mutate(gap = obs_cos - null_mean)
bg <- boot_paired(gaps, "gap")
report_ci(bg, "drift-free step alignment (obs - null), mean over moving countries")

cat("\n=== raw observed vs null, point estimates ===\n")
gaps %>% group_by(model) %>%
  summarise(mean_obs = round(mean(obs_cos, na.rm = TRUE), 3),
            mean_null = round(mean(null_mean, na.rm = TRUE), 3),
            mean_gap = round(mean(gap, na.rm = TRUE), 3), .groups = "drop") %>% print()

report_pairwise(bg, "drift-free alignment")

#' ## Specification checks
#'
#' The test is blunt for three-wave countries, so it is cut two further ways:
#' restricted to four-wave countries, where three steps make the permutation
#' informative; and restricted to countries scored on a fuller indicator base.
#' A model that clears zero in every specification is the only one whose timing
#' signal is robust.

cat("\n=== four-wave countries only (3 steps) ===\n")
report_ci(boot_paired(gaps %>% filter(n_steps >= 3), "gap"), "drift-free alignment, 4-wave")

k_items <- readRDS("model_coords.rds") %>%
  distinct(country, k_dim1, k_dim2) %>%
  mutate(k_tot = k_dim1 + k_dim2)

cat("\n=== dropping countries scored on fewer than 13 indicators ===\n")
report_ci(boot_paired(gaps %>% inner_join(k_items, by = "country") %>% filter(k_tot >= 13), "gap"),
          "drift-free alignment, fuller indicator base")
