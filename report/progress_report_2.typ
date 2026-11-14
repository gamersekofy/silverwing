#import "ppr2_numbers.typ": results as n
#set page(paper: "us-letter", margin: (x: 1in, y: 1in),
  numbering: "1", number-align: center)
#set text(size: 11pt)
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.1")
#show heading.where(level: 1): it => block(above: 1.2em, below: 0.8em)[#it]
#set figure(gap: 0.6em)
#let headers = (R2: [R²], Fold_SD: [Fold RMSE SD], Raw_MAE: [Raw MAE],
  Raw_RMSE: [Raw RMSE], Mean_AUC: [Mean AUC], RMSE_pp: [RMSE (pp)],
  MAE_pp: [MAE (pp)], CI95: [95% CI], CV_RMSE: [CV RMSE],
  Time_RMSE: [Time RMSE], Time_MAE: [Time MAE], Time_R2: [Time R²],
  Tree_cp: [Tree cp], Class_cp: [Class cp], Class_leaves: [Class leaves])
#let result-table(file, widths, caption, size: 9.5pt) = {
  let rows = csv("ppr2_tables/" + file)
  block(breakable: false, figure({
    set text(size: size)
    table(columns: widths, inset: 5pt, stroke: 0.4pt,
      table.header(..rows.first().map(s => strong(headers.at(s, default: text(s))))),
      ..rows.slice(1).flatten().map(s => text(s)))
  }, caption: caption))
}
#let plot(file, caption, width: 100%) = block(breakable: false, figure(
  image("figures/ppr2/" + file + ".svg", width: width), caption: caption))

#align(center)[
  #text(size: 17pt, weight: "bold")[
    Modeling YouTube Video Engagement \
    and Trending Popularity
  ]
  #v(0.4em)
  #text(size: 13pt)[MATH 448 — Progress Report 2]
  #v(0.6em)
  #text(size: 11pt)[
    Jannagrace Carandang (924173494) \
    Uzair Hamed Mohammed (920142896)
  ]
  #v(0.4em)
  #text(size: 11pt)[Fall 2026]
  #v(0.6em)
  #text(size: 11pt, style: "italic")[Model implementation and performance comparison]
]
#v(0.5em)
#line(length: 100%, stroke: 0.5pt)
#v(0.6em)
*Summary.* This report moves from exploratory analysis to prediction. It implements
ordinary least squares, ridge regression, a pruned regression tree, and bagging on
#n.videos U.S. trending videos, using upload-related metadata rather than engagement
counts as predictors. Each video is evaluated only when its entire channel is held out.
The lowest cross-validated log-view RMSE is *#n.best_rmse*, obtained by *#n.best_model*,
a *#n.improvement%* reduction from the training-mean baseline. Secondary analyses examine
high-view classification, engagement rates, and conditional metadata associations.
The temporal cohort check yields negative R² for every model, so this is not a
deployment-ready view forecast.
#v(0.6em)
#outline(title: [Contents], indent: 1.2em, depth: 1)
#pagebreak()

= Problem, Data, and Changes Since PPR1

The prediction question is deliberately narrower than the project title: *among videos
that appeared on the U.S. Trending tab, how well can metadata predict their last-observed
view count?* The dataset contains no non-trending comparison group. Neither regression nor
classification below estimates the probability that an arbitrary upload will trend.
The main response is $y = ln(1 + "views")$, with natural logarithms. We compare all four
methods on this same response; comparing a regressor's RMSE with a classifier's AUC would
not be a meaningful contest.

The public Kaggle dataset, #link("https://www.kaggle.com/datasets/datasnaek/youtube-new")[
_Trending YouTube Video Statistics_ (datasnaek)], supplies 40,949 U.S. video-day snapshots
and a category lookup. PPR1's downloader and the shared `analysis/data_core.R` supply
both milestones. The two U.S. files match PPR1's recorded SHA-256 digests. Ordered
cleaning leaves 40,926 rows after removing unavailable-video records, 40,878 after exact
deduplication, and 40,876 after retaining the last duplicate video-day record. Keeping
each video's last trending snapshot yields *#n.videos videos across #n.channels channels*.
The channel count is recomputed after cleaning, not copied from the raw-data discussion.

