#set page(
  paper: "us-letter",
  margin: (x: 1in, y: 1in),
  numbering: "1",
  number-align: center,
)
#set text(size: 11pt)
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.1")
#show heading.where(level: 1): it => block(above: 1.2em, below: 0.8em)[#it]
#set figure(gap: 0.6em)

#align(center)[
  #text(size: 17pt, weight: "bold")[
    Modeling YouTube Video Engagement \
    and Trending Popularity
  ]
  #v(0.3em)
  #text(size: 13pt)[MATH 448 --- Progress Report 1]
  #v(0.8em)
  #text(size: 11pt)[
    Jannagrace Carandang (924173494) \
    Uzair Hamed Mohammed (920142896)
  ]
  #v(0.3em)
  #text(size: 10pt, style: "italic")[Fall 2026]
]

#v(0.5em)
#line(length: 100%, stroke: 0.5pt)
#v(0.5em)

#outline(title: [Contents], indent: 1.2em, depth: 2)

#pagebreak()

= Introduction and Objectives

YouTube is the largest video-sharing platform in the world, and for a large class of
creators and marketers the "Trending" tab is the main discovery surface they compete for.
The platform's own ranking logic is hidden, but creators control a documented set of
upload-time decisions --- which category to publish in, what time and day to release, how
long the title is, how many tags to attach, and whether comments and ratings are enabled.
This project studies the relationship between those controllable, upload-time metadata
factors and the post-release performance of videos that reached the Trending tab.

== Objectives

Following the project proposal, we pursue three complementary goals:

+ *Regression.* Predict continuous engagement outcomes --- in particular
  `log(1 + views)` and engagement ratios such as `likes/views` (like rate) and
  `comment_count/views` (comment rate).
+ *Classification.* Predict whether a video attains "High Engagement," defined here as a
  top-quartile final view count.
+ *Inference.* Estimate whether creator-controlled choices (publish time, title length,
  tag count, comment/rating settings) have statistically significant effects on audience
  reception, and in which direction.

The first two are prediction tasks; the third is a statistical-inference task, and the two
call for different tools (see @sec-modeling).

== Research questions

+ *RQ1 (regression).* How much of the variation in `log(1 + views)`, like rate, and comment
  rate can upload-time metadata explain, and which metadata features carry the most signal?
+ *RQ2 (classification).* Can upload-time metadata distinguish top-quartile-view videos from
  the rest, and how well (ROC-AUC, error rate)?
+ *RQ3 (inference).* Are the associations between creator choices and engagement
  statistically significant and stable, after controlling for topic (category)?

== Scope of this report

This first progress report establishes the empirical foundation: it imports and audits the
data, defines the analysis unit, preprocesses and engineers features, performs exploratory
data analysis (EDA), documents data issues and leakage risks, and lays out the initial
modeling and validation plan. Model fitting and final results are deferred to Progress
Report 2.

= Data Overview

== Source and scope

The data come from the *"Trending YouTube Video Statistics"* dataset (Kaggle), which
provides daily snapshots of the videos appearing on the Trending tab across several
countries. We use the *US* file, `USvideos.csv`, together with the label mapping
`US_category_id.json`. The file we analyzed has exactly *40,949 rows and 16 columns*,
spanning trending dates from *2017-11-14 to 2018-06-14* (205 distinct days). (We flag a
citation check in @sec-issues: the proposal attributes the set to a specific contributor
that should be verified against the Kaggle listing.)

== Unit of analysis

Each row is a *video-day snapshot*: a video appears once for every day it stayed on the
Trending tab, with cumulative counts as of that day. This structure is central to the whole
project. In the raw file there are only *6,351 unique `video_id` values* across the
40,949 rows: on average each video appears *6.45* times, up to *30* times, and *88.9%*
of videos appear on two or more days. We therefore work at two levels:

+ *Snapshot level* --- all 40,876 cleaned snapshot rows, used only to study trending
  duration and growth.
+ *Video level* --- one row per video (its *last* trending snapshot, i.e. final cumulative
  performance), giving *n = 6,348* videos. This is the unit for modeling. Keeping the
  *last* snapshot makes the outcome "final cumulative views," and it is the choice that
  avoids the most leakage (@sec-issues).

== Variables

The 16 raw variables and their role in the analysis are summarized in @tbl-vars. Outcomes
are the cumulative engagement counts; predictors are upload-time metadata. Several
predictors are *derived* from raw text/time fields during preprocessing (@sec-preproc).

