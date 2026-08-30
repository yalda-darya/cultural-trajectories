message("fig1_implicit_anchor.R  [rev E]")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(forcats)
  library(scales)
  library(patchwork)
})

## ---- shared setup ----------------------------------------------------------

PAL <- c(
  "Gemini 3.6 Flash" = "#1B9E77",
  "Claude Opus 4.8"  = "#D9820B",
  "GPT-5.5"          = "#4C9BE8",
  "Qwen3.6-Plus"     = "#C86BA5"
)

MODEL_ORDER <- names(PAL)

relabel <- function(x) {
  dplyr::recode(
    as.character(x),
    "gemini-3.6-flash"  = "Gemini 3.6 Flash",
    "claude-opus-4-8"   = "Claude Opus 4.8",
    "gpt-5.5"           = "GPT-5.5",
    "Qwen/Qwen3.6-Plus" = "Qwen3.6-Plus"
  )
}

## idempotent: safe on raw IDs or on already-relabelled values
as_model <- function(x) {
  factor(relabel(x), levels = MODEL_ORDER)
}

th <- theme_minimal(base_size = 9) +
  theme(
    legend.position   = "bottom",
    legend.title      = element_blank(),
    legend.key.width  = unit(1.4, "lines"),
    legend.margin     = margin(t = 0, b = 0),
    panel.grid.minor  = element_blank(),
    plot.tag          = element_text(face = "bold", size = 11),
    plot.tag.position = c(0.005, 0.99),
    axis.title        = element_text(size = 8.5)
  )

## ---- data ------------------------------------------------------------------

cls_file <- c("classification_verified.rds", "classification.rds")
cls_file <- cls_file[file.exists(cls_file)]

if (!length(cls_file)) {
  stop("no classification file found in ", getwd())
}

if (cls_file[1] != "classification_verified.rds") {
  warning(
    "using ", cls_file[1],
    "; classification_verified.rds not found. ",
    "Check that this matches the classification reported in Table 1.",
    call. = FALSE
  )
}

message("classification: ", cls_file[1])

model_coords <- readRDS("model_coords.rds") |>
  mutate(model = as_model(model))

coords <- readRDS("country_wave_coords.rds")

clsf <- readRDS(cls_file[1]) |>
  select(country = iso, class)

stopifnot(identical(levels(model_coords$model), MODEL_ORDER))

gt <- coords |>
  transmute(
    country = iso,
    wave,
    gt1 = Dim1,
    gt2 = Dim2
  )

## C1 = country named, no year. Mean over elicitations.
c1 <- model_coords |>
  filter(condition == "C1") |>
  group_by(model, country) |>
  summarise(
    m1 = mean(Dim1),
    m2 = mean(Dim2),
    .groups = "drop"
  )

moving <- clsf |>
  filter(class != "stable") |>
  pull(country)

## ---- checks ----------------------------------------------------------------

if (length(moving) != 36) {
  stop(
    "expected 36 moving countries, got ", length(moving),
    ". Check the class labels: ",
    paste(sort(unique(clsf$class)), collapse = ", ")
  )
}

lost <- setdiff(moving, unique(c1$country))

if (length(lost)) {
  stop(
    "moving countries absent from the C1 coordinates: ",
    paste(lost, collapse = ", ")
  )
}

## ---- distance from each model's C1 answer to every survey wave -------------

## pos = 0 for a country's most recent wave, 1 for the wave before, etc.

wave_pos <- gt |>
  group_by(country) |>
  arrange(desc(wave), .by_group = TRUE) |>
  mutate(pos = row_number() - 1L) |>
  ungroup()

anchor_long <- c1 |>
  inner_join(
    wave_pos,
    by = "country",
    relationship = "many-to-many"
  ) |>
  filter(country %in% moving) |>
  mutate(
    d = sqrt((m1 - gt1)^2 + (m2 - gt2)^2)
  )

## 4 models x (14 countries x 4 waves + 22 x 3) = 488
if (nrow(anchor_long) != 488) {
  warning(
    "anchor_long has ", nrow(anchor_long),
    " rows, expected 488. ",
    "Wave coverage may differ from 14 four-wave and 22 three-wave countries.",
    call. = FALSE
  )
}

## ---- Panel A: mean distance by wave position -------------------------------

## positions 0-2 only: all 36 moving countries are observed at three waves,
## but only 14 reach a fourth, so position 3 would mix samples.

curve_df <- anchor_long |>
  filter(pos <= 2) |>
  group_by(model, pos) |>
  summarise(
    mean_d = mean(d),
    n = n_distinct(country),
    .groups = "drop"
  )

stopifnot(all(curve_df$n == 36))

pos_lab <- c(
  "Most\nrecent",
  "1 wave\nearlier",
  "2 waves\nearlier"
)