“Last observed” is important. The dataset ends on June 14, 2018, and videos have unequal
observation windows. These outcomes are neither lifetime views nor views measured at a
common age. PPR2 preserves the PPR1 outcome definition for continuity, while stating this
limitation explicitly. It also corrects the earlier description of a 25%/75% target as
balanced: a top-quartile positive class is *imbalanced*.

== Predictor boundary

Every model receives the same metadata representation: category indicators, weekday
indicators, title character count, title word count, tag count, sine/cosine of UTC
publication hour, and comment/rating-disabled indicators. The hour encoding makes 23:00
and 00:00 adjacent rather than opposite ends of a numeric line. Categories with fewer
than 20 observations in the current training partition are pooled into “Other”; unseen
categories follow that rule as well. Zero-variance columns are removed, and all retained
columns are centered and scaled using training-partition statistics only. Trees do not
need this scaling, but receive it without changing their ordering-based split geometry.

We exclude views, likes, dislikes, comment counts, engagement ratios, identifiers, and
channel identity from the predictor matrix. *We also exclude PPR1's `days_to_trend`*:
it depends on a post-upload trending date and is unavailable at the intended prediction
time. Channel identifiers are used only to define validation groups. Category, title,
tags, and settings are recorded at snapshots, not proven to be their original upload-time
values. Thus “upload-related metadata” is a feature restriction, not a claim that the
file reconstructs an immutable upload-time information set.

= Experimental Design and Performance Measures

== Shared grouped and nested validation

The 2,198 channels are assigned to ten approximately equal-sized outer folds, using a
fixed seed (20261111) and a greedy channel-size balancing algorithm independent of the
outcomes. Each test fold contains #n.fold_min–#n.fold_max videos. All videos from a channel
stay together; assertions check zero channel overlap between training and validation
partitions. The reported errors therefore target generalization to *unseen channels*
within this historical trending-video population, not merely new videos from familiar
channels. Every method uses the same saved fold assignments.

Inside each outer training set, five further channel-grouped folds select ridge strength
and tree pruning. Pooling, coding, and scaling are relearned inside each inner training
partition. We use the one-standard-error rule: among candidates whose mean inner loss is
within one estimated standard error of the minimum, choose stronger ridge shrinkage or
more aggressive pruning. The standard error is a complexity-selection heuristic, not a
formal confidence interval from independent datasets. Bagging uses a fixed, prespecified
200-tree specification rather than tuning against outer-fold performance.

#figure(
  table(columns: (1fr, 1fr, 1.2fr), inset: 6pt, stroke: 0.4pt,
    table.header([*Stage*], [*Information allowed*], [*Purpose*]),
    [Inner training], [Its metadata and outcomes], [Learn features and fit candidates],
    [Inner validation], [Held-out channel outcomes], [Choose penalty or pruning],
    [Outer training], [Nine complete channel folds], [Refit the selected specification],
    [Outer test], [Tenth channel fold, scored once], [Compare genuine held-out predictions]),
  caption: [The validation boundary. Every video receives one out-of-fold (OOF) prediction per model.],
)

== Regression measures

For the $N$ saved out-of-fold predictions, the primary measure is
$"RMSE" = sqrt(frac(1, N) sum_(i=1)^N (y_i - hat(y)_i)^2)$.
We also report $"MAE" = frac(1,N) sum_(i=1)^N abs(y_i - hat(y)_i)$ and
$R^2 = 1 - frac(sum_i (y_i - hat(y)_i)^2, sum_i (y_i - overline(y))^2)$.
RMSE penalizes large log-scale errors; MAE is less sensitive to their tails. R² compares
pooled OOF squared error with variation about the evaluation outcomes' mean and may be
negative. The training-mean predictor is an essential no-feature baseline, not one of
the four fitted course methods. Its held-out R² need not be exactly zero.

