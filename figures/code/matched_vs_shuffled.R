suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(forcats)
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

stepcos <- readRDS("trajectory_stepcos.rds") |>
  mutate(model = as_model(model))

clsf <- readRDS("classification.rds") |>
  select(country = iso, class)

# -----------------------------------------------------------------------------
# Prepare data
# -----------------------------------------------------------------------------

step_all <- stepcos |>
  filter(class != "stable")

step_four <- step_all |>
  filter(n_steps >= 3)

dumb <- bind_rows(
  
  step_all |>
    group_by(model) |>
    summarise(
      obs = mean(obs_cos),
      nul = mean(null_mean),
      .groups = "drop"
    ) |>
    mutate(
      set = "All movers (n = 36)"
    ),
  
  step_four |>
    group_by(model) |>
    summarise(
      obs = mean(obs_cos),
      nul = mean(null_mean),
      .groups = "drop"
    ) |>
    mutate(
      set = "Four-wave only (n = 14)"
    )
  
) |>
  mutate(
    set = factor(
      set,
      levels = c(
        "All movers (n = 36)",
        "Four-wave only (n = 14)"
      )
    ),
    yy = as.numeric(fct_rev(model)) +
      ifelse(
        set == "All movers (n = 36)",
        0.17,
        -0.17
      )
  )

# -----------------------------------------------------------------------------
# Plot
# -----------------------------------------------------------------------------

fS_dumb <- ggplot(dumb) +
  
  geom_segment(
    aes(
      x = nul,
      xend = obs,
      y = yy,
      yend = yy,
      colour = model,
      alpha = set,
      linetype = set
    ),
    linewidth = 1.5,
    lineend = "round"
  ) +
  
  geom_point(
    aes(nul, yy),
    shape = 21,
    fill = "white",
    colour = "grey35",
    size = 2.1,
    stroke = 0.6
  ) +
  
  geom_point(
    aes(
      obs,
      yy,
      colour = model,
      alpha = set
    ),
    size = 2.7
  ) +
  
  scale_colour_manual(
    values = PAL,
    guide = "none"
  ) +
  
  scale_alpha_manual(
    values = c(
      "All movers (n = 36)" = 1,
      "Four-wave only (n = 14)" = 0.45
    )
  ) +
  
  scale_linetype_manual(
    values = c(
      "All movers (n = 36)" = "solid",
      "Four-wave only (n = 14)" = "solid"
    )
  ) +
  
  scale_y_continuous(
    breaks = 1:4,
    labels = rev(MODEL_ORDER),
    expand = expansion(add = 0.45)
  ) +
  
  labs(
    x = "Step alignment with the true trajectory",
    y = NULL
  ) +
  
  th

# -----------------------------------------------------------------------------
# Export
# -----------------------------------------------------------------------------

ggsave(
  "figS_matched_vs_shuffled.pdf",
  fS_dumb,
  width = 6.2,
  height = 3.2,
  device = cairo_pdf
)

message("Wrote figS_matched_vs_shuffled.pdf")