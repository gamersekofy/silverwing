# Progress Report 2: reproducible implementation

PPR2 extends the R-transition baseline now merged into master. PPR1 owns data retrieval;
both milestones use one shared preparation module. The historical PPR1 report and its
eight published EDA figures are preserved. PPR2 adds validation and models, not another EDA pipeline.

## Data and scope

- Public source: https://www.kaggle.com/datasets/datasnaek/youtube-new
- Only USvideos.csv and US_category_id.json are extracted; checksums are enforced.
- Cleaning is shared with the merged R port through analysis/data_core.R (base R).
  Counts: 40949 -> 40926 -> 40878 -> 40876 snapshots
  -> 6348 unique videos, across 2198 channels after cleaning.
- Response: natural log(1 + last-observed trending views), not lifetime or fixed-age views.
- Metadata are snapshot-recorded proxies, not certified original upload-time values.
- days_to_trend and every engagement outcome/ratio are excluded from features.

## Implementation

- analysis/download_data.R: the PPR1 downloader and SHA-256 verification.
- analysis/fetch_data.sh: compatibility shim that delegates to that downloader.
- analysis/data_core.R: shared import, ordered cleaning and baseline features.
- analysis/clean_eda.R: PPR1 EDA using that core; --data-only exports its table without plotting.
- analysis/ppr2_data.R: PPR2-only extensions, training-only features and grouped folds.
- analysis/ppr2_models.R: OLS, SVD ridge, pruned rpart trees, 200-tree bagging;
  logistic and tree classification, metrics and channel-clustered covariance.
- analysis/ppr2_run.R: grouped evaluation, inner tuning, checkpoints and time test.
- analysis/ppr2_present.R: figures, formatted tables and linked report numbers.
- analysis/tests/test_ppr2.R: numerical kernels, preprocessing and leakage tests.
- analysis/tests/audit_ppr2_outputs.R: independent checks on the saved results.
- report/progress_report_2.typ: vanilla Typst report with live source-code appendix.

Only base/recommended R and rpart are needed. No packages are installed. MASS is available
but not required: the ridge kernel specifies its own mean-squared-error normalization.
Use R with its recommended rpart package, plus Typst to compile the report.
The exact versions used for this analysis are recorded in the run manifest.

## Commands (run at repository root)

    Rscript --vanilla analysis/download_data.R
    Rscript --vanilla analysis/tests/test_ppr2.R
    Rscript --vanilla analysis/ppr2_run.R
    Rscript --vanilla analysis/tests/audit_ppr2_outputs.R
    Rscript --vanilla analysis/ppr2_present.R
    typst compile --root . report/progress_report_2.typ

The R commands run in an ordinary R installation; no environment manager is required.
Data retrieval uses R HTTPS/unzip support and either digest, sha256sum or shasum for
integrity verification. Typst is needed only for the PDF. To export the PPR1 table
without its optional plotting packages, run Rscript --vanilla analysis/clean_eda.R --data-only;
this is not required before PPR2, which calls the same preparation function directly.

## Validation contract

- Ten outer folds, grouped by anonymized numeric channel ID; seed 20261111.
- No outcome-dependent outer allocation; group sizes balance video counts.
- Five inner grouped folds learn categories/scaling and tune ridge or pruning separately
  for each outcome. One-SE rule chooses the strongest eligible penalty/pruning.
- Ridge: mean squared residual loss + lambda times squared slope norm; intercept free;
  lambda = 10^seq(-4,2,length.out=13), training-only sample-SD standardization.
- Tree: cp in {0,.001,.003,.01,.03,.1}; minbucket 20, minsplit 40, maxdepth 12, xval 0.
- Bagging: 200 ordinary row-bootstrap trees, minbucket 5, minsplit 10, maxdepth 20,
  cp 0; all predictors eligible at every node. This is not random forest. It is fixed,
  not selected using held-out outcomes. OOB error is not used for channel generalization.
- Classification cutoff: 75th percentile of each fit's training views; inner and outer
  validation outcomes are labeled with their respective training cutoff. Probability
  decision threshold fixed at 0.5. Tree tuning uses Brier loss.
- OOF errors are video-weighted; fold SDs are descriptive, not independent-sample CIs.
- Temporal check: train last_trend < 2018-05-01; test first_trend >= 2018-05-01;
  discard spanning videos. Channels may recur in this secondary stress test.
- Full-data association model uses CR1 channel-clustered covariance and t(G-1) intervals;
  unadjusted exploratory p-values, not causal effects or post-selection guarantees.

The report includes uncorrected expm1 back-transforms only as supplementary raw-view
errors; these are not estimated conditional means. Rate models are not clipped and
may predict outside the unit interval. Disabled interactions imply structural zeros.

## Outputs and preservation

analysis/output/ppr2/ contains cleaned metadata, all OOF predictions, fold assignments,
metrics, selected parameters, time splits, cluster estimates, checkpoints and manifests.
It is gitignored. report/ppr2_tables/ and report/figures/ppr2/ contain the generated,
report-ready subset. Do not hand-edit generated numbers to change a reported conclusion.

Fold checkpoints include analysis/data_core.R in their code/data fingerprints and are
reused only when identical. The reconciliation rerun archives the former checkpoints
in report/review/branch-reconcile/before rather than relabeling them as current.
To change modeling code or data, move/remove only this milestone's generated checkpoints
before a new full run; never bypass the signature assertion. Presentation-only edits do
not invalidate predictions. Actual uncommitted project changes must remain separate.

See RECONCILIATION.md for merge provenance, the three Unicode word-count corrections,
parity evidence and the final report checks.
