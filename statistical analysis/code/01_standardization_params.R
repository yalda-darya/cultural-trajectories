#' # 01 — The coordinate system
#'
#' The ground-truth build z-scores each component item inline and never saves the
#' means and standard deviations it used. But those μ and σ *are* the coordinate
#' system: scoring the models on the same axes requires the identical values, not
#' recomputed ones. This script reproduces the ground-truth scoring rule exactly
#' — pooled, one-time, unweighted mean and SD over all respondents, with WVS
#' negative codes set to missing — and freezes the per-item μ, σ, orientation
#' sign, and dimension to disk.
#'
#' It then verifies the export by rebuilding the saved country-wave coordinates
#' from the exported parameters alone. A maximum coordinate difference of zero is
#' the check that model and survey coordinates live on one scale, which is what
#' every distance in the paper assumes.
#'
#' **Inputs:** `WVS_subset_40countries_W4toW7.rds`, `country_wave_coords.rds`
#' **Writes:** `standardization_params.csv`

source("R/00_setup.R")
library(haven)

sub    <- readRDS("WVS_subset_40countries_W4toW7.rds")
coords <- readRDS("country_wave_coords.rds")

#' Column names in the WVS trend file vary in case across releases, so resolve
#' the locked instrument against whatever is actually present and fail loudly if
#' any component is missing.

resolve <- function(want, have) unname(setNames(have, toupper(have))[toupper(want)])
nms <- names(sub)
item_cols <- resolve(ITEMS, nms)
stopifnot(!any(is.na(item_cols)))

#' Respondent-level matrix of the thirteen components, WVS negatives → NA.

X <- vapply(item_cols,
            function(cc) { v <- as.numeric(zap_labels(sub[[cc]])); v[v < 0] <- NA; v },
            numeric(nrow(sub)))
colnames(X) <- ITEMS

#' The parameters themselves: pooled over the entire respondent sample, computed
#' once, and unweighted. Weighting enters later, at aggregation to national
#' means, not here.

mu <- apply(X, 2, mean, na.rm = TRUE)
sg <- apply(X, 2, sd,   na.rm = TRUE)

params <- tibble(item = ITEMS, dim = DIM_OF[ITEMS], sign = SIGNS[ITEMS],
                 mu = mu[ITEMS], sd = sg[ITEMS])
write_csv(params, "standardization_params.csv")
print(params)

#' ## Verification
#'
#' Rebuild the saved coordinates using only the exported parameters. This
#' repeats the full ground-truth aggregation: z-score, apply the orientation
#' sign, restrict to the constant within-country indicator base, take
#' survey-weighted national means per item, and average items within each
#' dimension.

Z <- sweep(sweep(X, 2, params$mu, `-`), 2, params$sd, `/`)
Z <- sweep(Z, 2, params$sign, `*`)

wave <- as.numeric(sub[[resolve("S002VS", nms)]])
w    <- as.numeric(sub[[resolve("S017",   nms)]]); w[is.na(w) | w <= 0] <- 1
df   <- data.frame(iso = sub$iso3, wave, w, Z, check.names = FALSE)

#' The constant within-country indicator base: keep an item for a country only if
#' it is more than half fielded in *all* of that country's waves. Applying the
#' same base to every wave is what keeps a country's coordinate comparable across
#' its own trajectory.

in_base <- df %>%
  group_by(iso, wave) %>%
  summarise(across(all_of(ITEMS), ~ mean(!is.na(.x)) > 0.5), .groups = "drop") %>%
  group_by(iso) %>%
  summarise(across(all_of(ITEMS), ~ all(.x)), .groups = "drop") %>%
  pivot_longer(all_of(ITEMS), names_to = "item", values_to = "keep")

wmean <- function(x, w) { ok <- !is.na(x); if (!any(ok)) NA_real_ else sum(x[ok] * w[ok]) / sum(w[ok]) }

repro <- df %>%
  pivot_longer(all_of(ITEMS), names_to = "item", values_to = "z") %>%
  left_join(in_base, by = c("iso", "item")) %>% filter(keep) %>%
  group_by(iso, wave, item) %>% summarise(m = wmean(z, w), .groups = "drop") %>%
  mutate(dim = DIM_OF[item]) %>%
  group_by(iso, wave, dim) %>% summarise(score = mean(m, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = dim, values_from = score) %>%
  rename(Dim1r = Dim1, Dim2r = Dim2)

chk <- coords %>% select(iso, wave, Dim1, Dim2) %>% inner_join(repro, by = c("iso", "wave"))
cat("max coord diff vs saved:",
    format(max(abs(chk$Dim1 - chk$Dim1r), abs(chk$Dim2 - chk$Dim2r)), scientific = TRUE), "\n")

#' Note for the methods: this operationalizes the Inglehart–Welzel dimensions as
#' an equal-weight average of z-scored component items, not as the published
#' `tradrat5` / `survself` factor scores. The composite is a deliberate proxy,
#' chosen because the identical rule can be applied to model outputs.
