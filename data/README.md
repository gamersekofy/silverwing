# Data

Raw input for this project is the Kaggle **"Trending YouTube Video Statistics"**
dataset: daily snapshots of the videos that appeared on YouTube's Trending tab, for
several regions, plus a per-region category-id lookup.

The large raw files are **not tracked in git** (see `.gitignore`). This README records
what to download and how to verify it, so the project stays reproducible without
committing ~515 MB of third-party data.

## Files used by the analysis

| File | Bytes | SHA-256 |
|---|---:|---|
| `USvideos.csv` | 62,756,152 | `09b4eb71295752705e472ebefeac9d2afab4177b7a818af795dea62744a48eb2` |
| `US_category_id.json` | 8,496 | `2e892c5a5e48d284e40fd37de0313912264041aef8833e5323bd2b2fd08c7e25` |

Only the **US** files are read by the current code (`analysis/*.R`). The other regions
are present locally and may be used for a later multi-region extension.

## Full local inventory

| File | Bytes | | File | Bytes |
|---|---:|---|---|---:|
| `CAvideos.csv` | 64,067,991 | | `CA_category_id.json` | 7,911 |
| `DEvideos.csv` | 63,040,138 | | `DE_category_id.json` | 7,911 |
| `FRvideos.csv` | 51,424,708 | | `FR_category_id.json` | 7,911 |
| `GBvideos.csv` | 53,213,441 | | `GB_category_id.json` | 8,225 |
| `INvideos.csv` | 59,600,439 | | `IN_category_id.json` | 8,225 |
| `JPvideos.csv` | 28,740,747 | | `JP_category_id.json` | 8,225 |
| `KRvideos.csv` | 34,835,868 | | `KR_category_id.json` | 8,225 |
| `MXvideos.csv` | 45,191,541 | | `MX_category_id.json` | 8,225 |
| `RUvideos.csv` | 76,268,286 | | `RU_category_id.json` | 8,225 |
| `USvideos.csv` | 62,756,152 | | `US_category_id.json` | 8,496 |

Total: ~515 MiB.

## How to obtain

Preferred: run the fetcher, which downloads and unpacks everything into this folder and
verifies the checksums:

```sh
Rscript analysis/download_data.R            # fetch if missing
Rscript analysis/download_data.R --force    # re-download
Rscript analysis/download_data.R --from-zip ~/Downloads/youtube-new.zip
```

It needs network access but no Kaggle account (the dataset is public); if you do have a
Kaggle account it will use `KAGGLE_USERNAME` / `KAGGLE_KEY` or `~/.kaggle/kaggle.json`.

Equivalent manual alternatives: `kagglehub.dataset_download("datasnaek/youtube-new")`, or
`curl -L -o youtube-new.zip https://www.kaggle.com/api/v1/datasets/download/datasnaek/youtube-new`
followed by unzipping the `*videos.csv` / `*_category_id.json` files flat into `data/`.

> **Citation check:** the project proposal credits the dataset to "Mitchell Jolly", but
> the 16-column / 40,949-row / Nov 2017–Jun 2018 regional release matches the
> `datasnaek/youtube-new` listing. Confirm the exact attribution before the final report.

## Verify integrity

```sh
sha256sum data/USvideos.csv data/US_category_id.json
```

Expected digests are in the table above. If a digest does not match, re-download.

## Notes for anyone running the code

- `trending_date` uses the format `YY.DD.MM` (e.g. `17.14.11` = 2017-11-14) — **not**
  `YY.MM.DD`.
- `publish_time` is UTC.
- In `tags`, the literal string `[none]` means "no tags" (count as 0).