All main metrics are pooled across videos, so every video has equal weight. The standard
deviation of the ten fold RMSEs describes fold-to-fold variability; it is *not* a 95%
confidence interval or evidence that tiny model differences are statistically decisive.
A one-unit log error corresponds to an approximately $e$-fold error in $1 + "views"$.
Raw-view errors are supplied separately using $max(0, exp(hat(y)) - 1)$, without smearing
correction. This plug-in back-transformation is not an estimate of the conditional mean
number of views; it is not the quantity used to tune or rank the main models.

= Methods Implemented

== Ordinary least squares — Chapter 3

Ordinary least squares (OLS) represents the predicted log view count as an intercept plus
an additive contribution from each encoded predictor. It chooses coefficients that
minimize the sum of squared training residuals. Category and weekday indicators let their
groups have different intercepts, while numeric coefficients summarize a linear change
holding the other features fixed. OLS is a useful first fitted benchmark because its
assumptions are transparent and its coefficients are easy to inspect. It does not
require normally distributed predictors; normal errors are also unnecessary for computing
the fitted least-squares predictions.

The tradeoff is its restricted shape: title length and tag count contribute linearly,
and no category-by-title interactions are inserted. Correlated title character and word
counts can make individual coefficients unstable. A successful OLS fit would show that
these simple additive patterns generalize across channels; a poor held-out fit would
show that low training error alone is insufficient. We compute the fit with QR-based
least squares. Its coefficients are used for prediction here; a separate cluster-robust
analysis addresses exploratory association uncertainty later.

== Ridge regression — Chapter 6

Ridge starts with the same additive representation but discourages large slope
coefficients. In our implementation the objective is
$frac(1,n) sum_(i=1)^n (y_i - beta_0 - x_i^T beta)^2 + lambda sum_(j=1)^p beta_j^2$.
The intercept is unpenalized. Increasing $lambda$ shrinks the fitted slopes toward zero,
trading some training fit for stability when predictors overlap or weak signals would
otherwise receive exaggerated weights. Unlike lasso, ridge generally does not remove a
predictor by setting its coefficient exactly to zero.

Scaling matters because this penalty acts on coefficient magnitudes. Each training
partition therefore supplies its own centers and standard deviations, including for
indicator columns. We solve the standardized ridge problem by singular-value
decomposition and check its normal equations numerically. Inner grouped CV considers
13 strengths from $10^(-4)$ to $10^2$ and applies the one-SE rule. This objective uses
*mean* squared error; penalty numbers should not be compared directly with software that
uses a differently normalized sum of squares.

== Pruned regression tree — Chapter 8, Part 1

A regression tree divides the feature space by successive yes/no questions, such as
whether a tag count exceeds a threshold, and predicts the training outcome mean in each
terminal region. The split selected at a node reduces training squared error. Different
branches can use different features, so a tree can represent thresholds and interactions
without us specifying them in advance. The resulting piecewise-constant rule is easy to
explain but can vary sharply when the training sample changes.

We grow a tree inside each inner training set and then evaluate cost-complexity-pruned
subtrees on held-out channels. The pruning grid is
$0, 0.001, 0.003, 0.01, 0.03, 0.1$ in `rpart`'s relative-complexity convention.
Growth is bounded at depth 12 with at least 20 training observations per leaf; these
limits are fixed. The one-SE rule favors a smaller eligible subtree. `rpart`'s automatic
random-fold cross-validation is disabled, because it would ignore the channel grouping.
A tree's invariance to monotone predictor rescaling does *not* make regression trees
invariant to a nonlinear transformation of the response: we explicitly fit log views.

== Bagging — Chapter 8, Part 2

