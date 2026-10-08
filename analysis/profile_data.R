#!/usr/bin/env Rscript
# Profile the Kaggle YouTube Trending (US) dataset.
#
# Run:  Rscript analysis/profile_data.R
# All output goes to stdout so it can be captured into the report's data section.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(jsonlite)
  library(e1071)
})

script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) > 0) return(normalizePath(sub("^--file=", "", hit[[1]]), mustWork = FALSE))
  normalizePath(".", mustWork = FALSE)
}
ROOT <- dirname(dirname(script_path()))
DATA <- file.path(ROOT, "data")
CSV  <- file.path(DATA, "USvideos.csv")
CATS <- file.path(DATA, "US_category_id.json")

invisible(suppressWarnings(try(Sys.setlocale("LC_ALL", "C.UTF-8"), silent = TRUE)))

# Bias-corrected sample skewness (Fisher-Pearson g1); e1071 type 2.
skew <- function(x) e1071::skewness(x, na.rm = TRUE, type = 2)
kurt <- function(x) e1071::kurtosis(x, na.rm = TRUE, type = 2)

banner <- function(title) cat(sprintf("\n%s\n%s\n%s\n", strrep("=", 78), title, strrep("=", 78)))

col_types <- cols(
  video_id = col_character(), trending_date = col_character(), title = col_character(),
  channel_title = col_character(), category_id = col_integer(), publish_time = col_character(),
  tags = col_character(), views = col_double(), likes = col_double(), dislikes = col_double(),
  comment_count = col_double(), thumbnail_link = col_character(),
  comments_disabled = col_logical(), ratings_disabled = col_logical(),
  video_error_or_removed = col_logical(), description = col_character()
)

