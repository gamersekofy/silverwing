#!/usr/bin/env Rscript
# Print the compact set of numbers cited in Progress Report 1.
#
# Run:  Rscript analysis/report_numbers.R   (after analysis/clean_eda.R)

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) > 0) return(normalizePath(sub("^--file=", "", hit[[1]]), mustWork = FALSE))
  normalizePath(".", mustWork = FALSE)
}
ROOT <- dirname(dirname(script_path()))
videos <- read_csv(file.path(ROOT, "analysis", "output", "videos.csv"),
                   col_types = cols(.default = col_guess()), progress = FALSE)
raw <- read_csv(file.path(ROOT, "data", "USvideos.csv"), progress = FALSE, show_col_types = FALSE)

describe <- function(x, label, p = c(.25, .5, .75)) {
  qs <- quantile(x, p, na.rm = TRUE)
  parts <- paste(sprintf("%s=%.5f", c("q25", "q50", "q75"), qs), collapse = " ")
  cat(sprintf("%-13s count=%d mean=%.5f sd=%.5f min=%.5f %s max=%.5f\n",
              label, sum(!is.na(x)), mean(x, na.rm = TRUE), sd(x, na.rm = TRUE),
              min(x, na.rm = TRUE), parts, max(x, na.rm = TRUE)))
}

cat(sprintf("### video level: n = %d\n", nrow(videos)))

cat("\n-- engagement ratios --\n")
for (c in c("like_rate", "comment_rate", "dislike_rate")) describe(videos[[c]], c)

cat("\n-- correlations with log_views (video level) --\n")
cols <- c("title_length", "title_word_count", "tag_count", "publish_hour",
          "days_to_trend", "log_likes", "log_dislikes", "log_comments")
cors <- vapply(cols, function(c) round(cor(videos[[c]], videos$log_views, use = "complete.obs"), 3), numeric(1))
print(cors)

cat("\n-- title / tag features --\n")
for (c in c("title_length", "title_word_count", "tag_count")) describe(videos[[c]], c)
cat(sprintf("tag_count == 0: %d\n", sum(videos$tag_count == 0)))
cat(sprintf("title_length == 0: %d\n", sum(videos$title_length == 0)))

cat("\n-- days_to_trend --\n")
x <- videos$days_to_trend
cat(sprintf("count=%d mean=%.4f sd=%.4f min=%.0f q25=%.1f med=%.1f q75=%.1f max=%.0f\n",
            sum(!is.na(x)), mean(x, na.rm = TRUE), sd(x, na.rm = TRUE), min(x, na.rm = TRUE),
            quantile(x, .25, na.rm = TRUE), median(x, na.rm = TRUE),
            quantile(x, .75, na.rm = TRUE), max(x, na.rm = TRUE)))
cat(sprintf("negative days_to_trend: %d\n", sum(x < 0, na.rm = TRUE)))
cat(sprintf("days_to_trend > 365: %d\n", sum(x > 365, na.rm = TRUE)))

cat("\n-- flags at video level --\n")
for (c in c("comments_disabled", "ratings_disabled"))
  cat(sprintf("%s n_true = %d\n", c, sum(videos[[c]], na.rm = TRUE)))

cat("\n-- zeros at video level --\n")
for (c in c("likes", "dislikes", "comment_count"))
  cat(sprintf("%s == 0: %d\n", c, sum(videos[[c]] == 0)))

cat("\n-- top categories (video level) --\n")
print(head(sort(table(videos$category), decreasing = TRUE), 8))

cat("\n-- raw snapshots --\n")
cat(sprintf("unique videos in raw: %d\n", n_distinct(raw$video_id)))
vc <- raw |> count(video_id, name = "n")
cat(sprintf("mean snapshots/video: %.2f | max: %d\n", mean(vc$n), max(vc$n)))
cat(sprintf("videos trending >= 2 days: %d (%.1f%%)\n", sum(vc$n >= 2), 100 * mean(vc$n >= 2)))

cat("\n-- raw views percentiles (snapshot) --\n")
cat(sprintf("count=%d mean=%.1f sd=%.1f min=%.0f q25=%.1f med=%.1f q75=%.1f q99=%.1f max=%.0f\n",
            nrow(raw), mean(raw$views), sd(raw$views), min(raw$views),
            quantile(raw$views, .25), median(raw$views),
            quantile(raw$views, .75), quantile(raw$views, .99), max(raw$views)))