Bagging averages many trees rather than trusting one high-variance partition. For each
of 200 trees we sample the outer training videos with replacement, grow a relatively
deep regression tree, and predict the held-out videos; the final prediction is the mean
of those 200 predictions. Different resamples yield different split decisions, and
averaging can reduce their variance. It does not guarantee that bias falls or that the
ensemble beats a regularized linear model when the metadata signal is weak.

All predictors remain eligible at every split. This is *bagging, not a random forest*;
random forests add random per-split feature subsets. Base trees use zero pruning penalty,
minimum leaf size 5, and a depth cap of 20. The tree count and these limits were fixed
before evaluation, and seeds are fixed per outer fold. Ordinary row bootstraps are used
only within the training set; evaluation still holds out entire channels. We do not use
ordinary row-level out-of-bag error as a substitute for unseen-channel validation. The
first 100 and all 200 trees are saved as a Monte Carlo stability diagnostic.

== Logistic regression and classification trees — Chapter 4 and Chapter 8

For the secondary binary task, logistic regression models the probability of exceeding a
training-defined high-view threshold through a linear log-odds score,
$P(Y=1 mid(|) x) = frac(1, 1 + exp(-(beta_0 + x^T beta)))$.
Its output is a probability, not a continuous predicted view count. An additive score
is interpretable, but rare indicators can cause separation, so convergence and numerical
warnings are recorded. We use the same metadata and grouping as the regression task,
and an ordinary binomial fit rather than claiming that it is penalized logistic regression.

Classification trees instead use Gini-based splits and terminal class probabilities;
bagged classifiers average those probabilities across the same fixed 200-tree design.
Inner grouped CV selects the single tree's pruning penalty by Brier loss, again preferring
a simpler eligible model. `rpart` uses its classification risk convention for pruning,
not a regression RSS penalty. All classifiers use a fixed probability cutoff of 0.5 for
confusion matrices and F1. ROC-AUC assesses ranking separately from that cutoff.

= Main Regression Results

#result-table("main.csv", (1fr, auto, auto, auto, 1fr),
  [Shared channel-grouped outer-CV results on log(1 + views). Lower RMSE/MAE and higher R² are better.])

#plot("performance",
  [Outer-fold errors (open circles) and pooled OOF errors (diamonds). Fold variability is descriptive, not an independent-sample confidence interval.])

The best observed pooled RMSE is #n.best_rmse for #n.best_model, compared with
#n.baseline_rmse for the training-mean predictor. That is a #n.improvement% reduction in
log-scale RMSE, with MAE #n.best_mae and R² #n.best_r2. We use “best observed” rather than
claiming universal superiority: the winner is chosen after comparing these estimates,
and it has not been confirmed on a separate untouched final test set.

OLS explains only about #n.ols_pct% of held-out log-view variation. Ridge and the pruned
tree have similar RMSEs (#n.ridge_rmse and #n.tree_rmse), while bagging is worse at
#n.bag_rmse despite
its greater flexibility. Thus the data do not support a claim that a more complex
method must predict better. The inner one-SE rule selects ridge strength 1 in every
outer fold and regression trees with only #n.leaves_min–#n.leaves_max leaves. Weak metadata
signal and missing channel-popularity information are plausible limitations, not
identified explanations of the ranking. The small gaps between fitted models should
not be described as conclusive statistical superiority.

For bagging, moving from the first 100 trees to all 200 changes log predictions by an
RMS of #n.bag_change and changes pooled RMSE from #n.bag_100_rmse to #n.bag_200_rmse.
The corresponding probability RMS change is #n.bag_class_change. These are finite-tree
stability diagnostics, not proof that Monte Carlo variation has vanished or a reason
to choose the tree count using these held-out outcomes.

#plot("predictions",
  [Observed versus OOF-predicted log views. Each panel contains all 6,348 videos; the dashed diagonal is perfect prediction. Concentration toward the center exposes failures to recover extreme outcomes.])

#plot("diagnostics",
  [Residual and normal-Q-Q diagnostics for the model with the lowest pooled RMSE. These use held-out predictions, not residuals from fitting the entire dataset.])

