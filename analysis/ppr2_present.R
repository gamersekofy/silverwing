# Generate publication tables, linked numbers, and vector plots from saved OOF data.
source("analysis/ppr2_models.R")
OUT <- "analysis/output/ppr2"
FIG <- "report/figures/ppr2"
TAB <- "report/ppr2_tables"
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
dir.create(TAB, recursive = TRUE, showWarnings = FALSE)
get <- function(name) read.csv(file.path(OUT, name), stringsAsFactors = FALSE)
put <- function(x, name) write.csv(x, file.path(TAB, name), row.names = FALSE)
fmt <- function(x, digits = 3) formatC(x, digits = digits, format = "f")
models <- c("Mean", "OLS", "Ridge", "Tree", "Bagging")
reg <- get("regression_oof.csv"); cls <- get("classification_oof.csv")
metrics <- get("regression_metrics.csv")
fold_metrics <- get("regression_fold_metrics.csv")
main <- metrics[metrics$target == "log_views", ]
main <- main[match(models, main$model), ]
fold_sd <- sapply(models, function(m) sd(fold_metrics$RMSE[
  fold_metrics$target == "log_views" & fold_metrics$model == m]))
put(data.frame(Method = models, RMSE = fmt(main$RMSE), MAE = fmt(main$MAE),
  R2 = fmt(main$R2), Fold_SD = fmt(fold_sd)), "main.csv")
put(data.frame(Method = models, Raw_MAE = format(round(main$raw_MAE),
  big.mark = ",", trim = TRUE), Raw_RMSE = format(round(main$raw_RMSE),
  big.mark = ",", trim = TRUE)), "raw.csv")
cm <- get("classification_metrics.csv")
cf <- get("classification_fold_metrics.csv")
cm <- cm[match(c("Majority", "Logistic", "Tree", "Bagging"), cm$model), ]
auc <- sapply(cm$model, function(m) mean(cf$AUC[cf$model == m]))
auc_sd <- sapply(cm$model, function(m) sd(cf$AUC[cf$model == m]))
put(data.frame(Classifier = cm$model, Mean_AUC = fmt(auc), AP = fmt(cm$AP),
  Error = fmt(cm$Error), F1 = fmt(cm$F1), Recall = fmt(cm$Recall),
  Brier = fmt(cm$Brier)), "classification.csv")
put(data.frame(Classifier = cm$model, TN = cm$TN, FP = cm$FP,
  FN = cm$FN, TP = cm$TP), "confusion.csv")
rates <- metrics[metrics$target != "log_views", ]
rates <- rates[order(rates$target, match(rates$model, models)), ]
put(data.frame(Outcome = ifelse(rates$target == "like_rate", "Like rate",
  "Comment rate"), Method = rates$model, RMSE_pp = fmt(100 * rates$RMSE),
  MAE_pp = fmt(100 * rates$MAE), R2 = fmt(rates$R2)), "rates.csv")
ci <- get("cluster_inference.csv")
terms <- c("title_length", "title_word_count", "tag_count", "hour_sin",
           "hour_cos", "comments_disabled", "ratings_disabled")
labels <- c("Title characters (+1 SD)", "Title words (+1 SD)",
  "Tag count (+1 SD)", "Hour sine (+1 SD)", "Hour cosine (+1 SD)",
  "Comments disabled (0 to 1)", "Ratings disabled (0 to 1)")
ci <- ci[match(terms, ci$term), ]
put(data.frame(Feature = labels, Estimate = fmt(ci$estimate),
  CI95 = paste0("[", fmt(ci$lower), ", ", fmt(ci$upper), "]"),
  p = ifelse(ci$p_value < .001, "<0.001", fmt(ci$p_value))), "inference.csv")
temporal <- get("temporal_metrics.csv")
temporal <- temporal[match(models, temporal$model), ]
put(data.frame(Method = models, CV_RMSE = fmt(main$RMSE),
  Time_RMSE = fmt(temporal$RMSE), Time_MAE = fmt(temporal$MAE),
  Time_R2 = fmt(temporal$R2)), "temporal.csv")
parameters <- get("regression_parameters.csv")
cp <- get("classification_parameters.csv")
d <- get("videos.csv"); folds <- get("folds.csv")
ts <- get("temporal_split.csv")
mainp <- parameters[parameters$target == "log_views", ]
put(data.frame(Fold = mainp$fold, Lambda = mainp$lambda, Tree_cp = mainp$cp,
  Leaves = mainp$leaves, Class_cp = cp$cp, Class_leaves = cp$leaves),
  "parameters.csv")
