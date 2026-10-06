# Review of `specifications.md` against the proposal, data, and rubric

**Verdict:** the plan is a solid skeleton and its headline claims are all *factually correct*
against the data. It correctly identifies the dataset shape, the multi-day snapshot
structure, the right-skew problem, and a sensible method menu. However, it has several
gaps that matter for a high-quality report — most importantly around **the unit of
analysis, leakage, the inference objective, and grouped validation**. All issues below are
backed by values I actually computed from `data/USvideos.csv`.

---

## 1. What the plan gets right (verified)

| Plan claim | Verified | Evidence |
|---|---|---|
| `USvideos.csv`, n ≈ 40,949, p = 16 | ✅ exact | `shape = (40949, 16)` |
| Multi-day repeated records cause leakage | ✅ | 40,949 rows but only **6,351** unique `video_id`; mean **6.45** snapshots/video, **max 30**; **88.9%** of videos trended ≥ 2 days |
| Heavy right-skew needs log transform | ✅ | skew(views) = **12.2** (raw snapshot), **14.2** (video level); log(1+views) skew ≈ −0.5 |
| Flags need attention | ✅ | `comments_disabled` TRUE 1.55%, `ratings_disabled` 0.41%, `video_error_or_removed` 0.056% |
| Methods (LASSO/Ridge, RF/GBM, LogReg/SVM), 10-fold CV, RMSE/ROC-AUC | ✅ | matches the proposal's Section III |
| Rubric coverage | ✅ | all 7 rubric items map onto Phases 1–4 |

---

## 2. Gaps and corrections (priority order)

### 2.1 Unit of analysis is under-specified (high priority)
The plan says "Deduplicate records by `video_id` **or** aggregate snapshots" and later
implies n ≈ 40,949. Those are inconsistent: after deduplication the modeling table is
**~6,348 videos**, not 40,949 rows. The plan must (a) state the analysis unit explicitly and
(b) report the reduced n. Recommendation: model at the **video level** (one row per
`video_id`) for the cross-sectional questions, and keep the snapshot table only for
trajectory/growth EDA.

### 2.2 Which snapshot to keep is undefined (high priority)
"Keep one row per video" is ambiguous. Keeping the **first** snapshot models early
performance; keeping the **last** (max `trending_date`) models final cumulative
performance. Pick one and justify. Recommendation: keep the **last** snapshot as the
outcome (final cumulative views), and *never* use early-snapshot metrics as predictors.

### 2.3 Contemporaneous leakage is not addressed (high priority)
The plan only flags *temporal* leakage. It does not forbid using `likes`, `dislikes`, or
`comment_count` as predictors of `views` (or `views` as a predictor of engagement ratios).
In this data those are almost the same signal: corr(log views, log likes) = **0.87**,
corr with log dislikes = **0.87**, corr with log comments = **0.79**. Using them is
textbook leakage. Recommendation: define the predictor set as **upload-time metadata
only** and state the exclusion rule explicitly.

### 2.4 The inference objective is under-served (high priority)
The proposal lists **three** objectives; the third is *inference* — whether creator choices
(publish time, title length, comment settings) have statistically significant effects.
The plan's modeling section is purely predictive. LASSO/Ridge and SVMs do **not** give
interpretable p-values (shrinkage biases coefficients). Recommendation: add a dedicated
inference subsection using OLS / GLM with heteroskedasticity-robust (HC3) standard errors
on the interpretable feature set, reporting standardized coefficients + 95% CIs; use the
regularized/tree models for *predictive* comparison, not for significance claims.

### 2.5 Validation must be grouped (high priority)
Plain 10-fold CV on the raw table leaks across the repeated snapshots of the same video.
Even at the video level, **2,207 channels** recur, so channel identity also cross-contaminates
folds. Recommendation: use **GroupKFold by `video_id`** (snapshot level) / by
`channel_title` (video level), stratified for classification; consider a **temporal holdout**
(train earlier, test later) as a secondary check. Fit all encoders/imputers/scalers on
training folds only.

