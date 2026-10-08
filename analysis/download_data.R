#!/usr/bin/env Rscript
# Fetch the Kaggle "Trending YouTube Video Statistics" dataset into ./data.
#
# Source: https://www.kaggle.com/datasets/datasnaek/youtube-new
#
# Downloads the public dataset zip over HTTPS, flattens the *.csv and *.json
# files into `data/`, and verifies the two US SHA-256 sums. Needs no Kaggle
# account; the dataset is public.
#
# Usage:
#   Rscript analysis/download_data.R
#   Rscript analysis/download_data.R --force
#   Rscript analysis/download_data.R --from-zip ~/Downloads/youtube-new.zip
#   Rscript analysis/download_data.R --dest /tmp/data

DATASET <- "datasnaek/youtube-new"
API_URL <- sprintf("https://www.kaggle.com/api/v1/datasets/download/%s", DATASET)

# Files the analysis actually needs, with expected SHA-256 (see data/README.md).
REQUIRED <- c(
  "USvideos.csv"         = "09b4eb71295752705e472ebefeac9d2afab4177b7a818af795dea62744a48eb2",
  "US_category_id.json"  = "2e892c5a5e48d284e40fd37de0313912264041aef8833e5323bd2b2fd08c7e25"
)
KEEP_SUFFIXES <- c(".csv", ".json")

# --- paths -------------------------------------------------------------------
# Resolve the project root from the script location; fall back to the working
# directory when the script was sourced rather than run via Rscript.
script_path <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", args, value = TRUE)
  if (length(hit) > 0) {
    return(normalizePath(sub("^--file=", "", hit[[1]]), mustWork = FALSE))
  }
  normalizePath(".", mustWork = FALSE)
}
ROOT <- dirname(dirname(script_path()))
DEFAULT_DEST <- file.path(ROOT, "data")

# --- argument parsing --------------------------------------------------------
parse_args <- function(argv) {
  opts <- list(dest = DEFAULT_DEST, force = FALSE, from_zip = NULL)
  i <- 1L
  while (i <= length(argv)) {
    a <- argv[[i]]
    if (a == "--force") {
      opts$force <- TRUE
    } else if (a == "--dest") {
      i <- i + 1L; opts$dest <- argv[[i]]
    } else if (a == "--from-zip") {
      i <- i + 1L; opts$from_zip <- argv[[i]]
    } else if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript analysis/download_data.R [--force] [--dest DIR] [--from-zip FILE]\n")
      quit(save = "no", status = 0)
    } else {
      stop(sprintf("unknown argument: %s", a), call. = FALSE)
    }
    i <- i + 1L
  }
  opts
}

# --- helpers -----------------------------------------------------------------
sha256 <- function(path) {
  digest::digest(path, algo = "sha256", file = TRUE)
}

already_present <- function(dest) {
  all(file.exists(file.path(dest, names(REQUIRED))))
}

extract_keep <- function(zip, dest) {
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  members <- utils::unzip(zip, list = TRUE)$Name
  keep <- members[
    !grepl("/$", members) &
      grepl(paste0("\\", KEEP_SUFFIXES, "$", collapse = "|"), members, ignore.case = TRUE)
  ]
  if (length(keep) == 0) {
    return(character(0))
  }
  tmp <- tempfile("youtube-new-")
  dir.create(tmp)
  # junkpaths = TRUE flattens nested directories into a single level.
  utils::unzip(zip, files = keep, exdir = tmp, junkpaths = TRUE)
  copied <- file.copy(list.files(tmp, full.names = TRUE), dest, overwrite = TRUE)
  unlink(tmp, recursive = TRUE)
  basename(keep[copied])
}

verify <- function(dest) {
  cat("Verifying required files:\n")
  ok <- TRUE
  for (name in names(REQUIRED)) {
    path <- file.path(dest, name)
    if (!file.exists(path)) {
      cat(sprintf("  MISSING  %s\n", name)); ok <- FALSE
    } else if (identical(sha256(path), unname(REQUIRED[[name]]))) {
      cat(sprintf("  ok       %s\n", name))
    } else {
      cat(sprintf("  WARN     %s  (sha256 does not match data/README.md)\n", name))
      ok <- FALSE
    }
  }
  ok
}

inventory <- function(dest) {
  files <- list.files(dest, pattern = "\\.(csv|json)$", ignore.case = TRUE, full.names = TRUE)
  if (length(files) == 0) return(invisible())
  files <- sort(files)
  cat(sprintf("\n%d file(s) in %s:\n", length(files), dest))
  for (f in files) {
    cat(sprintf("  %12s  %s\n", format(file.size(f), big.mark = ","), basename(f)))
  }
}

download_http <- function(url, out_path) {
  cat(sprintf("  GET %s\n", url))
  old <- options(HTTPUserAgent = "Mozilla/5.0 (compatible; math448-download/1.0)")
  on.exit(options(old), add = TRUE)
  utils::download.file(url, out_path, mode = "wb", method = "libcurl", quiet = FALSE)
}

# --- main --------------------------------------------------------------------
main <- function() {
  opts <- parse_args(commandArgs(trailingOnly = TRUE))
  dest <- normalizePath(opts$dest, mustWork = FALSE)
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(opts$from_zip)) {
    if (!file.exists(opts$from_zip)) {
      stop(sprintf("error: zip not found: %s", opts$from_zip), call. = FALSE)
    }
    cat(sprintf("Extracting %s -> %s ...\n", opts$from_zip, dest))
    n <- extract_keep(opts$from_zip, dest)
    cat(sprintf("  extracted %d file(s)\n", length(n)))
    verify(dest); inventory(dest)
    return(invisible())
  }

  if (already_present(dest) && !opts$force) {
    cat(sprintf("Data already present in %s (use --force to re-download).\n", dest))
    verify(dest); inventory(dest)
    return(invisible())
  }

  cat("Downloading via HTTPS ...\n")
  tmp <- tempfile("youtube-new-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  zip_path <- file.path(tmp, "youtube-new.zip")
  download_http(API_URL, zip_path)
  cat("Extracting ...\n")
  n <- extract_keep(zip_path, dest)
  cat(sprintf("  extracted %d file(s)\n", length(n)))
  verify(dest); inventory(dest)
}

main()
