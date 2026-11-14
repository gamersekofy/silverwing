#!/usr/bin/env Rscript
# Cleaning, feature engineering, and EDA for the US YouTube trending data.
#
# Produces:
#   analysis/output/videos.csv            video-level (deduplicated) table
#   analysis/output/summary_*.csv         numeric summaries used in the report
#   analysis/output/cleaning_log.txt      step-by-step row counts
#   analysis/output/figures/fig*.png      the 8 EDA figures
#
# Run:  Rscript analysis/clean_eda.R



# --- paths -------------------------------------------------------------------
script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) > 0) return(normalizePath(sub("^--file=", "", hit[[1]]), mustWork = FALSE))
  normalizePath(".", mustWork = FALSE)
}
ROOT <- dirname(dirname(script_path()))
DATA <- file.path(ROOT, "data")
OUT  <- file.path(ROOT, "analysis", "output")
FIGS <- file.path(OUT, "figures")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

source(file.path(ROOT, "analysis", "data_core.R"))
# Reuse the PPR1 preparation without plotting-package dependencies when requested.
if ("--data-only" %in% commandArgs(trailingOnly = TRUE)) {
  baseline <- prepare_ppr1_data(DATA)
  videos <- baseline$videos
  videos$high_views <- as.integer(videos$views >= quantile(videos$views, .75))
  write.csv(videos, file.path(OUT, "videos.csv"), row.names = FALSE)
  write.csv(data.frame(step = names(baseline$counts), rows = baseline$counts),
    file.path(OUT, "summary_cleaning_counts.csv"), row.names = FALSE)
  cat("PPR1 shared preparation: 6348 videos; EDA plots not regenerated.\n")
  quit(save = "no", status = 0)
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(forcats)
  library(ggplot2)
  library(patchwork)
})

invisible(suppressWarnings(try(Sys.setlocale("LC_ALL", "C.UTF-8"), silent = TRUE)))

# Bias-corrected sample skewness (Fisher-Pearson g1); e1071 type 2.
# (e1071's *default* is type 3, so the type is stated explicitly.)
skew <- function(x) e1071::skewness(x, na.rm = TRUE, type = 2)

LOG <- "\n[clean_eda] "
step_log <- character(0)
log_msg <- function(...) {
  msg <- paste0(...)
  cat(LOG, msg, "\n", sep = "")
  step_log[[length(step_log) + 1L]] <<- msg
}

savefig <- function(plot, name) {
  path <- file.path(FIGS, paste0(name, ".png"))
  ggsave(path, plot, width = 13, height = 5, dpi = 140, bg = "white")
  log_msg("wrote figure ", sub(paste0(ROOT, "/"), "", path, fixed = TRUE))
}

