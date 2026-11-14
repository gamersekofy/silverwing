# Recompute reported metrics and split rules from saved predictions.
# Independent checks use residual moments and ROC trapezoid integration.
source("analysis/ppr2_models.R")
OUT <- "analysis/output/ppr2"
read <- function(name) read.csv(file.path(OUT, name), stringsAsFactors = FALSE)
d <- read("videos.csv"); folds <- read("folds.csv")
r <- read("regression_oof.csv"); c <- read("classification_oof.csv")
m <- read("regression_metrics.csv"); cm <- read("classification_metrics.csv")
stopifnot(nrow(d) == 6348L, !anyDuplicated(d$video_id),
  all(vapply(split(folds$outer_fold, folds$channel_id),
    function(f) length(unique(f)) == 1L, logical(1))))
for (i in seq_len(nrow(m))) {
  z <- r[r$target == m$target[i] & r$model == m$model[i], ]
  stopifnot(nrow(z) == nrow(d), !anyDuplicated(z$video_id))
  idx <- match(z$video_id, d$video_id)
  stopifnot(max(abs(z$actual - d[[m$target[i]]][idx])) < 1e-10,
    identical(z$fold, folds$outer_fold[match(z$video_id, folds$video_id)]))
  error <- z$prediction - z$actual
  stopifnot(abs(sqrt(crossprod(error) / length(error)) - m$RMSE[i]) < 1e-10,
    abs(sum(abs(error)) / length(error) - m$MAE[i]) < 1e-10)
  r2 <- 1 - crossprod(error) / crossprod(z$actual - mean(z$actual))
  stopifnot(abs(r2 - m$R2[i]) < 1e-10)
  if (m$target[i] == "log_views") {
    error_raw <- pmax(0, expm1(z$prediction)) - z$views
    stopifnot(abs(sqrt(mean(error_raw^2)) - m$raw_RMSE[i]) < 1e-6,
              abs(mean(abs(error_raw)) - m$raw_MAE[i]) < 1e-6)
  }
}
cp <- read("classification_parameters.csv")
for (f in 1:10) {
  train_ids <- folds$video_id[folds$outer_fold != f]
  threshold <- quantile(d$views[d$video_id %in% train_ids], .75)
  stopifnot(abs(threshold - cp$cutoff_views[cp$fold == f]) < 1e-6)
}
for (i in seq_len(nrow(cm))) {
  z <- c[c$model == cm$model[i], ]
  idx <- match(z$video_id, d$video_id)
  stopifnot(nrow(z) == nrow(d), !anyDuplicated(z$video_id),
    all(z$actual == as.integer(d$views[idx] >= z$cutoff_views)))
  curve <- roc_points(z$actual, z$probability)
  area <- sum(diff(curve$fpr) *
    (head(curve$tpr, -1) + tail(curve$tpr, -1)) / 2)
  stopifnot(abs(area - cm$AUC[i]) < 1e-10,
    abs(mean((z$probability - z$actual)^2) - cm$Brier[i]) < 1e-10,
    cm$TP[i] + cm$TN[i] + cm$FP[i] + cm$FN[i] == nrow(d))
}
t <- read("temporal_predictions.csv")
train <- as.Date(d$trend) < as.Date("2018-05-01")
test <- as.Date(d$first_trend) >= as.Date("2018-05-01")
stopifnot(!any(train & test),
  setequal(unique(t$video_id), d$video_id[test]))
ci <- read("cluster_inference.csv")
stopifnot(all(ci$lower <= ci$estimate), all(ci$upper >= ci$estimate))
stability <- read("bagging_regression_stability.csv")
stability_c <- read("bagging_classification_stability.csv")
writeLines(c("PASS: saved grouped folds, unique OOF coverage, and response identities.",
  "PASS: independent residual-moment regression metrics and ROC area.",
  "PASS: training-only class cutoffs, confusion totals, and temporal membership.",
  sprintf("Bagging log prediction RMS change (100 -> 200): %.6f",
    sqrt(mean((stability$all200 - stability$first100)^2))),
  sprintf("Bagging probability RMS change (100 -> 200): %.6f",
    sqrt(mean((stability_c$all200 - stability_c$first100)^2)))),
  file.path(OUT, "output_audit.txt"))
cat(readLines(file.path(OUT, "output_audit.txt")), sep = "\n")
