suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
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
# Bootstrap function
# -----------------------------------------------------------------------------

B <- 2000

boot_ci <- function(df, col, FUN = mean) {
  
  W <- df |>
    select(
      model,
      country,
      val = all_of(col)
    ) |>
    pivot_wider(
      names_from = model,
      values_from = val
    ) |>
    arrange(country)
  
  M <- as.matrix(W[, -1])
  n <- nrow(M)
  
  stopifnot(n > 0)
  
  set.seed(42)
  
  bm <- matrix(
    NA_real_,
    B,
    ncol(M),
    dimnames = list(
      NULL,
      colnames(M)
    )
  )
  
  for (b in 1:B) {
    
    bm[b, ] <- apply(
      M[
        sample.int(n, n, TRUE),
        ,
        drop = FALSE
      ],
      2,
      FUN,
      na.rm = TRUE
    )
  }
  
  tibble(
    model = factor(
      colnames(M),
      levels = MODEL_ORDER
    ),
    est = apply(
      bm,
      2,
      median,
      na.rm = TRUE
    ),
    lo = apply(
      bm,
      2,
      quantile,
      0.025,
      na.rm = TRUE
    ),
    hi = apply(
      bm,
      2,
      quantile,
      0.975,
      na.rm = TRUE
    )
  )
}

# -----------------------------------------------------------------------------
# Load data
# -----------------------------------------------------------------------------

model_coords <- readRDS("model_coords.rds") |>
  mutate(model = as_model(model))

c2_matched <- readRDS("c2_matched.rds") |>
  mutate(model = as_model(model))

# -----------------------------------------------------------------------------
# Condition-level coordinates
# -----------------------------------------------------------------------------

cond_wide <- model_coords |>
  filter(condition %in% c("C0", "C1")) |>
  group_by(model, country, condition) |>
  summarise(
    x = mean(Dim1),
    y = mean(Dim2),
    .groups = "drop"
  ) |>
  pivot_wider(
    names_from = condition,
    values_from = c(x, y)
  )

c1 <- cond_wide |>
  select(
    model,
    country,
    m1 = x_C1,
    m2 = y_C1
  )

# -----------------------------------------------------------------------------
# Country instruction effect
# -----------------------------------------------------------------------------

country_eff <- cond_wide |>
  mutate(
    val = sqrt(
      (x_C0 - x_C1)^2 +
        (y_C0 - y_C1)^2
    )
  ) |>
  boot_ci("val") |>
  mutate(
    instr = "Naming the country"
  )

# -----------------------------------------------------------------------------
# Year instruction effect
# -----------------------------------------------------------------------------

c2_latest <- c2_matched |>
  group_by(model, country) |>
  filter(wave == max(wave)) |>
  ungroup()

year_eff <- c1 |>
  inner_join(
    select(
      c2_latest,
      model,
      country,
      Dim1,
      Dim2,
      gt1,
      gt2
    ),
    by = c("model", "country")
  ) |>
  mutate(
    val =
      sqrt(
        (m1 - gt1)^2 +
          (m2 - gt2)^2
      ) -
      sqrt(
        (Dim1 - gt1)^2 +
          (Dim2 - gt2)^2
      )
  ) |>
  boot_ci("val") |>
  mutate(
    instr = "Naming the year"
  )

# -----------------------------------------------------------------------------
# Combine
# -----------------------------------------------------------------------------

instr_df <- bind_rows(
  country_eff,
  year_eff
) |>
  mutate(
    instr = factor(
      instr,
      levels = c(
        "Naming the country",
        "Naming the year"
      )
    ),
    yy = as.numeric(fct_rev(model)) +
      ifelse(
        instr == "Naming the country",
        0.15,
        -0.15
      )
  )

stopifnot(nrow(instr_df) == 8)

# -----------------------------------------------------------------------------
# Plot
# -----------------------------------------------------------------------------

fS_instr <- ggplot(instr_df) +
  
  geom_vline(
    xintercept = 0,
    colour = "grey60",
    linetype = "22",
    linewidth = 0.45
  ) +
  
  geom_segment(
    aes(
      x = lo,
      xend = hi,
      y = yy,
      yend = yy,
      colour = model
    ),
    linewidth = 0.9,
    lineend = "round"
  ) +
  
  geom_point(
    aes(
      x = est,
      y = yy,
      colour = model,
      shape = instr
    ),
    size = 2.8,
    fill = "white",
    stroke = 0.9
  ) +
  
  scale_colour_manual(
    values = PAL,
    guide = "none"
  ) +
  
  scale_shape_manual(
    values = c(
      "Naming the country" = 16,
      "Naming the year" = 21
    )
  ) +
  
  scale_y_continuous(
    breaks = 1:4,
    labels = rev(MODEL_ORDER),
    expand = expansion(add = 0.45)
  ) +
  
  scale_x_continuous(
    limits = c(-0.05, 0.65)
  ) +
  
  labs(
    x = "Effect on the model's answer",
    y = NULL
  ) +
  
  th

# -----------------------------------------------------------------------------
# Export
# -----------------------------------------------------------------------------

ggsave(
  "figS_instruction_contrast.pdf",
  fS_instr,
  width = 6.4,
  height = 3.0,
  device = cairo_pdf
)

message("Wrote figS_instruction_contrast.pdf")