#figure(
  table(
    columns: (auto, auto, auto, 1fr),
    inset: 5pt,
    stroke: 0.4pt,
    align: (left, left, left, left),
    table.header([*Variable*], [*Type*], [*Role*], [*Description*]),
    [`video_id`],        [string],      [identifier],   [Unique video key; not a predictor.],
    [`trending_date`],   [date],        [sampling],     [Day the video appeared in Trending; format `YY.DD.MM`.],
    [`title`],           [text],        [feature src],  [Video title; source of title-length/word features.],
    [`channel_title`],   [categorical], [group/feature],[Channel name; 2,207 levels.],
    [`category_id`],     [categorical], [predictor],    [Topic bucket; 16 levels used.],
    [`publish_time`],    [datetime],    [feature src],  [Upload timestamp (UTC).],
    [`tags`],            [text list],   [feature src],  [Pipe-separated keywords; `[none]` if absent.],
    [`views`],           [integer],     [outcome],      [Cumulative views at snapshot.],
    [`likes`],           [integer],     [outcome],      [Cumulative likes.],
    [`dislikes`],        [integer],     [outcome],      [Cumulative dislikes.],
    [`comment_count`],   [integer],     [outcome],      [Cumulative comments.],
    [`thumbnail_link`],  [URL],         [drop],         [Thumbnail URL; ID-like, no signal.],
    [`comments_disabled`],[boolean],    [predictor],    [Comments turned off (rare).],
    [`ratings_disabled`],[boolean],     [predictor],    [Ratings turned off (rare).],
    [`video_error_or_removed`],[boolean],[filter],      [Video unavailable; used as a filter.],
    [`description`],     [text],        [drop],         [Description text (570 missing); unused.],
  ),
  caption: [Raw variables, types, roles, and descriptions. `X` = predictor, `Y` = outcome.],
) <tbl-vars>

*Outcomes.* `views`, `likes`, `dislikes`, `comment_count`; plus derived `log(1 + x)`
transforms and the ratios `like_rate`, `comment_rate`, `dislike_rate`.

*Predictors.* `category`, `publish_hour`, `publish_dayofweek`, `title_length`,
`title_word_count`, `tag_count`, `days_to_trend`, `comments_disabled`, `ratings_disabled`.
The engagement counts and `thumbnail_link` are *excluded* from `X` for leakage reasons
(@sec-issues).

= Preprocessing <sec-preproc>

== Data-quality audit

Before transforming anything we audited the raw file. Findings:

+ *Missing values.* There is almost none. Only `description` has nulls (570 rows, about 1.4%),
  plus 8 empty strings. Since `description` is not used, no imputation is required.
+ *Sentinels.* `tags` uses the literal string `[none]` in *1,535* rows (about 3.8%). This must
  be mapped to "zero tags," not counted as one tag.
+ *Duplicates.* 48 fully duplicated rows and 2 duplicate `(video_id, trending_date)` pairs.
+ *Flags.* `video_error_or_removed` is TRUE for only *23* rows; `comments_disabled` and
  `ratings_disabled` are TRUE for 1.55% and 0.41% of rows.
+ *Logical consistency.* No violations: no row has `likes`, `dislikes`, or `comment_count`
  exceeding `views`, and every row with `comments_disabled = TRUE` has `comment_count = 0`
  (a structural, not a data-entry, relationship).

== Cleaning steps

The cleaning pipeline and the row count after each step are shown in @tbl-clean. Each step
is justified:

+ *Drop `video_error_or_removed`.* These 23 rows describe videos that are no longer
  available; their engagement counts are unreliable and they cannot be modeled fairly.
+ *Drop exact duplicates.* 48 rows are byte-identical repeats (data-collection artifacts)
  and would otherwise double-count those videos.
+ *Drop duplicate video-days.* 2 rows repeat the same `(video_id, trending_date)` pair;
  these are redundant snapshots of the same day.
+ *Collapse to one row per video.* We keep each video's *last* trending snapshot
  (maximum `trending_date`), which encodes final cumulative performance and removes the
  within-video dependence that would otherwise leak across folds (@sec-issues).

