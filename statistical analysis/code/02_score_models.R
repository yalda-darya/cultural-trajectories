#' # 02 — Scoring model outputs onto the cultural map
#'
#' Takes the raw elicitation panel and puts it on the same two axes as the
#' survey. Four stages: read the JSONL and average the ten replicates per cell;
#' convert each stated distribution into the single number comparable to a WVS
#' respondent mean; export the per-country indicator base; and apply the survey's
#' own standardization to get model coordinates.
#'
#' The estimand per cell is the mean *stated* distribution over k = 10
#' independent elicitations. Models were asked to state a probability
#' distribution over the response options directly rather than being sampled
#' repeatedly, which elicits the model's belief about the population
#' distribution instead of conflating it with response stochasticity.
#'
#' **Inputs:** elicitation JSONL, `standardization_params.csv`,
#' `WVS_subset_40countries_W4toW7.rds`
#' **Writes:** `model_cells_long.rds`, `model_item_values.rds`,
#' `item_base_by_country.csv`, `model_coords.rds`

source("R/00_setup.R")
library(jsonlite)
library(haven)

#' ## Stage 1 — Read the elicitation panel
#'
#' One JSONL per model × country. Only records flagged usable are kept: `OK`,
#' `NORMALIZED` (probabilities rescaled to sum to one), and `SUM_SOFT_OVER`
#' (sum slightly above one, within tolerance). Provider and model are read from
#' inside each record rather than from the filename. Output is long — one row per
#' response option — for clean downstream joins.

USABLE <- c("OK", "NORMALIZED", "SUM_SOFT_OVER")

read_one <- function(path) {
  lines <- readLines(path, warn = FALSE); lines <- lines[nzchar(lines)]
  recs  <- lapply(lines, fromJSON, simplifyVector = TRUE)
  map_dfr(recs, function(r) {
    if (is.null(r$flag) || !(r$flag %in% USABLE)) return(NULL)
    p <- r$parsed
    if (is.null(p) || !length(p)) return(NULL)
    tibble(provider = r$provider, model = r$model,
           country  = r$country,  condition = r$condition,
           item_id  = r$item_id,  item_type = r$item_type,
           wave     = as.integer(r$wave),
           replicate = as.integer(r$replicate),
           option   = names(p),
           prob     = as.numeric(unlist(p)))
  })
}

files <- list.files(ELICITATION_DIR, pattern = "\\.jsonl$", recursive = TRUE, full.names = TRUE)
cat("reading", length(files), "files...\n")
raw <- map_dfr(files, read_one)

#' Collapse replicates to the mean stated distribution per cell and option. The
#' per-option SD across replicates is retained as a precision signal — it is the
#' within-cell variability that the country bootstrap does not separately
#' propagate, and it is largest for the least stable model.

cell_keys <- c("provider", "model", "country", "condition", "item_id", "item_type", "wave")

repl_n <- raw %>% distinct(across(all_of(cell_keys)), replicate) %>%
  count(across(all_of(cell_keys)), name = "k_used")

model_cells <- raw %>%
  group_by(across(all_of(c(cell_keys, "option")))) %>%
  summarise(mean_prob = mean(prob), sd_prob = sd(prob), .groups = "drop") %>%
  left_join(repl_n, by = cell_keys)

saveRDS(model_cells, "model_cells_long.rds")

#' Completeness gate before scoring: four models, forty countries each, and
#' k_used = 10 for every cell.

cat("\nrows:", nrow(model_cells), "\n")
model_cells %>% distinct(model, country) %>% count(model, name = "countries") %>% print()
model_cells %>% distinct(across(all_of(cell_keys)), k_used) %>%
  count(model, k_used) %>% arrange(model, k_used) %>% print(n = Inf)

#' ## Stage 2 — Stated distributions to WVS component values
#'
#' Three item types, each converted by the rule that makes it comparable to the
#' corresponding survey respondent mean.
#'
#' *Ordinal items* become the expected value of the stated distribution over the
#' numbered scale.

model_cells <- readRDS("model_cells_long.rds")

ordinal_ids <- c("F118", "F120", "F063", "G006", "E018", "A008", "E025", "A165")
ev_A <- model_cells %>%
  filter(item_type == "A", item_id %in% ordinal_ids) %>%
  mutate(pt = as.numeric(option)) %>%
  group_by(model, country, condition, wave, item = item_id) %>%
  summarise(value = sum(pt * mean_prob), .groups = "drop")

#' *The child-qualities card sort* yields the four child-autonomy components as
#' stated selection probabilities. The deck differs across waves, so each quality
#' is mapped to its wave-specific card position.

scored_key <- tribble(
  ~wave, ~card, ~item,
  4L,  1L, "A029",  4L,  7L, "A039",  4L,  8L, "A040",  4L, 10L, "A042",
  5L,  1L, "A029",  5L,  7L, "A039",  5L,  8L, "A040",  5L, 10L, "A042",
  6L,  1L, "A029",  6L,  7L, "A039",  6L,  8L, "A040",  6L, 10L, "A042",
  7L,  2L, "A029",  7L,  8L, "A039",  7L,  9L, "A040",  7L, 11L, "A042"
)
ev_B <- model_cells %>%
  filter(item_type == "B") %>%
  mutate(card = as.integer(option)) %>%
  inner_join(scored_key, by = c("wave", "card")) %>%
  transmute(model, country, condition, wave, item, value = mean_prob / 100)

