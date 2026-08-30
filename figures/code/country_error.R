## =============================================================================
## figS_country_error.R

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

theme_pub <- function(base = 8.5) {
  theme_minimal(base_size = base) +
    theme(
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(
        colour = "grey92",
        linewidth = 0.3
      ),
      axis.title = element_text(
        size = base,
        colour = "grey20"
      ),
      axis.text = element_text(
        size = base - 0.5,
        colour = "grey30"
      ),
      plot.title = element_text(
        size = base + 2,
        face = "bold",
        colour = "grey10"
      ),
      plot.subtitle = element_text(
        size = base - 0.5,
        colour = "grey40",
        lineheight = 1.25
      ),
      strip.text = element_text(
        size = base,
        face = "bold",
        colour = "grey20"
      ),
      legend.position = "bottom",
      legend.title = element_blank(),
      legend.key.height = grid::unit(8, "pt"),
      plot.margin = margin(4, 6, 4, 4)
    )
}

# -----------------------------------------------------------------------------
# Load data
# -----------------------------------------------------------------------------

c2_matched <- readRDS("c2_matched.rds") |>
  mutate(model = as_model(model))

coords <- readRDS("country_wave_coords.rds")

gt <- coords |>
  transmute(
    country = iso,
    wave,
    gt1 = Dim1,
    gt2 = Dim2
  )

latest_gt <- gt |>
  group_by(country) |>
  filter(wave == max(wave)) |>
  ungroup()

c2_latest <- c2_matched |>
  group_by(model, country) |>
  filter(wave == max(wave)) |>
  ungroup()

# -----------------------------------------------------------------------------
# Compute placement error
# -----------------------------------------------------------------------------

map_all <- c2_latest |>
  left_join(latest_gt, by = c("country", "wave")) |>
  transmute(
    model,
    country,
    label = ifelse(
      country %in% names(CNAME),
      CNAME[country],
      country
    ),
    err = sqrt((Dim1 - gt1)^2 + (Dim2 - gt2)^2)
  )

xmax <- max(map_all$err) * 1.06

# -----------------------------------------------------------------------------
# Plot function
# -----------------------------------------------------------------------------

make_country_plot <- function(m) {
  
  d <- map_all |>
    filter(model == m) |>
    mutate(label = fct_reorder(label, err))
  
  mu <- mean(d$err)
  
  ggplot(d, aes(err, label)) +
    
    geom_vline(
      xintercept = mu,
      linetype = "22",
      colour = "grey45",
      linewidth = 0.4
    ) +
    
    annotate(
      "text",
      x = mu,
      y = Inf,
      label = sprintf("mean %.3f", mu),
      hjust = -0.1,
      vjust = 1.4,
      size = 2.4,
      colour = "grey40"
    ) +
    
    geom_segment(
      aes(x = 0, xend = err, yend = label),
      colour = "grey85",
      linewidth = 0.35
    ) +
    
    geom_point(
      aes(fill = err),
      shape = 21,
      colour = "white",
      size = 2.6,
      stroke = 0.4
    ) +
    
    scale_fill_viridis_c(
      option = "viridis",
      direction = -1,
      limits = c(0, xmax),
      guide = "none"
    ) +
    
    scale_x_continuous(
      limits = c(0, xmax),
      expand = expansion(mult = c(0, 0.04))
    ) +
    
    labs(
      x = "Distance to most recent surveyed position",
      y = NULL
    ) +
    
    theme_pub() +
    
    theme(
      panel.grid.major.y = element_blank(),
      axis.text.y = element_text(size = 7)
    )
}

# -----------------------------------------------------------------------------
# Export
# -----------------------------------------------------------------------------

slugify <- function(x) {
  tolower(gsub("[^A-Za-z0-9]+", "_", x))
}

for (m in MODEL_ORDER) {
  
  ggsave(
    paste0("figS_country_", slugify(m), ".pdf"),
    make_country_plot(m),
    width = 5.2,
    height = 7.2,
    device = cairo_pdf
  )
  
  message("Wrote figure for ", m)
}
