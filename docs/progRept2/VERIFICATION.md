# PPR2 verification after branch reconciliation

## Execution and baseline

- master includes the current origin/r-transition tip 525327c; HTTPS refresh confirmed
  zero divergence. No push was performed. The working cleanup changes are not committed.
- Both public US files pass SHA-256 verification. A negative test confirms that corrupt
  local files fail rather than silently passing or triggering a download.
- Shared preparation passes the unchanged row chain 40949 -> 40926 -> 40878 -> 40876
  -> 6348, with 2198 cleaned channels. An independent implementation matches every
  video across 25 PPR1 fields, including UTC dates, Unicode words, rates and EDA labels.
- Exactly three earlier PPR2 title word counts were corrected for Unicode whitespace;
  no outcomes, video membership/order, or other modeling inputs changed.
- The PPR1 --data-only export ran successfully without plotting packages. The original
  PPR1 source/PDF pass preservation hashes; the eight published EDA figures are retained.
- Deterministic unit/data tests passed: PPR1/PPR2 shared-field identity, Unicode words,
  grouped folds, training-only features, ridge equations, tied ROC/AP, bagging, one-SE
  selection and channel-clustered covariance.

## Fresh model execution

- All ten outer folds were fitted afresh, followed by the separate temporal stress fit.
  Former checkpoints were archived; signatures were not bypassed or relabeled.
- New checkpoint fingerprints include data_core.R, fitting sources and raw data.
- Independent saved-output audits passed: OOF coverage, response identities, grouped
  fold membership, residual-moment errors, ROC area, training-only class cutoffs,
  confusion totals and temporal membership.
- Main log-view RMSE: Mean 1.855000; OLS 1.770704; Ridge 1.785772;
  pruned tree 1.785929; bagging 1.801305. OLS R2 is 0.086587.
- Primary classification AUC remains the mean fold AUC, 0.673 for logistic regression;
  pooled ROC AUC is a different summary. Logistic recall at 0.5 remains 0.055.
- Temporal R2 remains negative for every method. Core conclusions are unchanged.
- The coefficient/interval prose is now generated from the rerun, including the updated
  title-character association (-0.177, 95% CI [-0.337, -0.018]).
- Exact R/package versions and source/data fingerprints are in run_manifest.txt.

## Figures and document

- Regenerated all five SVG figures from the fresh results.
- Inspected all five within their own rendered viewports at 1800-pixel page scale.
  Both log-label descenders in the performance figure are now complete; other labels,
  titles and axes are unclipped. Figure dimensions are unchanged.
- The margin fix explicitly sets mgp = c(2.2, .7, 0) in the shared plotting helper.
- Report comparisons, recalls, rate R2 and selected coefficient intervals are linked
  to generated values rather than stale literal numbers. The appendix includes the
  shared preparation module and refers to the reused PPR1 downloader in the source bundle.
- R source width gate (96 characters for listed PPR2 sources) and git diff --check passed.

## Remaining artifact step / limits

- The personalized report was rebuilt with the cover block preserved and its full
  pagination inspected page by page: **22 pages, US Letter (612 x 792 pt), clean compile,
  no warnings**. No clipped text, no code or table overrunning a margin, and the page-5
  figure axis labels are complete including descenders. The appendix (pp. 13-22) renders
  without overrun; the final page carries the last four lines of the audit block and is
  otherwise blank.
- Final archive checked: CRC-tested clean, and its extracted sources compile to the same
  22 pages with extracted text identical to the delivered PDF. Report instructions remain
  plain Rscript and Typst.
- The full dependency-heavy PPR1 plotting path was not rerun; its existing report and
  figures are preserved. Numerical preparation and PPR2 were executed in the recorded,
  cached project environment without installing packages.
- Official rubric/sample conformance is not claimed: those external references were
  unavailable during the prior review.