#figure(
  table(
    columns: (1fr, auto, auto),
    inset: 5pt,
    stroke: 0.4pt,
    align: (left, right, right),
    table.header([*Step*], [*Rows removed*], [*Rows remaining*]),
    [Raw file],                                   [---], [40,949],
    [Drop `video_error_or_removed`,              ], [23], [40,926],
    [Drop fully-duplicated rows],                  [48], [40,878],
    [Drop duplicate `(video_id, trending_date)`],  [2],  [40,876],
    [Collapse to one row per video (last snapshot)], [---], [6,348 videos],
  ),
  caption: [Cleaning pipeline with observation counts. The final analysis table has 6,348 videos.],
) <tbl-clean>

== Derived features and transformations

+ `trending_date` is parsed with the format `YY.DD.MM` (an unusual, easy-to-misread layout:
  `17.14.11` means 2017-11-14); `publish_time` is ISO-8601 UTC. `days_to_trend` is the gap
  between the two.
+ `publish_hour` and `publish_dayofweek` are extracted from `publish_time`.
+ `title_length` (characters) and `title_word_count` (whitespace tokens) are derived from
  `title`.
+ `tag_count` counts pipe-separated tags, with `[none]` mapped to 0.
+ `category` is the human-readable name from `US_category_id.json`.
+ *Log transform.* We use `log(1 + x)` for views, likes, dislikes, and comments to stabilize
  the severe right-skew (@fig-views) while handling the zeros in the like/dislike/comment
  counts (32, 99, and 140 videos respectively).
+ *Ratios.* `like_rate`, `comment_rate`, `dislike_rate` are computed per view.
+ *Label.* `high_views = 1` if final views are in the top quartile, i.e. at least
  *1,473,578* views (a balanced 25% / 75% split).

The final video-level table (`analysis/output/videos.csv`) has `n = 6,348` rows and is the
input to EDA and modeling.

= Exploratory Data Analysis

== The response is severely right-skewed

@fig-views contrasts raw views with their log transform. Raw views have skewness *14.2*,
with the median (516,214) far below the mean (1,962,282) and a maximum of 225 million; the
transform brings skewness to about *-0.5* and a roughly bell-shaped distribution. This
directly justifies the log transformation for all count outcomes. (The same pattern holds
for likes, dislikes, and comments, whose raw skewnesses are 12.5, 44.9, and 24.1.)

#figure(
  image("figures/fig01_views_transform.png", width: 92%),
  caption: [Raw views (left) versus `log(1 + views)` (right) at the video level. The log transform removes almost all of the skew.],
) <fig-views>

== Category is the strongest categorical signal

@fig-cat shows `log(1 + views)` by category. Gaming and Music have the highest median
views, followed by Film & Animation and Comedy; News & Politics and Nonprofits & Activism
sit lowest. The spread within categories is large, so category is informative but far from
deterministic. Two categories have very few observations (Nonprofits & Activism, n = 14;
Shows, n = 4), which will need care (pooling or regularization).

#figure(
  image("figures/fig02_logviews_by_category.png", width: 92%),
  caption: [`log(1 + views)` by category (video level), ordered by median.],
) <fig-cat>

== Engagement ratios differ by category

@fig-eng plots like rate and comment rate by category. Like rates cluster around 2–4%, and
the ordering of categories by like rate does not perfectly match the ordering by views ---
large-view categories are not uniformly the most "engaging" per view, which motivates
treating ratios as distinct outcomes rather than proxies for views.

#figure(
  image("figures/fig03_engagement_by_category.png", width: 92%),
  caption: [Like rate and comment rate by category (x-axis truncated at 0.15 for readability).],
) <fig-eng>

== Comment/rating settings

Only 105 videos have comments disabled and 30 have ratings disabled at the video level.
@fig-flags compares `log(1 + views)` across these groups. The groups are small --- a
data-issue in its own right --- but useful for a first look at whether disabled settings
co-occur with weaker performance.

#figure(
  image("figures/fig04_flags_vs_views.png", width: 92%),
  caption: [`log(1 + views)` by `comments_disabled` and `ratings_disabled`.],
) <fig-flags>

== Time effects are mild

@fig-time shows mean `log(1 + views)` by publish hour and day of week. The hour profile is
nearly flat, with a modest bump in the early UTC morning, and Thursday/Friday publish days
are slightly higher. Crucially, `publish_hour` is *UTC*, not US-local, so these patterns
are confounded by timezone (@sec-issues). The effect sizes are small relative to the
category spread.

#figure(
  image("figures/fig05_time_effects.png", width: 92%),
  caption: [Mean `log(1 + views)` by publish hour (UTC, left) and day of week (right).],
) <fig-time>

== Text and tag features carry weak linear signal

