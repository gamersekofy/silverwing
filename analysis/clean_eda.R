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

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(forcats)
  library(ggplot2)
  library(patchwork)
  library(jsonlite)
})

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

col_types <- cols(
  video_id = col_character(), trending_date = col_character(), title = col_character(),
  channel_title = col_character(), category_id = col_integer(), publish_time = col_character(),
  tags = col_character(), views = col_double(), likes = col_double(), dislikes = col_double(),
  comment_count = col_double(), thumbnail_link = col_character(),
  comments_disabled = col_logical(), ratings_disabled = col_logical(),
  video_error_or_removed = col_logical(), description = col_character()
)

savefig <- function(plot, name) {
  path <- file.path(FIGS, paste0(name, ".png"))
  ggsave(path, plot, width = 13, height = 5, dpi = 140, bg = "white")
  log_msg("wrote figure ", sub(paste0(ROOT, "/"), "", path, fixed = TRUE))
}

main <- function() {
  raw <- read_csv(file.path(DATA, "USvideos.csv"), col_types = col_types, progress = FALSE)
  n0 <- nrow(raw)
  log_msg(sprintf("raw rows = %d, columns = %d", n0, ncol(raw)))

  # ---- parse dates -------------------------------------------------------
  # trending_date uses an unusual YY.DD.MM format (17.14.11 -> 2017-11-14).
  raw <- raw |>
    mutate(
      trending_date_parsed = as.Date(trending_date, format = "%y.%d.%m"),
      publish_time_parsed  = as.POSIXct(publish_time, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
    )
  log_msg(sprintf("trending range %s .. %s", min(raw$trending_date_parsed), max(raw$trending_date_parsed)))
  log_msg(sprintf("publish  range %s .. %s",
                  format(min(raw$publish_time_parsed), tz = "UTC", usetz = TRUE),
                  format(max(raw$publish_time_parsed), tz = "UTC", usetz = TRUE)))

  # ---- cleaning steps with counts ---------------------------------------
  clean <- raw
  counts <- c(raw = n0)

  n_removed_flag <- sum(clean$video_error_or_removed, na.rm = TRUE)
  clean <- clean |> filter(!video_error_or_removed)
  counts[["drop_error_or_removed"]] <- nrow(clean)
  log_msg(sprintf("drop video_error_or_removed: -%d rows (flagged=%d)", n0 - nrow(clean), n_removed_flag))

  before <- nrow(clean)
  clean <- clean |> distinct()
  counts[["drop_full_dup"]] <- nrow(clean)
  log_msg(sprintf("drop fully duplicated rows: -%d rows", before - nrow(clean)))

  before <- nrow(clean)
  # keep the *last* occurrence of each (video_id, trending_date) pair
  clean <- clean |>
    mutate(.row = row_number()) |>
    group_by(video_id, trending_date_parsed) |>
    slice_max(.row, n = 1, with_ties = FALSE) |>
    ungroup() |>
    arrange(.row) |>
    select(-.row)
  counts[["drop_dup_snapshot"]] <- nrow(clean)
  log_msg(sprintf("drop duplicate (video_id, trending_date) snapshots: -%d rows", before - nrow(clean)))

  # ---- feature engineering ----------------------------------------------
  clean <- clean |>
    mutate(
      publish_hour      = as.integer(format(publish_time_parsed, "%H", tz = "UTC")),
      publish_dayofweek = as.integer(lubridate::wday(publish_time_parsed, week_start = 1) - 1L),
      publish_date      = as.Date(format(publish_time_parsed, "%Y-%m-%d", tz = "UTC")),
      days_to_trend     = as.integer(trending_date_parsed - publish_date),
      title_length      = nchar(title, type = "chars"),
      title_word_count  = str_count(title, "\\S+")
    )

  # tags is a '|'-separated list; '[none]' means no tags.
  tags_clean <- str_trim(clean$tags)
  tags_clean[is.na(tags_clean)] <- ""
  clean <- clean |>
    mutate(tag_count = if_else(tags_clean == "[none]" | tags_clean == "",
                               0L, str_count(tags_clean, fixed("|")) + 1L))

  cats <- jsonlite::fromJSON(file.path(DATA, "US_category_id.json"))
  id2name <- setNames(as.character(cats$items$snippet$title), as.character(cats$items$id))
  clean <- clean |> mutate(category = id2name[as.character(category_id)])

  clean <- clean |>
    mutate(
      log_views    = log1p(views),   log_likes    = log1p(likes),
      log_dislikes = log1p(dislikes), log_comments = log1p(comment_count),
      like_rate    = likes / views,
      comment_rate = comment_count / views,
      dislike_rate = dislikes / views
    )

  log_msg(sprintf("snapshot-level table after cleaning: %d rows", nrow(clean)))

  # ---- deduplicate to one row per video (final cumulative snapshot) ------
  videos <- clean |>
    arrange(video_id, trending_date_parsed) |>
    slice_tail(n = 1, by = video_id)
  counts[["video_level"]] <- nrow(videos)
  log_msg(sprintf("video-level table (last trending snapshot per video): %d videos", nrow(videos)))

  # classification target: top-quartile final views
  q75 <- quantile(videos$views, 0.75)
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