== Back-transformed errors

#result-table("raw.csv", (1fr, 1fr, 1fr),
  [Errors in views after the simple nonnegative plug-in back-transform. These are supplementary, not the tuning criterion.])

Large raw-scale errors are expected because a few videos have enormous view counts and
the models were trained to minimize errors in logarithms. Different rankings on this
table and the log-scale table would not be a contradiction: they emphasize different
parts of the outcome distribution. We do not equate a back-transformed log prediction
with an unbiased expected view count. In this run bagging has the lowest raw-view
RMSE, whereas OLS has the lowest log RMSE and raw-view MAE; the choice of loss matters.

== Temporal robustness check

We also prespecify May 1, 2018 as a time boundary: training uses videos whose last trending
snapshot is before May 1, and testing uses videos whose first trending snapshot is on or
after May 1. This yields #n.temporal_train training videos and #n.temporal_test test videos;
#n.temporal_excluded videos spanning the boundary are excluded. Selection is repeated only
within the earlier training data. No video appears on both sides.

#result-table("temporal.csv", (1fr, auto, auto, auto, auto),
  [Channel-grouped CV versus the separate temporal stress test. The populations and difficulty differ, so these are not paired estimates of the same test risk.])

Unlike the primary unseen-channel comparison, this time check permits channels to recur:
#n.temporal_seen test videos come from channels seen earlier. It is a historical
first-trending-period stress test, not a deployment forecast of all new uploads. Snapshot
metadata and variable outcome observation windows remain limitations. The time test is
reported for all prespecified models, not used to retune them.

The temporal result is a warning, not a confirmation of robustness: all five test R²
values are negative. #n.time_best_model has the smallest temporal RMSE (#n.time_best_rmse),
so the ranking reverses relative to the primary comparison, but even that model performs
worse in squared error than an oracle constant using the later test outcomes' mean.
That oracle is a diagnostic reference, not an available deployment predictor. Mean log
views shift from #n.time_train_mean in the earlier training cohort to #n.time_test_mean
in the later test cohort. The shift is upward, so truncated follow-up alone cannot
explain it. Cohort composition, trending-duration differences, and unequal observation
windows cannot be disentangled by this test.

= Secondary Prediction Tasks

== High-view classification

PPR1 defined “high engagement” using top-quartile views, which is more precisely a
*high-view* label rather than a per-view engagement rate. To avoid learning the label
boundary from held-out outcomes, each training partition supplies its own 75th-percentile
view cutoff; its validation partition is labeled using that same cutoff. This is repeated
inside inner CV as well as the outer loop. The outer cutoffs range from #n.cutoff_min to
#n.cutoff_max views, rather than freezing PPR1's full-data exploratory cutoff. The pooled
held-out positive share is #n.prevalence%.

#result-table("classification.csv", (1fr, auto, auto, auto, auto, auto, auto),
  [AUC is the mean of ten fold-specific ROC-AUCs. AP is pooled average precision with score ties handled together. Error, F1, recall, and Brier loss use pooled OOF predictions; the class decision cutoff is 0.5.], size: 9pt)

The strongest mean fold AUC is #n.best_auc for #n.best_class, with a fold-AUC standard
deviation of #n.auc_sd. The majority classifier predicts the training prevalence and
labels every case negative at 0.5. Its low-looking error is not evidence of useful
positive-class detection: its recall and F1 are zero. AUC, AP, Brier loss, and the
confusion counts expose tradeoffs that accuracy alone would miss. Because training-derived
cutoffs differ slightly across folds, fold-specific AUC is the primary ranking summary;
the pooled curves below are descriptive cross-fitted summaries. All ten logistic fits
converged; #n.logistic_warnings outer fits emitted numerical warnings, recorded verbatim
in the saved classification-parameter table. The one-SE rule prunes the single
classification tree to its root in every outer fold, making it identical to the majority
predictor. It is a fitted-and-validated result, not an omitted model. Logistic regression
ranks better than bagging but detects only #n.logistic_recall% of positives at 0.5;
bagging raises recall to #n.bag_recall% with more false positives. A threshold chosen for a particular recall/cost
objective would require training-only selection, which is not attempted here. Small
pooled AP/ROC departures for constant-within-fold predictors reflect differences in
fold prevalence scores, not genuine within-fold discrimination.

