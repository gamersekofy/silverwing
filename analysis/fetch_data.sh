#!/usr/bin/env bash
# Compatibility entry point; PPR1 owns download and integrity verification.
set -euo pipefail
cd "$(dirname "$0")/.."
exec Rscript --vanilla analysis/download_data.R "$@"