best <- which.min(main$RMSE)
best_class <- which.max(auc)
stability <- get("bagging_regression_stability.csv")
stability_c <- get("bagging_classification_stability.csv")
time_train <- as.Date(d$trend) < as.Date("2018-05-01")
time_test <- as.Date(d$first_trend) >= as.Date("2018-05-01")
nums <- list(videos = nrow(d), channels = length(unique(d$channel_id)),
  ols_pct = fmt(100 * main$R2[main$model == "OLS"], 1),
  ridge_rmse = fmt(main$RMSE[main$model == "Ridge"]),
  tree_rmse = fmt(main$RMSE[main$model == "Tree"]),
  bag_rmse = fmt(main$RMSE[main$model == "Bagging"]),
  logistic_recall = fmt(100 * cm$Recall[cm$model == "Logistic"], 1),
  bag_recall = fmt(100 * cm$Recall[cm$model == "Bagging"], 1),
  like_r2 = fmt(rates$R2[rates$target == "like_rate" & rates$model == "OLS"]),
  comment_r2 = fmt(rates$R2[rates$target == "comment_rate" & rates$model == "OLS"]),
  tag_est = fmt(ci$estimate[ci$term == "tag_count"]),
  tag_low = fmt(ci$lower[ci$term == "tag_count"]),
  tag_high = fmt(ci$upper[ci$term == "tag_count"]),
  title_est = fmt(ci$estimate[ci$term == "title_length"]),
  title_low = fmt(ci$lower[ci$term == "title_length"]),
  title_high = fmt(ci$upper[ci$term == "title_length"]),
  best_model = main$model[best], best_rmse = fmt(main$RMSE[best]),
  best_mae = fmt(main$MAE[best]), best_r2 = fmt(main$R2[best]),
  improvement = fmt(100 * (1 - main$RMSE[best] / main$RMSE[1]), 1),
  baseline_rmse = fmt(main$RMSE[1]),
  best_class = cm$model[best_class], best_auc = fmt(auc[best_class]),
  auc_sd = fmt(auc_sd[best_class]),
  prevalence = fmt(100 * mean(cls$actual[cls$model == "Logistic"]), 1),
  fold_min = min(table(folds$outer_fold)), fold_max = max(table(folds$outer_fold)),
  lambda_min = min(mainp$lambda), lambda_max = max(mainp$lambda),
  leaves_min = min(mainp$leaves), leaves_max = max(mainp$leaves),
  cutoff_min = format(round(min(cp$cutoff_views)), big.mark = ",", trim = TRUE),
  cutoff_max = format(round(max(cp$cutoff_views)), big.mark = ",", trim = TRUE),
  temporal_train = ts$train, temporal_test = ts$test,
  temporal_excluded = ts$excluded_spanning,
  temporal_seen = ts$test_channels_seen,
  time_train_mean = fmt(mean(d$log_views[time_train])),
  time_test_mean = fmt(mean(d$log_views[time_test])),
  time_best_model = temporal$model[which.min(temporal$RMSE)],
  time_best_rmse = fmt(min(temporal$RMSE)),
  bag_100_rmse = fmt(sqrt(mean((stability$actual - stability$first100)^2))),
  bag_200_rmse = fmt(sqrt(mean((stability$actual - stability$all200)^2))),
  bag_change = fmt(sqrt(mean((stability$all200 - stability$first100)^2))),
  bag_class_change = fmt(sqrt(mean((stability_c$all200 -
    stability_c$first100)^2))),
  logistic_warnings = sum(!is.na(cp$logistic_warnings) &
    nzchar(cp$logistic_warnings)),
  title_sd = fmt(sd(d$title_length), 1), tag_sd = fmt(sd(d$tag_count), 1))
lines <- vapply(names(nums), function(key)
  paste0("  ", key, ": ", encodeString(as.character(nums[[key]]), quote = '"'), ","),
  character(1))