#plot("classification",
  [ROC and precision-recall curves from pooled cross-fitted probabilities. Dashed references are random ranking and the observed positive prevalence, respectively.])

#result-table("confusion.csv", (1fr, auto, auto, auto, auto),
  [OOF confusion counts: TN/FP are actual negatives; FN/TP are actual positives.])

== Engagement-rate regression

Like rate and comment rate address a distinct question: how much recorded interaction
occurs per view? These responses are not supplied as predictors. We apply the mean,
OLS, ridge, and pruned-tree procedures to both rates using the same outer channel folds
and target-specific inner tuning. Bagging is reserved for the primary log-view and
classification comparisons to keep the secondary analysis focused.

#result-table("rates.csv", (1fr, auto, auto, auto, auto),
  [Secondary rate predictions. RMSE and MAE are percentage points (pp), not relative percentage errors; R² is dimensionless.])

Ratios have a denominator and a bounded domain; squared-error linear fits need not remain
inside that domain. No test-outcome-dependent clipping or binomial-trial interpretation
is imposed. Comments-disabled videos have structurally zero recorded comment counts,
and ratings-disabled videos can likewise have structural zeros in rating outcomes.
A model using those flags can learn the recording mechanism, not necessarily an underlying
audience preference. OLS has the strongest rate results here: R² is #n.like_r2 for
like rate and #n.comment_r2 for comment rate. The one-SE comment-rate tree collapses to its baseline;
there is no useful tree improvement to claim. These results should not be interpreted as predictions of
engagement that would have occurred had every interaction option been available.

= Exploratory Associations, Not Causal Effects

A separate full-video-level OLS model estimates conditional associations with log views.
It uses the same metadata representation but is not the source of the held-out performance
numbers. Confidence intervals use a channel-clustered sandwich covariance with the CR1
finite-sample adjustment and a $t$ reference with $G-1$ degrees of freedom, where
$G = 2198$. This allows heteroskedasticity and arbitrary residual dependence within a
channel while assuming independent channels. It is more appropriate here than treating
all videos as unrelated observations.

#result-table("inference.csv", (1.6fr, auto, 1.1fr, auto),
  [Selected adjusted OLS associations; category and weekday indicators are included as controls. Continuous features use a one-SD increase; disabled flags use a full 0-to-1 change.])

#plot("inference",
  [Channel-clustered 95% intervals. Crossing zero indicates that the corresponding unadjusted two-sided interval does not distinguish the association from zero.])

