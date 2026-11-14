# Run from the repository root: Rscript --vanilla analysis/ppr2_run.R
source("analysis/ppr2_data.R")
source("analysis/ppr2_models.R")
OUT <- "analysis/output/ppr2"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
SEED <- 20261111L
sources <- c("analysis/data_core.R", "analysis/ppr2_data.R", "analysis/ppr2_models.R",
             "analysis/ppr2_run.R", "data/USvideos.csv",
             "data/US_category_id.json")
signature <- tools::md5sum(sources)
regression_block <- function(train, test, fold, inner,
                             targets = c("log_views", "like_rate", "comment_rate")) {
  prep <- learn_features(train)
  x <- features(train, prep); z <- features(test, prep)
  predictions <- parameters <- list()
  stability <- NULL
  for (target in targets) {
    tuned <- tune_regression(train, target, inner)
    y <- train[[target]]
    tree <- rpart::prune(fit_tree(x, y), cp = tuned$cp)
    p <- list(Mean = rep(mean(y), nrow(test)),
      OLS = linear_predict(fit_ols(x, y), z),
      Ridge = linear_predict(fit_ridge(x, y, tuned$lambda), z),
      Tree = tree_predict(tree, z))
    if (target == "log_views") {
      bag <- bag_predict(x, y, z, SEED + 1000L * fold + 1L)
      p$Bagging <- bag$prediction
      stability <- data.frame(fold = fold, row = seq_len(nrow(test)),
        actual = test$log_views, first100 = bag$half, all200 = bag$prediction)
    }
    predictions[[target]] <- do.call(rbind, lapply(names(p), function(m)
      data.frame(video_id = test$video_id, channel_id = test$channel_id,
        fold = fold, target = target, model = m, actual = test[[target]],
        prediction = p[[m]], views = test$views)))
    parameters[[target]] <- data.frame(fold = fold, target = target,
      lambda = tuned$lambda, cp = tuned$cp,
      leaves = sum(tree$frame$var == "<leaf>"), features = ncol(x))
  }
  list(predictions = do.call(rbind, predictions),
       parameters = do.call(rbind, parameters), stability = stability)
}
classification_block <- function(train, test, fold, inner) {
  prep <- learn_features(train)
  x <- features(train, prep); z <- features(test, prep)
  cutoff <- unname(quantile(train$views, .75))
  y <- as.integer(train$views >= cutoff)
  truth <- as.integer(test$views >= cutoff)
  tuned <- tune_classification(train, inner)
  tree <- rpart::prune(fit_tree(x, y, TRUE), cp = tuned$cp)
  logistic <- fit_logistic(x, y)
  bag <- bag_predict(x, y, z, SEED + 1000L * fold + 2L, TRUE)
  p <- list(Majority = rep(mean(y), nrow(test)),
    Logistic = plogis(linear_predict(logistic$beta, z)),
    Tree = tree_predict(tree, z, TRUE), Bagging = bag$prediction)
  predictions <- do.call(rbind, lapply(names(p), function(m)
    data.frame(video_id = test$video_id, fold = fold, model = m,
      actual = truth, probability = p[[m]], cutoff_views = cutoff)))
  stopifnot(all(is.finite(predictions$probability)),
    all(predictions$probability >= 0 & predictions$probability <= 1))
  list(predictions = predictions,
    parameters = data.frame(fold = fold, cutoff_views = cutoff,
      positive_test = sum(truth), cp = tuned$cp,
      leaves = sum(tree$frame$var == "<leaf>"),
      logistic_iterations = logistic$iterations,
      logistic_warnings = paste(logistic$warnings, collapse = "; ")),
    stability = data.frame(fold = fold, actual = truth,
      first100 = bag$half, all200 = bag$prediction))
}
summarise_regression <- function(predictions, by_fold = FALSE) {
  keys <- c("target", "model", if (by_fold) "fold")
  groups <- split(seq_len(nrow(predictions)),
                  interaction(predictions[, keys], drop = TRUE))
  do.call(rbind, lapply(groups, function(rows) {
    z <- predictions[rows, ]
    metrics <- regression_metrics(z$actual, z$prediction)
    raw <- c(raw_RMSE = NA_real_, raw_MAE = NA_real_)
    if (z$target[1] == "log_views") {
      back <- pmax(0, expm1(z$prediction))
      raw <- c(raw_RMSE = sqrt(mean((z$views - back)^2)),
               raw_MAE = mean(abs(z$views - back)))
    }
    cbind(z[1, keys, drop = FALSE], as.data.frame(as.list(c(metrics, raw))))
  }))
}
summarise_classification <- function(predictions, by_fold = FALSE) {
  keys <- c("model", if (by_fold) "fold")
  groups <- split(seq_len(nrow(predictions)),
                  interaction(predictions[, keys], drop = TRUE))
  do.call(rbind, lapply(groups, function(rows) {
    z <- predictions[rows, ]
    cbind(z[1, keys, drop = FALSE], as.data.frame(as.list(
      classification_metrics(z$actual, z$probability))))
  }))
}
write_table <- function(x, name) write.csv(x, file.path(OUT, name),
                                         row.names = FALSE)