#' *The four-goal post-materialism ranking* becomes Y002 by assigning each
#' ordered goal-pair the number of post-materialist goals it contains (goals 2
#' and 4) and taking the probability-weighted mean on the resulting 1–3 index.

y002_cat <- function(pair) { g <- as.integer(strsplit(pair, ",")[[1]]); 1 + sum(g %in% c(2L, 4L)) }
pair_cat <- model_cells %>% filter(item_id == "Y002") %>% distinct(option) %>%
  mutate(cat = map_dbl(option, y002_cat))
ev_C <- model_cells %>%
  filter(item_id == "Y002") %>%
  left_join(pair_cat, by = "option") %>%
  group_by(model, country, condition, wave, item = item_id) %>%
  summarise(value = sum(mean_prob * cat), .groups = "drop")

model_item_values <- bind_rows(ev_A, ev_B, ev_C) %>%
  arrange(model, country, condition, wave, item)
saveRDS(model_item_values, "model_item_values.rds")

#' Expect thirteen values per cell, and twelve for C0 — national pride (G006) is
#' undefined without a country and is omitted from the country-agnostic
#' condition. That difference in indicator base is a caveat on any C0-to-C1
#' comparison; see script 05.

model_item_values %>% count(model, country, condition, wave) %>%
  count(n_items = n) %>% print()

#' Scale sanity check only, not a level result: model item means should sit on
#' the same scale as the WVS means.

params <- read_csv("standardization_params.csv", show_col_types = FALSE)
model_item_values %>% group_by(item) %>%
  summarise(model_mean = mean(value), .groups = "drop") %>%
  left_join(params %>% select(item, wvs_mu = mu), by = "item") %>%
  mutate(across(where(is.numeric), ~ round(.x, 3))) %>% print(n = Inf)

#' ## Stage 3 — The per-country indicator base
#'
#' Reproduces the ground truth's keep/drop table so the model averages over the
#' same item set per country. Drops are not random: they concentrate in items
#' thin in less-liberal and less-Western contexts, and fall more heavily on
#' Dimension 2. Nine countries rest on a reduced base and are correspondingly
#' less precisely estimated.

sub <- readRDS("WVS_subset_40countries_W4toW7.rds")
resolve <- function(want, have) unname(setNames(have, toupper(have))[toupper(want)])
nms <- names(sub); item_cols <- resolve(ITEMS, nms); stopifnot(!any(is.na(item_cols)))

X <- vapply(item_cols, function(cc) { v <- as.numeric(zap_labels(sub[[cc]])); v[v < 0] <- NA; v },
            numeric(nrow(sub)))
colnames(X) <- ITEMS
wave <- as.numeric(sub[[resolve("S002VS", nms)]]); iso <- sub$iso3

item_base <- data.frame(iso, wave, X, check.names = FALSE) %>%
  group_by(iso, wave) %>%
  summarise(across(all_of(ITEMS), ~ mean(!is.na(.x)) > 0.5), .groups = "drop") %>%
  group_by(iso) %>%
  summarise(across(all_of(ITEMS), ~ all(.x)), .groups = "drop") %>%
  pivot_longer(all_of(ITEMS), names_to = "item", values_to = "keep")

write_csv(item_base, "item_base_by_country.csv")

cat("countries:", n_distinct(item_base$iso), "| rows:", nrow(item_base), "(expect 520)\n")
item_base %>% group_by(iso) %>% summarise(n_kept = sum(keep), .groups = "drop") %>%
  count(n_kept) %>% arrange(desc(n_kept)) %>% print()
item_base %>% filter(!keep) %>% arrange(iso, item) %>% print(n = Inf)

#' ## Stage 4 — Project onto the axes
#'
#' Standardize each model item value with the *survey's* μ and σ, apply the
#' orientation sign, and average within each dimension over only that country's
#' kept items. Identical rule to the ground truth, so the output is directly
#' comparable to `country_wave_coords.rds`.

vals   <- readRDS("model_item_values.rds")
params <- read_csv("standardization_params.csv", show_col_types = FALSE)
base   <- read_csv("item_base_by_country.csv",   show_col_types = FALSE)

model_coords <- vals %>%
  left_join(params, by = "item") %>%
  left_join(base,   by = c("country" = "iso", "item")) %>%
  filter(keep) %>%
  mutate(z = sign * (value - mu) / sd) %>%
  group_by(model, country, condition, wave, dim) %>%
  summarise(score = mean(z), n_items = n(), .groups = "drop") %>%
  pivot_wider(names_from = dim, values_from = c(score, n_items)) %>%
  rename(Dim1 = score_Dim1, Dim2 = score_Dim2,
         k_dim1 = n_items_Dim1, k_dim2 = n_items_Dim2)

saveRDS(model_coords, "model_coords.rds")

cat("rows:", nrow(model_coords), "| models:", n_distinct(model_coords$model),
    "| countries:", n_distinct(model_coords$country), "\n")
model_coords %>% count(condition) %>% print()

#' Model coordinates should occupy a range roughly comparable to the ground
#' truth: same scale, centred near zero, no blow-up.

model_coords %>% summarise(across(c(Dim1, Dim2), list(min = min, mean = mean, max = max))) %>%
  mutate(across(everything(), ~ round(.x, 3))) %>% print()
readRDS("country_wave_coords.rds") %>%
  summarise(across(c(Dim1, Dim2), list(min = min, mean = mean, max = max))) %>%
  mutate(across(everything(), ~ round(.x, 3))) %>% print()