A one-SD increase is about #n.title_sd title characters or #n.tag_sd tags. The two title
measures enter jointly, so their individual coefficients represent changes holding the
other fixed, not the total effect of rewriting a title. UTC hour is represented by a
sine/cosine pair; neither coefficient alone is a “best publishing hour.” Intervals and
$p$-values are exploratory and not adjusted for multiple comparisons. Rare flags are
particularly uncertain. Tag count has a positive adjusted association (#n.tag_est log
units per SD, 95% CI [#n.tag_low, #n.tag_high]); title characters have a negative
association after controlling for title word count (#n.title_est,
CI [#n.title_low, #n.title_high]). The hour components and
disabled flags do not have intervals excluding zero. These observations do not establish
a benefit from adding tags or shortening a title. Unmeasured channel popularity, content quality, and audience
composition prevent causal interpretation, regardless of whether an interval excludes zero.

= Limitations and Conclusions

The comparison is reproducible but conditional on the available sample. Selection into
Trending, unequal follow-up, snapshot metadata edits, absent subscriber counts, UTC rather
than audience-local time, and rare flags all constrain interpretation. Grouping by channel
addresses one form of dependence but does not remove common time shocks or confounding.
Title/tag keywords, thumbnails, and semantic content are deliberately outside this
metadata-only comparison. No result establishes what causes a video to trend.

The four implemented regression methods satisfy the method-comparison objective using
an identical target and validation boundary. #n.best_model achieves the lowest observed
log-view RMSE (#n.best_rmse), but the useful conclusion is the size and consistency of
its improvement over the baseline, not its name alone. Classification separates ranking
from a fixed-threshold decision, rate outcomes distinguish volume from interaction per
view, and the inference analysis remains explicitly associational. Lasso, random forests,
boosting, and SVMs from the initial roadmap are not claimed as completed methods; this
milestone uses the verified available toolchain rather than silently changing dependencies.
The failed temporal check is a material finding: the modest cross-sectional improvement
does not establish reliable performance under cohort and observation-window shift.

= Reproducibility and References

The implementation requires R with its recommended `rpart` package. The exact versions
and code/data fingerprints are recorded in
`analysis/output/ppr2/run_manifest.txt`. Run from the repository root:
#[
  #set text(size: 8pt)
  #raw("Rscript --vanilla analysis/download_data.R\nRscript --vanilla analysis/tests/test_ppr2.R\nRscript --vanilla analysis/ppr2_run.R\nRscript --vanilla analysis/tests/audit_ppr2_outputs.R\nRscript --vanilla analysis/ppr2_present.R\ntypst compile --root . report/progress_report_2.typ", block: true, lang: "sh")
]
The runner checkpoints completed folds and refuses to reuse a checkpoint with a different
code/data fingerprint. Saved fold assignments, OOF predictions, selected parameters,
confusion counts, and temporal splits make the tables independently checkable. Tables
and summary numbers are generated directly from those outputs; the appendix reads the
same source files that were executed, rather than a separately copied listing. PPR1 and
its existing figures are preserved.

+ datasnaek. _Trending YouTube Video Statistics_. Kaggle,
  #link("https://www.kaggle.com/datasets/datasnaek/youtube-new").
+ MATH 448 lecture materials: Chapters 3 (linear regression), 4 (classification),
  5 (resampling), 6 (ridge/model selection), and 8 Parts 1–2 (trees and bagging).
  Course-source mapping is used to distinguish covered methods from unimplemented extensions.
+ James, G., Witten, D., Hastie, T., and Tibshirani, R. _An Introduction to Statistical
  Learning, with Applications in R_, second edition. Springer, 2021.
+ Therneau, T. and Atkinson, B. `rpart` package documentation, version recorded in
  the run manifest. Pruning parameters follow this implementation's convention.

#pagebreak()
#set heading(numbering: none)
= Appendix: Executed Analysis Code

The following files are the executable implementation, figure/table generation, and
verification code. Raw data and generated prediction tables are not duplicated as code.
Listings retain the actual source rather than abbreviated pseudocode.
#let listing(path, language) = {
  set text(size: 8pt)
  set par(justify: false, leading: .35em)
  raw(read(path), lang: language, block: true)
}
== A. Public data retrieval — reused from PPR1
The existing `analysis/download_data.R` performs retrieval and integrity checks. It is
supplied in the source bundle; no separate PPR2 downloader is maintained.
== B. Shared PPR1 preparation and PPR2-only features
#listing("../analysis/data_core.R", "r")
#listing("../analysis/ppr2_data.R", "r")
== C. Models, metrics, and clustered covariance
#listing("../analysis/ppr2_models.R", "r")
== D. Grouped evaluation and saved outputs
#listing("../analysis/ppr2_run.R", "r")
== E. Computed tables and vector figures
#listing("../analysis/ppr2_present.R", "r")
== F. Numerical and leakage-control tests
#listing("../analysis/tests/test_ppr2.R", "r")
== G. Independent checks of saved predictions
#listing("../analysis/tests/audit_ppr2_outputs.R", "r")
