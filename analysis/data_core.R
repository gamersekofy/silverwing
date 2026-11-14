# Shared PPR1 data preparation, used by EDA and PPR2 (base R only).
# Cleaning order, UTC conventions and last-snapshot outcomes are unchanged.
read_category_lookup <- function(path) {
  s <- paste(readLines(path, warn = FALSE), collapse = " ")
  grab <- function(pattern) regmatches(s, gregexpr(pattern, s, perl = TRUE))[[1]]
  ids <- grab('"id"\\s*:\\s*"[0-9]+"')
  titles <- grab('"title"\\s*:\\s*"[^"\\r\\n]*"')
  ids <- sub('.*"([0-9]+)"$', "\\1", ids)
  titles <- sub('^"title"\\s*:\\s*"(.*)"$', "\\1", titles, perl = TRUE)
  stopifnot(length(ids) == length(titles), !anyDuplicated(ids))
  setNames(titles, ids)
}
read_trending_raw <- function(data_dir = "data") {
  types <- c(rep("character", 4), "integer", rep("character", 2),
             rep("numeric", 4), "character", rep("logical", 3), "character")
  d <- read.csv(file.path(data_dir, "USvideos.csv"), colClasses = types,
    stringsAsFactors = FALSE, na.strings = c("", "NA"), comment.char = "",
    fileEncoding = "UTF-8")
  stopifnot(nrow(d) == 40949L, ncol(d) == 16L)
  d
}
count_title_words <- function(titles) {
  vapply(gregexpr("(*UCP)\\S+", titles, perl = TRUE),
    function(hit) as.integer(sum(hit > 0L)), integer(1))
}
prepare_ppr1_data <- function(data_dir = "data") {
  raw <- read_trending_raw(data_dir)
  raw$trending_date_parsed <- as.Date(raw$trending_date, "%y.%d.%m")
  raw$publish_time_parsed <- as.POSIXct(raw$publish_time,
    "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
  stopifnot(!anyNA(raw$trending_date_parsed), !anyNA(raw$publish_time_parsed))
  d <- raw[!raw$video_error_or_removed, ]
  counts <- c(raw = nrow(raw), drop_error_or_removed = nrow(d))
  d <- d[!duplicated(d), ]
  counts <- c(counts, drop_full_dup = nrow(d))
  d <- d[!duplicated(d[c("video_id", "trending_date_parsed")], fromLast = TRUE), ]
  counts <- c(counts, drop_dup_snapshot = nrow(d))
  time <- d$publish_time_parsed
  d$publish_hour <- as.integer(format(time, "%H", tz = "UTC"))
  d$publish_dayofweek <- (as.integer(format(time, "%w", tz = "UTC")) + 6L) %% 7L
  d$publish_date <- as.Date(format(time, "%Y-%m-%d", tz = "UTC"))
  d$days_to_trend <- as.integer(d$trending_date_parsed - d$publish_date)
  d$title_length <- nchar(d$title, type = "chars")
  # Unicode whitespace matches stringr's PPR1 word/trim conventions.
  d$title_word_count <- count_title_words(d$title)
  tags <- trimws(d$tags, whitespace = "[\\h\\v]")
  absent <- is.na(tags) | tags %in% c("", "[none]")
  tags[absent] <- ""
  d$tag_count <- ifelse(absent, 0L,
    nchar(tags) - nchar(gsub("|", "", tags, fixed = TRUE)) + 1L)
  cats <- read_category_lookup(file.path(data_dir, "US_category_id.json"))
  d$category <- unname(cats[as.character(d$category_id)])
  d$log_views <- log1p(d$views)
  d$log_likes <- log1p(d$likes)
  d$log_dislikes <- log1p(d$dislikes)
  d$log_comments <- log1p(d$comment_count)
  d$like_rate <- d$likes / d$views
  d$comment_rate <- d$comment_count / d$views
  d$dislike_rate <- d$dislikes / d$views
  ordered <- d[order(d$video_id, d$trending_date_parsed), ]
  videos <- ordered[!duplicated(ordered$video_id, fromLast = TRUE), ]
  counts <- c(counts, video_level = nrow(videos))
  rownames(videos) <- NULL
  stopifnot(identical(unname(counts), c(40949L, 40926L, 40878L, 40876L, 6348L)),
    !anyDuplicated(videos$video_id), !anyNA(videos$category), all(videos$views > 0))
  list(raw = raw, snapshots = d, videos = videos, counts = counts)
}