f2a <- ggplot(
  curve_df,
  aes(pos, mean_d, colour = model)
) +
  geom_line(
    aes(linetype = model),
    linewidth = .7
  ) +
  geom_point(
    aes(shape = model),
    size = 2.1
  ) +
  scale_colour_manual(values = PAL) +
  scale_linetype_manual(
    values = c(
      "solid",
      "22",
      "42",
      "1343"
    )
  ) +
  scale_shape_manual(
    values = c(
      16,
      17,
      15,
      18
    )
  ) +
  scale_x_continuous(
    breaks = 0:2,
    labels = pos_lab,
    expand = expansion(add = .25)
  ) +
  labs(
    x = "Survey wave, relative to each country's most recent",
    y = "Mean distance to true position"
  ) +
  th

## ---- Panel B: which wave each country anchors to ---------------------------

## Every country contributes exactly one anchor, so the four segments in a row
## sum to 36 by construction. complete() keeps empty cells explicit so a zero
## is visible as a zero rather than as a silently missing category.

LAB_LEVELS <- c(
  "3 waves back",
  "2 waves back",
  "1 wave back",
  "Most recent"
)

bar_df <- anchor_long |>
  group_by(model, country) |>
  slice_min(
    d,
    n = 1,
    with_ties = FALSE
  ) |>
  ungroup() |>
  count(model, pos) |>
  complete(
    model,
    pos = 0:3,
    fill = list(n = 0L)
  ) |>
  group_by(model) |>
  arrange(pos, .by_group = TRUE) |>
  mutate(
    frac = n / sum(n),
    top  = cumsum(frac),
    mid  = top - frac / 2
  ) |>
  ungroup() |>
  mutate(
    pos_f   = factor(pos, levels = 3:0, labels = LAB_LEVELS),
    
    ## White text on the two darker segments; dark text on the lighter ones.
    lab_col = ifelse(
      pos %in% c(0, 1),
      "white",
      "grey15"
    ),
    
    yy = fct_rev(model)
  )

stopifnot(
  all(
    tapply(
      bar_df$n,
      bar_df$model,
      sum
    ) == 36
  )
)

## Echo the counts so they can be checked against the caption.
cat("\nPanel B counts (rows sum to 36):\n")

bar_df |>
  select(model, pos_f, n) |>
  pivot_wider(
    names_from = pos_f,
    values_from = n
  ) |>
  select(
    model,
    all_of(rev(LAB_LEVELS))
  ) |>
  as.data.frame() |>
  print(row.names = FALSE)

## ---- Label placement -------------------------------------------------------

## All nonzero labels are placed at the midpoint of their own segment.
## This keeps even the small "3 waves back" segments inside the bar.

lab_in <- bar_df |>
  filter(n > 0) |>
  mutate(ylab = mid)

cat("\nLabel positions:\n")

lab_in |>
  select(
    model,
    pos_f,
    n,
    bar_ends_at = top,
    label_at = ylab
  ) |>
  as.data.frame() |>
  print(row.names = FALSE)

cat("\n")

## ---- Panel B plot ----------------------------------------------------------

f2b <- ggplot(
  bar_df,
  aes(yy, frac, fill = pos_f)
) +
  geom_col(
    width = .6,
    colour = "white",
    linewidth = .4
  ) +
  
  ## Every label is centered within its own segment.
  geom_text(
    data = lab_in,
    aes(
      x = yy,
      y = ylab,
      label = n,
      colour = lab_col
    ),
    size = 2.6,
    inherit.aes = FALSE,
    show.legend = FALSE
  ) +
  
  scale_colour_identity() +
  
  scale_fill_manual(
    values = c(
      "Most recent"  = "#2C6E8F",
      "1 wave back"  = "#6FA3BC",
      "2 waves back" = "#AFC9D8",
      "3 waves back" = "#E2E9EE"
    )
  ) +
  
  scale_x_discrete(
    expand = expansion(add = .55)
  ) +
  
  scale_y_continuous(
    labels = percent,
    expand = expansion(mult = c(0, .055))
  ) +
  
  coord_flip(
    clip = "off"
  ) +
  
  labs(
    x = NULL,
    y = "Share of the 36 moving countries"
  ) +
  
  guides(
    fill = guide_legend(
      reverse = TRUE,
      nrow = 1
    )
  ) +
  
  th

## ---- combine and export ----------------------------------------------------

fig2 <- (f2a / f2b) +
  plot_layout(
    heights = c(1, .8)
  ) +
  plot_annotation(
    tag_levels = "A"
  )

dev <- if (isTRUE(capabilities("cairo"))) {
  grDevices::cairo_pdf
} else {
  grDevices::pdf
}

ggsave(
  "fig2_implicit_anchor.pdf",
  fig2,
  device = dev,
  width = 6.5,
  height = 6.4,
  units = "in"
)

message("wrote fig1_implicit_anchor.pdf")