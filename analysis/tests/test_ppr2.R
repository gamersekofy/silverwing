# Deterministic unit/data tests; run from the project root.
source("analysis/ppr2_data.R")
source("analysis/ppr2_models.R")
d <- prepare_data()
baseline <- prepare_ppr1_data()
idx <- match(d$video_id, baseline$videos$video_id)
shared <- c("views", "log_views", "like_rate", "comment_rate", "title_length",
  "title_word_count", "tag_count", "publish_hour", "category",
  "comments_disabled", "ratings_disabled", "publish_date")
for (name in shared) stopifnot(identical(d[[name]], baseline$videos[[name]][idx]))
stopifnot(identical(d$weekday, baseline$videos$publish_dayofweek[idx]),
  identical(d$trend, baseline$videos$trending_date_parsed[idx]),
  !any(c("high_views", "days_to_trend", "channel_title") %in% names(d)),
  identical(unname(count_title_words(c("", "a b", "a\u00a0b", "a\u2003b"))),
    c(0L, 2L, 2L, 2L)))
stopifnot(nrow(d) == 6348L, length(unique(d$channel_id)) == 2198L,
  abs(mean(d$views) - 1962281.5) < .1, sum(d$tag_count == 0) == 256L,
  abs(quantile(d$views, .75) - 1473578.25) < 1,
  sum(d$comments_disabled) == 105L, sum(d$ratings_disabled) == 30L)
f <- make_folds(d$channel_id, 10L, 20261111L)
stopifnot(identical(f, make_folds(d$channel_id, 10L, 20261111L)))
stopifnot(diff(range(table(f))) <= 2L)
for (k in 1:10) stopifnot(!length(intersect(
  d$channel_id[f == k], d$channel_id[f != k])))
train <- d[f != 1, ]; valid <- d[f == 1, ]
p <- learn_features(train)
x <- features(train, p)
stopifnot(max(abs(colMeans(x))) < 1e-12,
          max(abs(apply(x, 2, sd) - 1)) < 1e-12)
changed <- valid
changed$views <- 1e12
changed$log_views <- -100
changed$like_rate <- 999
stopifnot(identical(features(valid, p), features(changed, p)))
changed$category[1] <- "not_in_training"
stopifnot(all(is.finite(features(changed, p))))
set.seed(7)
x <- scale(matrix(rnorm(400), 100, 4))
y <- 2 + x[, 1] - 2 * x[, 2] + rnorm(100)
b <- fit_ridge(x, y, .2)
stopifnot(max(abs(crossprod(x, linear_predict(b, x) - y) +
  nrow(x) * .2 * b[-1])) < 1e-8)
stopifnot(max(abs(fit_ridge(x, y, 0) - fit_ols(x, y))) < 1e-8)
stopifnot(max(abs(fit_ridge(x, y, 1e8)[-1])) < 1e-6)
stopifnot(abs(classification_metrics(c(0, 0, 1, 1),
  c(.1, .4, .35, .8))["AUC"] - .75) < 1e-12)
stopifnot(classification_metrics(c(0, 1), c(.5, .5))["AUC"] == .5)
stopifnot(classification_metrics(c(0, 1), c(.5, .5))["AP"] == .5)
colnames(x) <- paste0("x", 1:4)
tree <- fit_tree(x, y)
stopifnot(tree$control$xval == 0)
a <- bag_predict(x, y, x[1:8, ], 19L, trees = 6L)
b <- bag_predict(x, y, x[1:8, ], 19L, trees = 6L)
stopifnot(identical(a, b), length(a$prediction) == 8L)
loss <- matrix(c(1, 1, 1, 1, 1, 1, 1, 1, 1, 1), nrow = 5)
stopifnot(one_se(loss, c(.01, 1)) == 2L)
ci <- cluster_inference(d)
stopifnot(all(is.finite(ci$se)), all(ci$se > 0),
          all(ci$lower <= ci$estimate & ci$upper >= ci$estimate))
cat("PASS: data parity, grouped folds, train-only features, ridge equations,\n")
cat("      tied ROC/AP, deterministic bagging, one-SE, and cluster covariance.\n")
