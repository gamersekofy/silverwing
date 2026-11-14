# PPR1/PPR2 reconciliation

## Branch provenance

- master fast-forwarded from 5ad7d91 to 525327c (the R-transition baseline).
- SSH refresh failed; credential-free HTTPS refresh succeeded. master and
  origin/r-transition were confirmed identical after that refresh (0/0 divergence).
- No push was performed. Existing PPR2 files were preserved. The pre-existing
  .gitignore review exclusion and the local decision to use Typst rather than the
  full TeX distribution were retained alongside all incoming R package declarations.
- Original code/results and the two tracked local edits are backed up under
  report/review/branch-reconcile/before. That directory is ignored, not deliverable source.

## One owner for established PPR1 work

- analysis/download_data.R remains the sole downloader/checksum implementation.
  fetch_data.sh is only a compatibility shim. Verification now fails on a bad digest;
  digest is optional when the platform supplies sha256sum or shasum.
- analysis/data_core.R is shared by clean_eda.R and ppr2_data.R. It centralizes import,
  ordered cleaning, last-snapshot collapse, baseline features and category lookup.
- PPR1 profiling/report-number scripts reuse that importer as well.
- PPR2 adds only its temporal/group identifiers, cyclical hour representation,
  training-only feature transformations, validation, models and result presentation.
  It does not regenerate the eight PPR1 EDA plots or reuse PPR1's full-data high-view
  label as a cross-validation target. days_to_trend remains excluded from predictors.
- The historical PPR1 source/PDF and its published figures are not rewritten.

## Baseline and regression evidence

- Shared preparation yields the unchanged chain 40949 -> 40926 -> 40878 -> 40876
  -> 6348 videos, with 2198 cleaned channels.
- An independent standard-library Python audit, transcribing the original PPR1
  semantics rather than calling the R helper, matches all 6348 videos across 25 fields.
  Audit code/output are in report/review/branch-reconcile/independent_parity.py and
  independent-parity.log; this is a development check, not a Python runtime dependency.
- Comparing all 19 PPR2 modeling-input columns with the previous run found exactly
  three changed cells, all title word counts affected by Unicode whitespace. Outcomes,
  video membership/order and every other modeling input are unchanged.
- Unit tests cover shared PPR1/PPR2 field identity, Unicode words, grouped folds,
  training-only features, ridge equations, tied ROC/AP, deterministic bagging, one-SE
  selection and clustered covariance. They passed before the fresh refit.
- The former ten checkpoints were archived, not given new signatures. New checkpoints
  fingerprint data_core.R as well as modeling sources and raw data. The fingerprint
  assertion was checked against a newly fitted checkpoint.
- Positive and negative integrity checks passed: existing public files verify, and
  the downloader rejects deliberately invalid local fixtures without downloading.

## Figures and report

- The clipping fix is limited to axis placement: the shared SVG helper explicitly
  sets mgp = c(2.2, .7, 0), moving titles inward without shrinking figures or type.
- Report prose now reads rerun-derived comparisons, recalls, rate R2 and selected
  coefficient intervals from ppr2_numbers.typ rather than repeating literal numbers.
- The report describes shared preparation and lists it in the code appendix. The
  PPR1 downloader is reused and supplied in the source bundle rather than duplicated.
- Reproducibility instructions remain ordinary Rscript/Typst commands, with no Nix
  instructions in the report. PPR1's optional plotting dependencies are not needed for
  the --data-only baseline export or for PPR2.
- The recorded cached project environment was used for execution, without installing
  packages or replacing the merged default PPR1 plotting environment. The full
  dependency-heavy PPR1 plotting path was not rerun; its published figures are retained.

Fresh-fit results, independent output audit and final rendering checks are recorded in
VERIFICATION.md when complete. Official assignment-rubric/sample conformance is not
claimed; those external references were not available during the earlier review.