@fig-text plots `log(1 + views)` against title length and tag count. Title length has a
weak negative association (`r = -0.06`) and tag count a weak positive one (`r = 0.14`). The
relationships look non-linear and heteroskedastic, which is exactly the kind of pattern
that tree-based models may capture better than a linear fit.

#figure(
  image("figures/fig06_text_metrics.png", width: 92%),
  caption: [`log(1 + views)` versus title length (left) and tag count (right), with linear trend lines.],
) <fig-text>

== Collinearity and leakage become visible in the correlation matrix

@fig-corr is the correlation matrix. It surfaces two important facts. First, the count
outcomes are almost perfectly co-linear: `log(views)` correlates *0.87* with
`log(likes)`, *0.87* with `log(dislikes)`, and *0.79* with `log(comments)`. Second,
`days_to_trend` is negatively correlated with views (`-0.14`), i.e. videos that trend
quickly after publishing tend to have higher final views.

#figure(
  image("figures/fig07_correlation.png", width: 88%),
  caption: [Correlation matrix of numeric features (video level). Strong outcome-outcome correlations confirm that counts cannot be used as one another's predictors.],
) <fig-corr>

== Class balance and snapshot multiplicity

@fig-class shows the classification target is a clean 25%/75% split, and that snapshot
multiplicity is highly variable across videos --- the visual companion to the leakage
discussion in @sec-issues.

#figure(
  image("figures/fig08_class_and_multiplicity.png", width: 92%),
  caption: [Left: the top-quartile-view target is balanced. Right: distribution of the number of daily snapshots per video in the raw data.],
) <fig-class>

= Data Issues, Limitations, and Leakage Risks <sec-issues>

+ *Severe right-skew.* Counts span several orders of magnitude (skew up to 44.9 for
  dislikes). Mitigation: `log(1 + x)` responses, robust metrics, and tree models that are
  invariant to monotone transforms of the target.
+ *Temporal / repeated-measures leakage.* The raw table's 40,949 rows describe only 6,351
  videos, and counts are *cumulative*. Rows for the same video are dependent, so a naive
  random split would put the same video's earlier and later snapshots in both train and
  test. Mitigation: model at the video level and use grouped cross-validation
  (@sec-modeling).
+ *Contemporaneous leakage.* `likes`, `dislikes`, and `comment_count` are near-perfectly
  correlated with `views` (0.79–0.87) because they accumulate together. Using them to
  predict views (or using counts to predict ratios) is leakage, not signal. Mitigation:
  restrict `X` to upload-time metadata and justify the exclusion explicitly.
+ *Selection bias.* The file contains only videos that *trended*. There is no comparison
  set of non-trending videos, so all conclusions are conditional on trending, and we cannot
  estimate "what causes a video to trend." The classification target is therefore
  "high engagement *among trending videos*."
+ *Rare flags and class imbalance.* `comments_disabled` (1.5%) and `ratings_disabled` (0.4%)
  are near-constant; `video_error_or_removed` (0.06%) is a filter. Near-constant predictors
  can cause quasi-separation in logistic regression and unstable coefficients.
+ *Missing data and sentinels.* Effectively no missingness; the real issues are the `[none]`
  tag sentinel (1,535 rows) and the unused `description` nulls (570 rows).
+ *Outliers and anomalies.* Views reach 225 million; `days_to_trend` reaches *4,215 days*
  (about 11.5 years), with 69 videos published more than a year before trending --- an
  "old catalog resurfacing" effect. These warrant a conscious keep/flag decision rather than
  silent deletion.
+ *Unobserved heterogeneity.* The data lack channel-level covariates such as subscriber
  count, and 2,207 channels recur, so channel popularity is folded into unexplained
  variance and repeated-channel rows can contaminate folds. Mitigation: group by channel.
+ *Timezone caveat.* `publish_time` is UTC, so `publish_hour` is not local US time; any
  "best time to publish" conclusion is provisional.
+ *Provenance.* The attribution of the dataset to a specific Kaggle contributor should be
  verified before submission (the shape and date range match the commonly cited
  "Trending YouTube Video Statistics" release).

= Initial Modeling Plan <sec-modeling>

== Analysis unit and targets

All models are fit on the *video-level* table (n = 6,348). Targets are:

+ Regression: `log(1 + views)`, `like_rate`, `comment_rate` (and `log(1 + dislikes)` as a
  secondary response reflecting the proposal).
+ Classification: `high_views` (top-quartile final views, threshold 1,473,578).