main <- function() {
  baseline <- prepare_ppr1_data(DATA)
  raw <- as_tibble(baseline$raw)
  videos <- as_tibble(baseline$videos)
  counts <- baseline$counts
  for (step in names(counts)) log_msg(sprintf("%s: %d rows", step, counts[[step]]))
  q75 <- quantile(videos$views, .75)
  videos <- videos |> mutate(high_views = as.integer(views >= q75))
  log_msg(sprintf("top-quartile views threshold = %s; positives = %.1f%%",
    format(round(q75), big.mark = ","), 100 * mean(videos$high_views)))

  write_csv(videos, file.path(OUT, "videos.csv"))

  # ---- persistence / summary tables -------------------------------------
  tibble(step = names(counts), rows = as.integer(counts)) |>
    write_csv(file.path(OUT, "summary_cleaning_counts.csv"))

  num <- c("views", "likes", "dislikes", "comment_count")
  numeric_summary <- function(df, vars) {
    purrr::map_dfr(vars, function(v) {
      x <- df[[v]]
      tibble(
        variable = v, count = sum(!is.na(x)), mean = mean(x), sd = sd(x),
        min = min(x), q25 = unname(quantile(x, .25)), median = median(x),
        q75 = unname(quantile(x, .75)), q90 = unname(quantile(x, .90)),
        q99 = unname(quantile(x, .99)), max = max(x), skew = skew(x)
      )
    })
  }
  write_csv(numeric_summary(videos, num), file.path(OUT, "summary_numeric.csv"))

  videos |>
    group_by(category) |>
    summarise(count = n(), mean = mean(log_views), median = median(log_views),
              std = sd(log_views), .groups = "drop") |>
    arrange(desc(median)) |>
    write_csv(file.path(OUT, "summary_by_category.csv"))

  videos |>
    group_by(publish_hour) |>
    summarise(mean = mean(log_views), .groups = "drop") |>
    arrange(publish_hour) |>
    write_csv(file.path(OUT, "summary_by_hour.csv"))

  videos |>
    group_by(publish_dayofweek) |>
    summarise(mean = mean(log_views), .groups = "drop") |>
    arrange(publish_dayofweek) |>
    write_csv(file.path(OUT, "summary_by_dow.csv"))

  # ---- figures (verification copies; see file header) -------------------
  # Fig 1: raw vs log views
  fig1a <- ggplot(videos, aes(x = views)) +
    geom_histogram(bins = 60, fill = "#c44e52", colour = "white") +
    labs(title = sprintf("Raw views (skew = %.1f)", skew(videos$views)),
         x = "views", y = "count") + theme_bw()
  fig1b <- ggplot(videos, aes(x = log_views)) +
    geom_histogram(bins = 60, fill = "#4c72b0", colour = "white") +
    labs(title = sprintf("log(1 + views) (skew = %.2f)", skew(videos$log_views)),
         x = "log(1 + views)", y = "count") + theme_bw()
  savefig(fig1a + fig1b, "fig01_views_transform")

  # Fig 2: log views by category
  fig2 <- videos |>
    mutate(category = fct_reorder(category, log_views, median)) |>
    ggplot(aes(x = log_views, y = category)) +
    geom_boxplot(fill = "#4c72b0", outlier.size = 1) +
    labs(title = "log(1 + views) by category (video level)", x = "log(1 + views)", y = NULL) +
    theme_bw()
  savefig(fig2, "fig02_logviews_by_category")

  # Fig 3: engagement rates by category
  eng <- videos |>
    select(category, like_rate, comment_rate) |>
    pivot_longer(-category, names_to = "metric", values_to = "rate")
  order2 <- videos |> group_by(category) |>
    summarise(m = median(like_rate), .groups = "drop") |> arrange(desc(m)) |> pull(category)
  fig3 <- eng |>
    mutate(category = factor(category, levels = order2)) |>
    ggplot(aes(x = rate, y = category, fill = metric)) +
    geom_boxplot(outlier.size = 0.5) +
    coord_cartesian(xlim = c(0, 0.15)) +
    labs(title = "Engagement ratios by category", x = "ratio", y = NULL) +
    theme_bw()
  savefig(fig3, "fig03_engagement_by_category")

  # Fig 4: flags vs log views
  fig4a <- ggplot(videos, aes(x = comments_disabled, y = log_views)) +
    geom_boxplot(fill = "#55a868", outlier.size = 1) +
    labs(title = sprintf("comments_disabled\n(TRUE n=%d)", sum(videos$comments_disabled)),
         x = "comments_disabled", y = "log(1 + views)") + theme_bw()
  fig4b <- ggplot(videos, aes(x = ratings_disabled, y = log_views)) +
    geom_boxplot(fill = "#55a868", outlier.size = 1) +
    labs(title = sprintf("ratings_disabled\n(TRUE n=%d)", sum(videos$ratings_disabled)),
         x = "ratings_disabled", y = "log(1 + views)") + theme_bw()
  savefig(fig4a + fig4b, "fig04_flags_vs_views")

  # Fig 5: publish hour & day of week
  hourly <- videos |> group_by(publish_hour) |>
    summarise(m = mean(log_views), .groups = "drop")
  dow_names <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
  dow <- videos |> group_by(publish_dayofweek) |>
    summarise(m = mean(log_views), .groups = "drop") |>
    mutate(day = factor(dow_names[publish_dayofweek + 1L], levels = dow_names))
  fig5a <- ggplot(hourly, aes(x = publish_hour, y = m)) +
    geom_line(colour = "#c44e52") + geom_point(colour = "#c44e52") +
    labs(title = "Mean log(1 + views) by publish hour (UTC)",
         x = "publish hour (UTC)", y = "mean log(1 + views)") + theme_bw()
  fig5b <- ggplot(dow, aes(x = day, y = m)) +
    geom_col(fill = "#8172b3") +
    labs(title = "Mean log(1 + views) by publish day", x = NULL,
         y = "mean log(1 + views)") + theme_bw()
  savefig(fig5a + fig5b, "fig05_time_effects")

  # Fig 6: title length & tag count
  fig6a <- ggplot(videos, aes(x = title_length, y = log_views)) +
    geom_point(alpha = 0.25, size = 0.7) +
    geom_smooth(method = "lm", colour = "red", se = FALSE) +
    labs(title = sprintf("log(1 + views) vs title length (r=%.2f)",
                         cor(videos$title_length, videos$log_views)),
         x = "title length (characters)", y = "log(1 + views)") + theme_bw()
  fig6b <- ggplot(videos, aes(x = tag_count, y = log_views)) +
    geom_point(alpha = 0.25, size = 0.7) +
    geom_smooth(method = "lm", colour = "red", se = FALSE) +
    labs(title = sprintf("log(1 + views) vs tag count (r=%.2f)",
                         cor(videos$tag_count, videos$log_views)),
         x = "tag count", y = "log(1 + views)") + theme_bw()
  savefig(fig6a + fig6b, "fig06_text_metrics")

  # Fig 7: correlation heatmap
  corr_cols <- c("log_views", "log_likes", "log_dislikes", "log_comments",
                 "like_rate", "comment_rate", "dislike_rate", "title_length",
                 "title_word_count", "tag_count", "publish_hour", "days_to_trend")
  cm <- cor(videos[corr_cols], use = "pairwise.complete.obs")
  cm_long <- as.data.frame(as.table(cm)) |>
    rename(var1 = Var1, var2 = Var2, value = Freq)
  fig7 <- ggplot(cm_long, aes(x = var1, y = var2, fill = value)) +
    geom_tile() +
    geom_text(aes(label = sprintf("%.2f", value)), size = 2.4) +
    scale_fill_gradient2(low = "#3b4cc0", mid = "white", high = "#b40426",
                         midpoint = 0, limits = c(-1, 1)) +
    coord_fixed() +
    labs(title = "Correlation matrix (video level)", x = NULL, y = NULL) +
    theme_bw() + theme(axis.text.x = element_text(angle = 45, hjust = 1))
  savefig(fig7, "fig07_correlation")

  # Fig 8: class balance + snapshot multiplicity
  fig8a <- videos |> count(high_views) |>
    mutate(label = c("Not top quartile (0)", "Top quartile (1)")[high_views + 1L]) |>
    ggplot(aes(x = label, y = n)) +
    geom_col(fill = "#4c72b0") +
    labs(title = "Classification target: top-quartile views", x = NULL, y = "videos") +
    theme_bw()
  mult <- raw |> count(video_id) |> count(n, name = "nn")
  fig8b <- ggplot(mult, aes(x = n, y = nn)) +
    geom_col(fill = "#c44e52") +
    labs(title = "Trending snapshots per video (raw data)",
         x = "number of daily snapshots", y = "videos") + theme_bw()
  savefig(fig8a + fig8b, "fig08_class_and_multiplicity")

  # ---- human-readable cleaning log --------------------------------------
  writeLines(step_log, file.path(OUT, "cleaning_log.txt"))
  log_msg("done")
}

main()
