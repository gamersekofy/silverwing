# Model kernels and grouped inner-CV selection; base R + rpart only.
LAMBDAS <- 10^seq(-4, 2, length.out = 13)
CPS <- c(0, .001, .003, .01, .03, .1)
BAG_TREES <- 200L
fit_ols <- function(x, y) {
  fit <- lm.fit(cbind(Intercept = 1, x), y)
  b <- fit$coefficients
  b[is.na(b)] <- 0
  b
}
linear_predict <- function(b, x) drop(cbind(Intercept = 1, x) %*% b)
fit_ridge <- function(x, y, lambda) {
  s <- svd(x)
  n <- nrow(x)
  centered <- y - mean(y)
  b <- s$v %*% ((s$d / (s$d^2 + n * lambda)) * crossprod(s$u, centered))
  c(Intercept = mean(y), drop(b))
}
# Objective: mean squared error + lambda * sum(slope^2).
# x has training-only zero means/unit sample SD; intercept is not penalized.
fit_tree <- function(x, y, classification = FALSE, bag = FALSE) {
  if (classification) y <- factor(y, levels = 0:1)
  frame <- data.frame(.y = y, x, check.names = FALSE)
  control <- rpart::rpart.control(cp = 0, xval = 0,
    minbucket = if (bag) 5L else 20L,
    minsplit = if (bag) 10L else 40L,
    maxdepth = if (bag) 20L else 12L)
  rpart::rpart(.y ~ ., data = frame, control = control,
    method = if (classification) "class" else "anova")
}
tree_predict <- function(tree, x, classification = FALSE) {
  new <- data.frame(x, check.names = FALSE)
  if (classification) return(predict(tree, new, type = "prob")[, "1"])
  as.numeric(predict(tree, new))
}
bag_predict <- function(x, y, new, seed, classification = FALSE,
                        trees = BAG_TREES) {
  set.seed(seed)
  total <- half <- rep(0, nrow(new))
  for (b in seq_len(trees)) {
    rows <- sample.int(nrow(x), nrow(x), replace = TRUE)
    tree <- fit_tree(x[rows, , drop = FALSE], y[rows], classification, TRUE)
    total <- total + tree_predict(tree, new, classification)
    if (b == floor(trees / 2)) half <- total / b
  }
  list(prediction = total / trees, half = half)
}
inner_splits <- function(d, seed) {
  fold <- make_folds(d$channel_id, 5L, seed)
  lapply(1:5, function(k) {
    train <- which(fold != k)
    valid <- which(fold == k)
    stopifnot(!length(intersect(d$channel_id[train], d$channel_id[valid])))
    prep <- learn_features(d[train, ])
    list(train = train, valid = valid,
         x = features(d[train, ], prep), z = features(d[valid, ], prep))
  })
}
one_se <- function(loss, complexity) {
  avg <- colMeans(loss)
  best <- which.min(avg)
  tolerance <- sd(loss[, best]) / sqrt(nrow(loss))
  eligible <- which(avg <= avg[best] + tolerance)
  eligible[which.max(complexity[eligible])]
}
tune_regression <- function(d, target, inner) {
  ridge_loss <- matrix(NA_real_, 5, length(LAMBDAS))
  tree_loss <- matrix(NA_real_, 5, length(CPS))
  for (k in seq_along(inner)) {
    s <- inner[[k]]
    y <- d[[target]][s$train]
    truth <- d[[target]][s$valid]
    for (j in seq_along(LAMBDAS)) {
      p <- linear_predict(fit_ridge(s$x, y, LAMBDAS[j]), s$z)
      ridge_loss[k, j] <- mean((truth - p)^2)
    }
    tree <- fit_tree(s$x, y)
    for (j in seq_along(CPS)) {
      p <- tree_predict(rpart::prune(tree, cp = CPS[j]), s$z)
      tree_loss[k, j] <- mean((truth - p)^2)
    }
  }
  list(lambda = LAMBDAS[one_se(ridge_loss, LAMBDAS)],
       cp = CPS[one_se(tree_loss, CPS)],
       ridge_loss = ridge_loss, tree_loss = tree_loss)
}
tune_classification <- function(d, inner) {
  loss <- matrix(NA_real_, 5, length(CPS))
  for (k in seq_along(inner)) {
    s <- inner[[k]]
    threshold <- unname(quantile(d$views[s$train], .75))
    y <- as.integer(d$views[s$train] >= threshold)
    truth <- as.integer(d$views[s$valid] >= threshold)
    tree <- fit_tree(s$x, y, classification = TRUE)
    for (j in seq_along(CPS)) {
      p <- tree_predict(rpart::prune(tree, cp = CPS[j]), s$z, TRUE)
      loss[k, j] <- mean((truth - p)^2)
    }
  }
  list(cp = CPS[one_se(loss, CPS)], loss = loss)
}
fit_logistic <- function(x, y) {
  warnings <- character()
  fit <- withCallingHandlers(
    glm.fit(cbind(Intercept = 1, x), y, family = binomial(),
            control = glm.control(maxit = 100)),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  stopifnot(fit$converged)
  b <- fit$coefficients
  b[is.na(b)] <- 0
  list(beta = b, warnings = warnings, iterations = fit$iter)
}
regression_metrics <- function(y, p) {
  c(RMSE = sqrt(mean((y - p)^2)), MAE = mean(abs(y - p)),
    R2 = 1 - sum((y - p)^2) / sum((y - mean(y))^2))
}
roc_points <- function(y, p) {
  o <- order(-p)
  y <- y[o]
  endpoints <- c(which(diff(p[o]) != 0), length(p))
  tp <- c(0, cumsum(y)[endpoints])
  fp <- c(0, cumsum(1 - y)[endpoints])
  data.frame(fpr = fp / sum(1 - y), tpr = tp / sum(y),
    precision = c(1, tp[-1] / (tp[-1] + fp[-1])))
}
classification_metrics <- function(y, p) {
  positive <- p >= .5
  tp <- sum(positive & y == 1)
  fp <- sum(positive & y == 0)
  fn <- sum(!positive & y == 1)
  tn <- sum(!positive & y == 0)
  auc <- (sum(rank(p)[y == 1]) - sum(y) * (sum(y) + 1) / 2) /
    (sum(y) * sum(1 - y))
  curve <- roc_points(y, p)
  c(AUC = auc, AP = sum(diff(curve$tpr) * curve$precision[-1]),
    Error = mean(positive != y), Brier = mean((y - p)^2),
    Recall = tp / (tp + fn), Specificity = tn / (tn + fp),
    F1 = if ((2 * tp + fp + fn) == 0) 0 else 2 * tp / (2 * tp + fp + fn),
    TP = tp, FP = fp, FN = fn, TN = tn)
}
cluster_inference <- function(d) {
  prep <- learn_features(d)
  x <- cbind(Intercept = 1, features(d, prep))
  stopifnot(qr(x)$rank == ncol(x))
  beta <- fit_ols(x[, -1, drop = FALSE], d$log_views)
  residual <- d$log_views - drop(x %*% beta)
  scores <- rowsum(x * residual, d$channel_id, reorder = FALSE)
  bread <- solve(crossprod(x))
  n <- nrow(x); p <- ncol(x); g <- nrow(scores)
  covariance <- (g / (g - 1)) * ((n - 1) / (n - p)) *
    bread %*% crossprod(scores) %*% bread
  se <- sqrt(diag(covariance))
  critical <- qt(.975, g - 1)
  result <- data.frame(term = colnames(x), estimate = beta, se = se,
    lower = beta - critical * se, upper = beta + critical * se,
    p_value = 2 * pt(-abs(beta / se), df = g - 1))
  # Convert binary indicators from a one-SD change to FALSE -> TRUE.
  binary <- c("comments_disabled", "ratings_disabled")
  for (term in binary) {
    i <- which(result$term == term)
    result[i, c("estimate", "se", "lower", "upper")] <-
      result[i, c("estimate", "se", "lower", "upper")] / prep$scale[term]
  }
  result
}