writeLines(c("#let results = (", lines, ")"), "report/ppr2_numbers.typ")
open_plot <- function(name, width = 7.2, height = 4.2) {
  svg(file.path(FIG, paste0(name, ".svg")), width, height, pointsize = 11)
  par(mar = c(4.1, 4.2, 2.2, .8), las = 1, family = "sans",
      mgp = c(2.2, .7, 0))
}
colors <- c("#777777", "#28668c", "#a55b1b", "#537f37", "#865a98")
open_plot("performance", height = 3.6)
par(mfrow = c(1, 2), mar = c(3.8, 4.8, 2.1, .7))
for (metric in c("RMSE", "MAE")) {
  z <- fold_metrics[fold_metrics$target == "log_views", ]
  plot(range(c(z[[metric]], main[[metric]])), c(.5, 5.5), type = "n",
    yaxt = "n", xlab = paste(metric, "on log(1 + views)"), ylab = "",
    main = paste("Log-view", metric))
  axis(2, at = 5:1, labels = models, tick = FALSE)
  abline(h = 1:5, col = "#eeeeee")
  for (i in 1:5) {
    values <- z[[metric]][z$model == models[i]]
    points(values, rep(6 - i, length(values)), col = "#aaaaaa", pch = 1)
    points(main[[metric]][i], 6 - i, col = colors[i], pch = 18, cex = 1.5)
  }
}
dev.off()
open_plot("predictions", height = 5.4)
par(mfrow = c(2, 2), mar = c(3.8, 3.8, 2.1, .5), cex = .88,
    mgp = c(2.2, .7, 0))
for (m in models[-1]) {
  z <- reg[reg$target == "log_views" & reg$model == m, ]
  limits <- range(z$actual, z$prediction)
  plot(z$actual, z$prediction, pch = 16, cex = .3,
    col = adjustcolor("#28668c", .12), xlim = limits, ylim = limits,
    xlab = "Observed log views", ylab = "OOF prediction", main = m)
  abline(0, 1, lty = 2, col = "#333333")
}
dev.off()
open_plot("classification", height = 3.8)
par(mfrow = c(1, 2), mar = c(3.8, 4.1, 2, .7))
plot(0:1, 0:1, type = "n", xlab = "False-positive rate",
     ylab = "True-positive rate", main = "Cross-fitted ROC curves")
abline(0, 1, col = "#999999", lty = 2)
for (i in 2:4) {
  z <- cls[cls$model == cm$model[i], ]; curve <- roc_points(z$actual, z$probability)
  lines(curve$fpr, curve$tpr, col = colors[i], lwd = 2)
}
legend("bottomright", cm$model[2:4], col = colors[2:4], lty = 1, bty = "n", cex = .85)
plot(0:1, 0:1, type = "n", xlab = "Recall", ylab = "Precision",
     main = "Precision-recall curves")
abline(h = mean(z$actual), col = "#999999", lty = 2)
for (i in 2:4) {
  z <- cls[cls$model == cm$model[i], ]; curve <- roc_points(z$actual, z$probability)
  lines(curve$tpr, curve$precision, col = colors[i], lwd = 1.5, type = "S")
}
dev.off()
open_plot("inference", height = 4.2)
par(mar = c(4, 12, 1.5, 1))
plot(range(ci$lower, ci$upper), c(.5, 7.5), type = "n", yaxt = "n",
     xlab = "Adjusted OLS coefficient (log-view units)", ylab = "")
axis(2, at = 7:1, labels = labels, tick = FALSE, cex.axis = .85)
abline(v = 0, lty = 2, col = "#777777")
segments(ci$lower, 7:1, ci$upper, 7:1, col = "#28668c", lwd = 2)
points(ci$estimate, 7:1, pch = 16, col = "#28668c")
dev.off()
open_plot("diagnostics", height = 3.6)
par(mfrow = c(1, 2), mar = c(3.8, 4.2, 2.2, .7))
z <- reg[reg$target == "log_views" & reg$model == main$model[best], ]
e <- z$actual - z$prediction
plot(z$prediction, e, pch = 16, cex = .3, col = adjustcolor("#28668c", .12),
  xlab = "OOF prediction", ylab = "Observed minus predicted", main = main$model[best])
abline(h = 0, lty = 2)
qqnorm(e, pch = 16, cex = .35, col = "#28668c", main = "OOF residual normal Q-Q")
qqline(e, col = "#a55b1b", lwd = 2)
dev.off()
cat("Generated linked tables, numbers, and five vector figures.\n")
