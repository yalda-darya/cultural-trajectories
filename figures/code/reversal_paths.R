suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
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

CNAME <- c(
  ARG="Argentina", AUS="Australia", BRA="Brazil", CAN="Canada", CHL="Chile",
  CHN="China", COL="Colombia", CYP="Cyprus", DEU="Germany", EGY="Egypt",
  HKG="Hong Kong", IDN="Indonesia", IND="India", IRN="Iran", IRQ="Iraq",
  JOR="Jordan", JPN="Japan", KGZ="Kyrgyzstan", KOR="South Korea", MAR="Morocco",
  MEX="Mexico", MYS="Malaysia", NGA="Nigeria", NLD="Netherlands",
  NZL="New Zealand", PAK="Pakistan", PER="Peru", PHL="Philippines",
  ROU="Romania", RUS="Russia", SGP="Singapore", SRB="Serbia", THA="Thailand",
  TUR="Turkey", TWN="Taiwan", UKR="Ukraine", URY="Uruguay",
  USA="United States", VNM="Vietnam", ZWE="Zimbabwe"
)

REV6 <- c(
  "IDN",
  "IND",
  "JOR",
  "JPN",
  "KOR",
  "ZWE"
)

# -----------------------------------------------------------------------------
# Theme
# -----------------------------------------------------------------------------

th <- theme_minimal(base_size = 9) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(
      colour = "grey92",
      linewidth = 0.3
    ),
    axis.title = element_text(
      size = 9,
      colour = "grey20"
    ),
    axis.text = element_text(
      size = 8,
      colour = "grey30"
    ),
    legend.position = "bottom",
    legend.title = element_blank(),
    legend.key.height = grid::unit(8, "pt"),
    plot.margin = margin(4, 6, 4, 4)
  )

# -----------------------------------------------------------------------------
# Load data
# -----------------------------------------------------------------------------

c2_matched <- readRDS("c2_matched.rds") |>
  mutate(model = as_model(model))

# -----------------------------------------------------------------------------
# WVS paths
# -----------------------------------------------------------------------------

truth_path <- c2_matched |>
  filter(country %in% REV6) |>
  distinct(
    country,
    wave,
    Dim1 = gt1,
    Dim2 = gt2
  ) |>
  arrange(country, wave) |>
  mutate(
    who = "World Values Survey"
  )

# -----------------------------------------------------------------------------
# Model paths
# -----------------------------------------------------------------------------

model_path <- c2_matched |>
  filter(country %in% REV6) |>
  select(
    model,
    country,
    wave,
    Dim1,
    Dim2
  ) |>
  arrange(model, country, wave) |>
  rename(
    who = model
  )

# -----------------------------------------------------------------------------
# Combine
# -----------------------------------------------------------------------------

paths <- bind_rows(
  truth_path,
  model_path
) |>
  mutate(
    who = factor(
      who,
      levels = c(
        "World Values Survey",
        MODEL_ORDER
      )
    ),
    label = CNAME[country],
    is_gt = who == "World Values Survey"
  )

# -----------------------------------------------------------------------------
# Arrow
# -----------------------------------------------------------------------------

arw <- arrow(
  length = grid::unit(0.085, "in"),
  type = "open",
  angle = 25
)

# -----------------------------------------------------------------------------
# Figure
# -----------------------------------------------------------------------------

f4 <- ggplot(
  paths,
  aes(Dim1, Dim2, group = who)
) +
  
  geom_path(
    data = ~ filter(.x, !is_gt),
    aes(colour = who),
    linewidth = 0.4,
    alpha = 0.85,
    arrow = arw
  ) +
  
  geom_point(
    data = ~ filter(.x, !is_gt),
    aes(colour = who),
    size = 0.7
  ) +
  
  geom_path(
    data = ~ filter(.x, is_gt),
    aes(colour = who),
    linewidth = 0.75,
    arrow = arw
  ) +
  
  geom_point(
    data = ~ filter(.x, is_gt),
    aes(colour = who),
    size = 1.4
  ) +
  
  scale_colour_manual(
    values = c(
      "World Values Survey" = "grey15",
      PAL
    ),
    breaks = c(
      "World Values Survey",
      MODEL_ORDER
    )
  ) +
  
  facet_wrap(
    ~ label,
    nrow = 2,
    scales = "free"
  ) +
  
  labs(
    x = "Traditional \u2192 secular-rational",
    y = "Survival \u2192 self-expression"
  ) +
  
  th +
  
  theme(
    legend.position = "bottom",
    legend.title = element_blank(),
    axis.text = element_text(size = 7),
    panel.spacing = grid::unit(10, "pt")
  ) +
  
  guides(
    colour = guide_legend(
      nrow = 1,
      override.aes = list(
        linewidth = c(
          0.75,
          rep(0.4, 4)
        ),
        arrow = NULL
      )
    )
  )

# -----------------------------------------------------------------------------
# Export
# -----------------------------------------------------------------------------

ggsave(
  "figS_reversal_paths.pdf",
  f4,
  width = 6.5,
  height = 4.8,
  device = cairo_pdf
)

message("Wrote figS_reversal_paths.pdf")