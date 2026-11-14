# PPR2-only extensions to the shared PPR1 table; train-only model features below.
source("analysis/data_core.R")
prepare_data <- function() {
  baseline <- prepare_ppr1_data()
  d <- baseline$videos
  first <- tapply(as.numeric(baseline$snapshots$trending_date_parsed),
    baseline$snapshots$video_id, min)
  d$first_trend <- as.Date(unname(first[d$video_id]), origin = "1970-01-01")
  d$trend <- d$trending_date_parsed
  d$weekday <- d$publish_dayofweek
  d$hour_sin <- sin(2 * pi * d$publish_hour / 24)
  d$hour_cos <- cos(2 * pi * d$publish_hour / 24)
  d$channel_id <- match(d$channel_title, sort(unique(d$channel_title)))
  keep <- c("video_id", "channel_id", "category", "publish_date",
    "first_trend", "trend", "publish_hour", "weekday", "title_length",
    "title_word_count", "tag_count", "hour_sin", "hour_cos",
    "comments_disabled", "ratings_disabled", "views", "log_views",
    "like_rate", "comment_rate")
  d <- d[, keep]
  rownames(d) <- NULL
  stopifnot(!anyNA(d), !anyDuplicated(d$video_id))
  dir.create("analysis/output/ppr2", recursive = TRUE, showWarnings = FALSE)
  write.csv(d, "analysis/output/ppr2/videos.csv", row.names = FALSE)
  steps <- c("raw", "available", "exact_dedup", "video_day_dedup", "video_level")
  write.csv(data.frame(step = steps, rows = unname(baseline$counts)),
    "analysis/output/ppr2/cleaning.csv", row.names = FALSE)
  d
}
raw_features <- function(d, categories) {
  category <- ifelse(d$category %in% categories, d$category, "Other")
  z <- data.frame(category = factor(category, c(categories, "Other")),
    weekday = factor(d$weekday, 0:6), title_length = d$title_length,
    title_word_count = d$title_word_count, tag_count = d$tag_count,
    hour_sin = d$hour_sin, hour_cos = d$hour_cos,
    comments_disabled = as.integer(d$comments_disabled),
    ratings_disabled = as.integer(d$ratings_disabled))
  x <- model.matrix(~ ., z)[, -1, drop = FALSE]
  colnames(x) <- make.names(colnames(x), unique = TRUE)
  x
}
learn_features <- function(train) {
  freq <- sort(table(train$category), decreasing = TRUE)
  categories <- names(freq)[freq >= 20L]
  x <- raw_features(train, categories)
  spread <- apply(x, 2, sd)
  keep <- is.finite(spread) & spread > 1e-10
  list(categories = categories, columns = colnames(x)[keep],
       center = colMeans(x)[keep], scale = spread[keep])
}
features <- function(d, prep) {
  x <- raw_features(d, prep$categories)[, prep$columns, drop = FALSE]
  x <- sweep(sweep(x, 2, prep$center, "-"), 2, prep$scale, "/")
  stopifnot(all(is.finite(x)))
  x
}
make_folds <- function(groups, k, seed) {
  set.seed(seed)
  sizes <- table(groups)
  order_g <- order(-as.integer(sizes), runif(length(sizes)))
  load <- rep(0L, k)
  assignment <- setNames(integer(length(sizes)), names(sizes))
  for (g in names(sizes)[order_g]) {
    possible <- which(load == min(load))
    f <- possible[sample.int(length(possible), 1L)]
    assignment[g] <- f
    load[f] <- load[f] + sizes[g]
  }
  folds <- unname(assignment[as.character(groups)])
  stopifnot(all(vapply(split(folds, groups), function(x)
    length(unique(x)) == 1L, logical(1))))
  folds
}