d <- prepare_data()
folds <- make_folds(d$channel_id, 10L, SEED)
write_table(data.frame(video_id = d$video_id, channel_id = d$channel_id,
                      outer_fold = folds), "folds.csv")
results <- vector("list", 10L)
for (f in 1:10) {
  checkpoint <- file.path(OUT, sprintf("fold%02d.rds", f))
  if (file.exists(checkpoint)) {
    saved <- readRDS(checkpoint)
    stopifnot(identical(saved$signature, signature))
    results[[f]] <- saved$result
    cat(sprintf("Fold %02d/10: verified checkpoint\n", f))
    next
  }
  train <- d[folds != f, ]; test <- d[folds == f, ]
  stopifnot(!length(intersect(train$channel_id, test$channel_id)))
  cat(sprintf("Fold %02d/10: %d train / %d test; fitting...\n",
              f, nrow(train), nrow(test)))
  started <- proc.time()[3]
  inner <- inner_splits(train, SEED + f)
  results[[f]] <- list(
    regression = regression_block(train, test, f, inner),
    classification = classification_block(train, test, f, inner))
  saveRDS(list(signature = signature, result = results[[f]]), checkpoint)
  cat(sprintf("Fold %02d/10 complete in %.1f seconds\n",
              f, proc.time()[3] - started))
}
reg <- do.call(rbind, lapply(results, function(x) x$regression$predictions))
cls <- do.call(rbind, lapply(results, function(x) x$classification$predictions))
stopifnot(!anyNA(reg), all(is.finite(reg$prediction)), !anyNA(cls))
write_table(reg, "regression_oof.csv")
write_table(cls, "classification_oof.csv")
write_table(summarise_regression(reg), "regression_metrics.csv")
write_table(summarise_regression(reg, TRUE), "regression_fold_metrics.csv")
write_table(summarise_classification(cls), "classification_metrics.csv")
write_table(summarise_classification(cls, TRUE), "classification_fold_metrics.csv")
write_table(do.call(rbind, lapply(results, function(x)
  x$regression$parameters)), "regression_parameters.csv")
write_table(do.call(rbind, lapply(results, function(x)
  x$classification$parameters)), "classification_parameters.csv")
write_table(do.call(rbind, lapply(results, function(x)
  x$regression$stability)), "bagging_regression_stability.csv")
write_table(do.call(rbind, lapply(results, function(x)
  x$classification$stability)), "bagging_classification_stability.csv")
write_table(cluster_inference(d), "cluster_inference.csv")
# Time stress test: outcomes fully observed before May 1 vs videos first
# observed trending on/after May 1. Spanning videos are excluded.
cutoff <- as.Date("2018-05-01")
train <- d[d$trend < cutoff, ]
test <- d[d$first_trend >= cutoff, ]
stopifnot(!length(intersect(train$video_id, test$video_id)))
cat(sprintf("Temporal stress test: %d train / %d test\n", nrow(train), nrow(test)))
inner <- inner_splits(train, SEED + 100L)
temporal <- regression_block(train, test, 11L, inner, "log_views")
write_table(temporal$predictions, "temporal_predictions.csv")
write_table(summarise_regression(temporal$predictions), "temporal_metrics.csv")
write_table(temporal$parameters, "temporal_parameters.csv")
write_table(data.frame(train = nrow(train), test = nrow(test),
  excluded_spanning = nrow(d) - nrow(train) - nrow(test),
  test_channels_seen = sum(test$channel_id %in% train$channel_id)),
  "temporal_split.csv")
writeLines(c(capture.output(sessionInfo()),
  paste("rpart", as.character(packageVersion("rpart"))),
  paste("seed", SEED), paste(names(signature), signature)),
  file.path(OUT, "run_manifest.txt"))
cat("Completed all comparisons.\n")
summary <- summarise_regression(reg)
print(summary[summary$target == "log_views", ])
print(summarise_classification(cls))
