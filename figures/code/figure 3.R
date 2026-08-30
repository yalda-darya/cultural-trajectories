library(dplyr); library(tidyr); library(purrr); library(ggplot2)
library(forcats); library(patchwork)

if (!exists("PAL")) PAL <- c(
  "Gemini 3.6 Flash" = "#1B9E77", "Claude Opus 4.8" = "#D9820B",
  "GPT-5.5"          = "#4C9BE8", "Qwen3.6-Plus"    = "#C86BA5")
if (!exists("MODEL_ORDER")) MODEL_ORDER <- names(PAL)
if (!exists("REV6"))        REV6 <- c("IDN","IND","JOR","JPN","KOR","ZWE")

if (!exists("CNAME")) CNAME <- c(
  IDN = "Indonesia", IND = "India", JOR = "Jordan",
  JPN = "Japan", KOR = "South Korea", ZWE = "Zimbabwe")

if (!exists("th")) th <- theme_minimal(base_size = 9) +
    theme(panel.grid.minor = element_blank(),
          plot.tag = element_text(face = "bold", size = 11),
          plot.tag.position = c(0.01, 0.99),
          axis.title = element_text(size = 8.5))

if (!exists("c2_matched")) {
  relabel <- function(x) dplyr::recode(as.character(x),
                                       "gemini-3.6-flash" = "Gemini 3.6 Flash", "claude-opus-4-8" = "Claude Opus 4.8",
                                       "gpt-5.5" = "GPT-5.5", "Qwen/Qwen3.6-Plus" = "Qwen3.6-Plus")
  c2_matched <- readRDS("c2_matched.rds") |>
    mutate(model = factor(relabel(model), levels = MODEL_ORDER))
}

GT_LAB    <- "World Values Survey"
WHO_ORDER <- c(GT_LAB, MODEL_ORDER)
WHO_COLS  <- c(setNames("grey15", GT_LAB), PAL)
DIM_LAB   <- c(Dim1 = "Traditional \u2192 secular-rational",
               Dim2 = "Survival \u2192 self-expression")

rev_paths <- bind_rows(
  c2_matched |> filter(country %in% REV6) |>
    distinct(country, wave, Dim1 = gt1, Dim2 = gt2) |> mutate(who = GT_LAB),
  c2_matched |> filter(country %in% REV6) |>
    transmute(country, wave, Dim1, Dim2, who = as.character(model))
) |>
  mutate(who   = factor(who, levels = WHO_ORDER),
         label = factor(CNAME[country], levels = CNAME[REV6]))

## ---- x variable: fieldwork year if available, else wave --------------------
yr <- NULL
if ("year" %in% names(c2_matched)) {
  yr <- distinct(c2_matched, country, wave, year)
} else if (exists("c2_year_spine")) {
  yr <- distinct(c2_year_spine, country, wave, year)
} else if (file.exists("c2_year_spine.rds")) {
  yr <- readRDS("c2_year_spine.rds") |> distinct(country, wave, year)
} else if (file.exists("c2_year_spine.xlsx") && requireNamespace("readxl", quietly = TRUE)) {
  yr <- readxl::read_excel("c2_year_spine.xlsx", skip = 9) |>
    setNames(c("country", "wave", "year", "n_resp", "straddles")) |>
    mutate(wave = as.integer(wave), year = as.integer(year)) |>
    distinct(country, wave, year)
}

if (!is.null(yr)) {
  rev_paths <- left_join(rev_paths, yr, by = c("country", "wave"))
  if (anyNA(rev_paths$year)) {
    warning("year missing for some country-waves; falling back to wave")
    yr <- NULL
  }
}
if (is.null(yr)) rev_paths <- mutate(rev_paths, year = wave)

X_IS_YEAR <- max(rev_paths$year, na.rm = TRUE) > 1900
x_lab     <- if (X_IS_YEAR) "Survey year" else "WVS wave"
x_scale   <- if (X_IS_YEAR) {
  scale_x_continuous(breaks = scales::pretty_breaks(3))
} else {
  scale_x_continuous(breaks = 4:7)
}
message("x axis: ", x_lab)

## ---- bend wave (largest turn in the surveyed 2-D path) ---------------------
bend_wave_of <- function(d) {
  d <- arrange(d, wave); n <- nrow(d)
  if (n < 3) return(NA_real_)
  ang <- vapply(2:(n - 1), function(i) {
    a <- c(d$Dim1[i]     - d$Dim1[i - 1], d$Dim2[i]     - d$Dim2[i - 1])
    b <- c(d$Dim1[i + 1] - d$Dim1[i],     d$Dim2[i + 1] - d$Dim2[i])
    acos(pmin(pmax(sum(a * b) / (sqrt(sum(a^2)) * sqrt(sum(b^2))), -1), 1)) * 180 / pi
  }, numeric(1))
  d$wave[1 + which.max(ang)]
}

bends <- rev_paths |>
  filter(who == GT_LAB) |>
  group_by(country, label) |>
  group_modify(~ tibble(bend_wave = bend_wave_of(.x))) |>
  ungroup() |>
  left_join(distinct(rev_paths, country, wave, year),
            by = c("country", "bend_wave" = "wave")) |>
  rename(bend_x = year)

ts_long <- rev_paths |>
  pivot_longer(c(Dim1, Dim2), names_to = "dim", values_to = "score") |>
  mutate(dim = factor(DIM_LAB[dim], levels = DIM_LAB), is_gt = who == GT_LAB)

bends_ts <- tidyr::crossing(bends, dim = factor(DIM_LAB, levels = DIM_LAB))

## ---- plot ------------------------------------------------------------------
figA <- ggplot(ts_long, aes(year, score, colour = who, group = who)) +
  geom_vline(data = bends_ts, aes(xintercept = bend_x), inherit.aes = FALSE,
             linetype = "22", colour = "grey65", linewidth = .35) +
  geom_line(data  = ~ filter(.x, !is_gt), linewidth = .45, alpha = .9) +
  geom_point(data = ~ filter(.x, !is_gt), size = .8) +
  geom_line(data  = ~ filter(.x,  is_gt), linewidth = .9) +
  geom_point(data = ~ filter(.x,  is_gt), size = 1.5) +
  facet_grid(dim ~ label, scales = "free", switch = "y") +
  scale_colour_manual(values = WHO_COLS, breaks = WHO_ORDER) +
  x_scale +
  labs(x = x_lab, y = NULL) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor  = element_blank(),
        panel.grid.major  = element_line(colour = "grey93", linewidth = .3),
        panel.spacing     = unit(7, "pt"),
        strip.placement   = "outside",
        strip.text.x      = element_text(size = 8, colour = "grey20"),
        strip.text.y.left = element_text(angle = 90, size = 7.5, colour = "grey20"),
        axis.text         = element_text(size = 7, colour = "grey40"),
        axis.title        = element_text(size = 8.5),
        legend.position   = "bottom",
        legend.title       = element_blank()) +
  guides(colour = guide_legend(nrow = 1,
                               override.aes = list(linewidth = c(.9, rep(.45, 4)),
                                                   size      = c(1.5, rep(.8, 4)))))

ggsave("fig3_timeseries_grid.pdf", figA, width = 7.2, height = 4.4,
       device = cairo_pdf)
message("wrote fig3_timeseries_grid.pdf")