### 2.6 "Missing data" is mis-framed (medium priority)
There is essentially **no missing data**: only `description` has NaN (570 rows, and we drop
it) plus 8 empty strings. The plan conflates missingness with the structural flags.
Reframe the flags as **rare, near-constant indicators / imbalance**, with a decision to
keep or drop (they may cause quasi-separation in logistic regression).

### 2.7 `tags` sentinel and tag counting (medium priority)
`tags` contains the literal string `[none]` in **1,535** rows → `tag_count` must map these
to **0**, not 1, or the plan will miscount tags for ~4% of rows. The plan's tag step omits
this.

### 2.8 Date-format and timezone gotchas (medium priority)
- `trending_date` is `YY.DD.MM` (e.g. `17.14.11` = 2017-11-14), **not** `YY.MM.DD`. Parsing
  with the intuitive format silently corrupts every date and the `publish_hour`/`dayofweek`
  features. The plan doesn't warn about this.
- `publish_time` is **UTC**, so derived `publish_hour` is UTC, not US-local. This directly
  affects the "best time to publish" conclusions. State it as a caveat (a US timezone
  assumption could be added, but is not recoverable from the file).

### 2.9 Response/predictor coverage vs. proposal (medium priority)
- The proposal lists **`dislikes`** as a response; the plan's log transforms omit
  `log(dislikes)` (skew = **40.2**, the most extreme variable) and any dislike ratio.
- The proposal mentions **"presence of specific keywords"** in `tags`; the plan reduces
  this to `tag_count` only. Either add keyword indicators or explicitly descope.

### 2.10 Outliers / anomalies under-specified (medium priority)
`days_to_trend` (trending − publish) has max **4,215 days (~11.5 years)** and **69** videos
published > 1 year before trending — old catalog videos surfacing late. Views reach
**225M**. The plan says "outliers" generically; it should name these cases and state a
decision (keep with log + robust metrics, or flag/filter), rather than leave it open.

### 2.11 Selection bias / scope limitation (medium priority)
The file contains **only videos that trended**. There are no non-trending negatives, so the
task is "engagement *among trending videos*," not "what causes trending." A random-forest
"predictor of trending" framing would be invalid. This limitation is not in the plan and
should appear in the data-issues section.

### 2.12 Class threshold needs a fixed, unit-consistent definition (low/medium)
Define the "High Engagement" label crisply at the video level and freeze the threshold
(e.g., top-quartile final views ⇒ ≥ **1,473,578** views; 25%/75% split). The proposal allows
"top-quartile views **or** exceptional engagement ratio"; the plan's "top quartile
views/engagement" is ambiguous about whether it is one target or two. Decide, and note the
ratio-based target is likely far more imbalanced than the views-based one.

### 2.13 Provenance / citation (low)
The proposal credits the dataset to **Mitchell Jolly**. The 16-column, 40,949-row,
Nov 2017–Jun 2018 multiregional file is the *"Trending YouTube Video Statistics"* set usually
attributed to **datasnaek**. Verify the correct citation before the final report.

---

## 3. Recommended additions to the EDA (low, but cheap wins)

- A class-balance plot for the target** and a snapshot-multiplicity plot (how many days each video trended).
- `days_to_trend` distribution (reveals the old-catalog anomaly).
- A raw-table vs. video-level comparison, because row-level statistics are **biased toward
  long-trending videos**: snapshot median views = 681,861 vs. video-level median = 516,214.
- Per-channel concentration (top channels dominate the rows).
- A duplicated/NA audit table (the plan asks for counts; show them explicitly).

---

## 4. Bottom line

Keep the plan's structure and method menu. Before writing the report, patch four things:
**(1) fix the unit of analysis and snapshot choice, (2) add explicit leakage controls
(contemporaneous + grouped CV), (3) add an inference subsection, (4) reframe "missing data"
as rare flags/imbalance and handle the `[none]` sentinel.** The remaining items are
polish. All of this is already reflected in the draft report and code I produced.