main <- function() {
  df <- read_csv(CSV, col_types = col_types, progress = FALSE)

  banner("1. DIMENSIONS & COLUMNS")
  cat(sprintf("shape (rows, cols): %d %d\n", nrow(df), ncol(df)))
  cat("columns:", paste(names(df), collapse = ", "), "\n")

  banner("2. DTYPES")
  print(vapply(df, function(x) class(x)[1], character(1)))

  banner("3. DATE RANGES (trending_date = YY.DD.MM)")
  td <- as.Date(df$trending_date, format = "%y.%d.%m")
  pt <- as.POSIXct(df$publish_time, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
  cat(sprintf("trending_date  min/max: %s %s | unparsed: %d\n",
              min(td, na.rm = TRUE), max(td, na.rm = TRUE), sum(is.na(td))))
  cat(sprintf("publish_time   min/max: %s %s | unparsed: %d\n",
              format(min(pt, na.rm = TRUE), tz = "UTC"),
              format(max(pt, na.rm = TRUE), tz = "UTC"), sum(is.na(pt))))
  cat(sprintf("distinct trending dates: %d\n", length(unique(td[!is.na(td)]))))
  cat(sprintf("all trending_date match ^\\d{2}\\.\\d{2}\\.\\d{2}$: %s\n",
              all(grepl("^\\d{2}\\.\\d{2}\\.\\d{2}$", df$trending_date))))

  banner("4. MISSING / SENTINELS")
  cat("NA per column:\n")
  print(colSums(is.na(df)))
  tags <- str_trim(df$tags)
  cat(sprintf("\ntags == '[none]': %d\n", sum(tags == "[none]", na.rm = TRUE)))
  cat(sprintf("tags == '[None]': %d\n", sum(tags == "[None]", na.rm = TRUE)))
  cat(sprintf("tags empty string: %d\n", sum(tags == "", na.rm = TRUE)))
  obj <- names(df)[vapply(df, function(x) is.character(x), logical(1))]
  empt <- vapply(obj, function(c) sum(str_trim(df[[c]]) == "", na.rm = TRUE), integer(1))
  cat("\nempty-string counts (object cols):\n")
  print(empt)

  banner("5. DUPLICATES & REPEATED SNAPSHOTS")
  cat(sprintf("fully duplicated rows: %d\n", sum(duplicated(df))))
  cat(sprintf("duplicated video_id : %d\n", sum(duplicated(df$video_id))))
  cat(sprintf("unique video_id     : %d\n", n_distinct(df$video_id)))
  vc <- df |> count(video_id, name = "n")
  cat(sprintf("max appearances of one video_id: %d\n", max(vc$n)))
  cat("\ndistribution of #appearances:\n")
  print(as.data.frame(table(vc$n), stringsAsFactors = FALSE))
  cat("\ntop 5 most-trending video_ids:\n")
  print(head(vc |> arrange(desc(n)), 5))
  dup_pairs <- sum(duplicated(df[c("video_id", "trending_date")]))
  cat(sprintf("\nduplicated (video_id, trending_date) pairs: %d\n", dup_pairs))

  banner("6. NUMERIC SUMMARY + SKEW")
  num <- c("views", "likes", "dislikes", "comment_count")
  for (v in num) {
    x <- df[[v]]
    cat(sprintf("%-14s mean=%.1f sd=%.1f min=%.0f q25=%.1f med=%.1f q75=%.1f q90=%.1f q99=%.1f max=%.0f\n",
                v, mean(x), sd(x), min(x), quantile(x, .25), median(x),
                quantile(x, .75), quantile(x, .90), quantile(x, .99), max(x)))
  }
  cat("\nskewness:\n"); print(vapply(df[num], skew, numeric(1)))
  cat("\nkurtosis:\n"); print(vapply(df[num], kurt, numeric(1)))

  banner("7. BOOLEAN FLAGS")
  for (c in c("comments_disabled", "ratings_disabled", "video_error_or_removed")) {
    cat(sprintf("\n%s:\n", c))
    print(table(df[[c]], useNA = "ifany"))
    print(round(100 * prop.table(table(df[[c]], useNA = "ifany")), 3))
  }

  banner("8. CATEGORY DISTRIBUTION (id -> name)")
  cats <- jsonlite::fromJSON(CATS)
  id2name <- setNames(as.character(cats$items$snippet$title), as.character(cats$items$id))
  cat("category_id value_counts:\n")
  print(table(df$category_id))
  cat(sprintf("\nnum distinct categories in data: %d\n", n_distinct(df$category_id)))
  cat("\ncategories appearing in data (name):\n")
  print(sort(table(id2name[as.character(df$category_id)]), decreasing = TRUE))

  banner("9. LOGICAL INCONSISTENCIES")
  cat(sprintf("views == 0            : %d\n", sum(df$views == 0)))
  cat(sprintf("likes == 0            : %d\n", sum(df$likes == 0)))
  cat(sprintf("comment_count == 0    : %d\n", sum(df$comment_count == 0)))
  cat(sprintf("likes > views         : %d\n", sum(df$likes > df$views)))
  cat(sprintf("dislikes > views      : %d\n", sum(df$dislikes > df$views)))
  cat(sprintf("comment_count > views : %d\n", sum(df$comment_count > df$views)))
  cat(sprintf("likes+dislikes > views: %d\n", sum((df$likes + df$dislikes) > df$views)))
  cat(sprintf("comments_disabled=True AND comment_count>0: %d\n",
              sum(df$comments_disabled & df$comment_count > 0, na.rm = TRUE)))

  banner("10. CHANNELS & ENGAGEMENT RATIOS")
  cat(sprintf("distinct channel_title: %d\n", n_distinct(df$channel_title)))
  cat("top 10 channels by #trending rows:\n")
  print(head(sort(table(df$channel_title), decreasing = TRUE), 10))
  v <- function(x) ifelse(df$views == 0, NA_real_, x / df$views)
  like_rate <- v(df$likes); comment_rate <- v(df$comment_count)
  cat(sprintf("\nengagement-ratio summary:\n"))
  for (nm in c("like_rate", "comment_rate")) {
    x <- if (nm == "like_rate") like_rate else comment_rate
    cat(sprintf("%-13s mean=%.5f sd=%.5f min=%.5f q25=%.5f med=%.5f q75=%.5f q90=%.5f max=%.5f\n",
                nm, mean(x, na.rm = TRUE), sd(x, na.rm = TRUE), min(x, na.rm = TRUE),
                quantile(x, .25, na.rm = TRUE), median(x, na.rm = TRUE),
                quantile(x, .75, na.rm = TRUE), quantile(x, .90, na.rm = TRUE),
                max(x, na.rm = TRUE)))
  }
  cat(sprintf("\nlike_rate > 1 (should be rare/impossible): %d\n", sum(like_rate > 1, na.rm = TRUE)))
  cat(sprintf("comment_rate > 1: %d\n", sum(comment_rate > 1, na.rm = TRUE)))

  banner("11. PER-VIDEO DEDUP PREVIEW (last snapshot per video)")
  last_idx <- ave(as.integer(td), df$video_id, FUN = function(z) z == max(z, na.rm = TRUE)) == 1
  dedup <- df[last_idx, ]
  cat(sprintf("rows after keeping last snapshot per video_id: %d\n", nrow(dedup)))
  cat(sprintf("unique videos: %d\n", n_distinct(dedup$video_id)))
  cat("views summary (dedup):\n")
  x <- dedup$views
  cat(sprintf("count=%.0f mean=%.1f sd=%.1f min=%.0f q25=%.1f med=%.1f q75=%.1f q90=%.1f q99=%.1f max=%.0f\n",
              length(x), mean(x), sd(x), min(x), quantile(x, .25), median(x),
              quantile(x, .75), quantile(x, .90), quantile(x, .99), max(x)))
}

main()
