suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(patchwork)
})

# -----------------------------------------------------------------------------
# Shared settings
# -----------------------------------------------------------------------------

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
    "gemini-3.6-flash" = "Gemini 3.6 Flash",
    "claude-opus-4-8" = "Claude Opus 4.8",
    "gpt-5.5" = "GPT-5.5",
    "Qwen/Qwen3.6-Plus" = "Qwen3.6-Plus"
  )
}

as_model <- function(x) {
  factor(relabel(x), levels = MODEL_ORDER)
}

# -----------------------------------------------------------------------------
# Theme
# -----------------------------------------------------------------------------

th <- theme_minimal(base_size = 9) +
  theme(
    legend.position = "none",
    panel.grid.minor = element_blank(),
    plot.tag = element_text(face = "bold", size = 11),
    plot.tag.position = c(0.01, 0.99),
    plot.title = element_text(
      size = 9,
      face = "plain",
      hjust = 0.5
    ),
    axis.title = element_text(size = 8.5)
  )

# -----------------------------------------------------------------------------
# Load data
# -----------------------------------------------------------------------------

net <- readRDS("trajectory_net.rds") |>
  mutate(model = as_model(model))

clsf <- readRDS("classification.rds") |>
  select(country = iso, class)

# -----------------------------------------------------------------------------
# Prepare data
# -----------------------------------------------------------------------------

rate_df <- net |>
  left_join(
    clsf,
    by = "country",
    suffix = c("", "_c")
  ) |>
  mutate(
    kind = ifelse(
      class == "stable",
      "Low-change countries",
      "Moving countries"
    )
  )

rmax <- max(
  c(rate_df$T_mag, rate_df$M_mag),
  na.rm = TRUE
) * 1.04

# -----------------------------------------------------------------------------
# Panel function
# -----------------------------------------------------------------------------

panel_rate <- function(m, show_y, show_x) {
  
  ggplot(
    filter(rate_df, model == m),
    aes(T_mag, M_mag)
  ) +
    
    geom_abline(
      slope = 1,
      intercept = 0,
      linetype = "22",
      colour = "grey45",
      linewidth = 0.45
    ) +
    
    geom_point(
      aes(shape = kind),
      colour = PAL[[m]],
      size = 1.9,
      alpha = 0.85
    ) +
    
    scale_shape_manual(
      values = c(
        "Moving countries" = 16,
        "Low-change countries" = 2
      )
    ) +
    
    coord_fixed(
      xlim = c(0, rmax),
      ylim = c(0, rmax)
    ) +
    
    labs(
      title = m,
      x = if (show_x)
        "Distance the country actually moved"
      else NULL,
      y = if (show_y)
        "Distance the model moved it"
      else NULL
    ) +
    
    th
}

# -----------------------------------------------------------------------------
# Build Figure 3
# -----------------------------------------------------------------------------

f3 <-
  (
    panel_rate(MODEL_ORDER[1], TRUE, FALSE) |
      panel_rate(MODEL_ORDER[2], FALSE, FALSE)
  ) /
  (
    panel_rate(MODEL_ORDER[3], TRUE, TRUE) |
      panel_rate(MODEL_ORDER[4], FALSE, TRUE)
  ) +
  plot_annotation(tag_levels = "A")

# -----------------------------------------------------------------------------
# Export
# -----------------------------------------------------------------------------

ggsave(
  "fig3_rate_flattening.pdf",
  f3,
  width = 6.5,
  height = 6.2,
  device = cairo_pdf
)

message("Wrote fig2_rate_flattening.pdf")