Predictors are the upload-time metadata set from @tbl-vars. We exclude all engagement
counts, `thumbnail_link`, `description`, and identifiers, and we fit every
encoder/imputer/scaler inside the training folds only.

== Candidate methods and why

*Regularized linear regression (Ridge / LASSO).* The design has a 16-level categorical and
several correlated/time-derived features. Ridge stabilizes coefficients under collinearity;
LASSO performs feature selection and yields a sparse, interpretable set of metadata effects.
We tune the penalty by nested cross-validation.

*Tree ensembles (Random Forest, Gradient Boosting).* EDA showed weak, non-linear, and
heteroskedastic marginal relationships (title length, tag count) and probable interactions
(for example, the effect of title length may differ by category). Trees capture these
without manual specification and provide permutation-importance and partial-dependence
summaries.

*Classification models (penalized logistic regression and SVM).* Logistic regression is
interpretable and well-suited to a balanced binary target; SVMs with linear and RBF kernels
provide a flexible non-linear benchmark. We tune the regularization strength (and `gamma`
for RBF) by grouped CV.

For *inference* (RQ3), separate from the predictive comparison, we fit an ordinary
least-squares / GLM model on the interpretable feature set with heteroskedasticity-robust
standard errors and report standardized coefficients with 95% confidence intervals. We treat
the regularized and tree models as predictive tools only, since shrinkage and
non-linearity complicate formal significance testing.

== Validation framework

+ *Grouped cross-validation.* Because snapshots repeat within videos and channels repeat
  across the data, we use `GroupKFold` grouped by `video_id` (snapshot level) and by
  `channel_title` (video level), with stratification on the binary target. This prevents the
  leakage identified in @sec-issues.
+ *Nested CV.* Hyperparameters are tuned in an inner loop so that the reported error is not
  optimistic.
+ *Temporal holdout (secondary).* As a robustness check we train on earlier trending dates
  and test on the most recent period, to see whether conclusions hold out of time.
+ *Reproducibility.* Fixed random seeds and a saved feature-engineering pipeline.

== Evaluation metrics

Regression: RMSE and MAE on the log scale (and, after back-transformation, on the raw scale)
plus R-squared. Classification: ROC-AUC, error rate, and F1 / confusion matrix at the
selected threshold.

== Planned comparisons

We will compare (i) a metadata-only baseline against (ii) the regularized and tree models,
to quantify how much signal upload-time metadata actually contains, and we will report the
inference model's coefficient table separately for the significance question. Residual
diagnostics and partial-dependence plots will be used to check that any apparent
non-linearity is real rather than an artifact of outliers.

= Summary and Next Steps

This report imported and audited the US YouTube trending data (40,949 rows, 16 columns),
identified the correct unit of analysis (6,348 videos after collapsing daily snapshots),
preprocessed and engineered features with explicit leakage controls, and produced an EDA
that establishes severe right-skew, category effects, weak time/title/tag signal, and
strong outcome-collinearity. It also documented the principal data issues: repeated-measures
and contemporaneous leakage, selection bias from observing only trending videos, rare flags,
a tag sentinel, outliers, a UTC timezone caveat, and missing channel covariates.

*Next steps (Progress Report 2).* (1) Implement the grouped, nested cross-validation
pipeline; (2) fit and tune the regression, tree, and classification models; (3) fit the
inference model with robust standard errors and interpret the coefficients; (4) compare all
models on the agreed metrics and visualize importances and partial dependence.

#pagebreak()

= Appendix: Analysis Code

The following scripts reproduce every number and figure in this report. They are also in the
project repository under `analysis/`.

#v(0.3em)
== `profile_data.py` --- data audit
#[
  #set text(size: 7pt)
  #raw(read("../analysis/profile_data.py"), lang: "python", block: true)
]

#v(0.6em)
== `clean_eda.py` --- cleaning, feature engineering, figures
#[
  #set text(size: 7pt)
  #raw(read("../analysis/clean_eda.py"), lang: "python", block: true)
]

#v(0.6em)
== `report_numbers.py` --- summary statistics cited above
#[
  #set text(size: 7pt)
  #raw(read("../analysis/report_numbers.py"), lang: "python", block: true)
]

#v(0.6em)
= References

+ Jolly, M. (and/or the corresponding Kaggle release). *Trending YouTube Video Statistics*.
  Dataset, Kaggle. (Verify the exact contributor/citation before submission.)
+ YouTube. *Trending* and platform documentation, 2018.
