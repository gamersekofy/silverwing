"""Profile the Kaggle YouTube Trending (US) dataset.

Run:  python analysis/profile_data.py
All output goes to stdout so it can be captured into the report's data section.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

pd.set_option("display.width", 160)
pd.set_option("display.max_columns", 50)

DATA = Path(__file__).resolve().parents[1] / "data"
CSV = DATA / "USvideos.csv"
CATS = DATA / "US_category_id.json"


def banner(title: str) -> None:
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


def main() -> None:
    df = pd.read_csv(CSV)

    banner("1. DIMENSIONS & COLUMNS")
    print("shape (rows, cols):", df.shape)
    print("columns:", list(df.columns))

    banner("2. DTYPES")
    print(df.dtypes.to_string())

    banner("3. DATE RANGES (trending_date = YY.DD.MM)")
    td = pd.to_datetime(df["trending_date"], format="%y.%d.%m", errors="coerce")
    pt = pd.to_datetime(df["publish_time"], errors="coerce", utc=True)
    print("trending_date  min/max:", td.min().date(), td.max().date(), "| unparsed:", int(td.isna().sum()))
    print("publish_time   min/max:", pt.min(), pt.max(), "| unparsed:", int(pt.isna().sum()))
    print("distinct trending dates:", int(td.nunique()))
    print("all trending_date match ^\\d{2}\\.\\d{2}\\.\\d{2}$:",
          bool(df["trending_date"].astype(str).str.match(r"^\d{2}\.\d{2}\.\d{2}$").all()))

    banner("4. MISSING / SENTINELS")
    print("NaN per column:\n", df.isna().sum().to_string())
    tags = df["tags"].astype(str).str.strip()
    print("\ntags == '[none]':", int((tags == "[none]").sum()))
    print("tags == '[None]':", int((tags == "[None]").sum()))
    print("tags empty string:", int((tags == "").sum()))
    obj = df.select_dtypes(include="object").columns
    empt = df[obj].apply(lambda s: s.astype(str).str.strip() == "").sum()
    print("\nempty-string counts (object cols):\n", empt.to_string())

    banner("5. DUPLICATES & REPEATED SNAPSHOTS")
    print("fully duplicated rows:", int(df.duplicated().sum()))
    print("duplicated video_id :", int(df["video_id"].duplicated().sum()))
    print("unique video_id     :", int(df["video_id"].nunique()))
    vc = df["video_id"].value_counts()
    print("max appearances of one video_id:", int(vc.max()))
    print("\ndistribution of #appearances:\n", vc.value_counts().sort_index().to_string())
    print("\ntop 5 most-trending video_ids:\n", vc.head().to_string())
    # duplicate (video_id, trending_date) pairs -> true duplicate snapshots
    dup_pairs = df.duplicated(subset=["video_id", "trending_date"]).sum()
    print("\nduplicated (video_id, trending_date) pairs:", int(dup_pairs))

    banner("6. NUMERIC SUMMARY + SKEW")
    num = ["views", "likes", "dislikes", "comment_count"]
    desc = df[num].describe(percentiles=[0.25, 0.5, 0.75, 0.9, 0.99]).T
    print(desc.to_string())
    print("\nskewness:\n", df[num].skew().to_string())
    print("\nkurtosis:\n", df[num].kurt().to_string())

    banner("7. BOOLEAN FLAGS")
    for c in ["comments_disabled", "ratings_disabled", "video_error_or_removed"]:
        print(f"\n{c}:")
        print(df[c].value_counts(dropna=False).to_string())
        print((df[c].value_counts(normalize=True, dropna=False) * 100).round(3).to_string(), "%")

    banner("8. CATEGORY DISTRIBUTION (id -> name)")
    with open(CATS, encoding="utf-8") as fh:
        cats = json.load(fh)
    id2name = {int(i["id"]): i["snippet"]["title"] for i in cats["items"]}
    print("category_id value_counts:\n", df["category_id"].value_counts().sort_index().to_string())
    print("\nnum distinct categories in data:", int(df["category_id"].nunique()))
    print("\ncategories appearing in data (name):")
    print(df["category_id"].map(id2name).value_counts().to_string())

    banner("9. LOGICAL INCONSISTENCIES")
    print("views == 0            :", int((df["views"] == 0).sum()))
    print("likes == 0            :", int((df["likes"] == 0).sum()))
    print("comment_count == 0    :", int((df["comment_count"] == 0).sum()))
    print("likes > views         :", int((df["likes"] > df["views"]).sum()))
    print("dislikes > views      :", int((df["dislikes"] > df["views"]).sum()))
    print("comment_count > views :", int((df["comment_count"] > df["views"]).sum()))
    print("likes+dislikes > views:", int(((df["likes"] + df["dislikes"]) > df["views"]).sum()))
    # comments disabled but comments recorded
    cd_true = df["comments_disabled"].astype(str).str.lower() == "true"
    print("comments_disabled=True AND comment_count>0:",
          int((cd_true & (df["comment_count"] > 0)).sum()))

    banner("10. CHANNELS & ENGAGEMENT RATIOS")
    print("distinct channel_title:", int(df["channel_title"].nunique()))
    print("top 10 channels by #trending rows:\n", df["channel_title"].value_counts().head(10).to_string())
    eng = pd.DataFrame({
        "like_rate": df["likes"] / df["views"].replace(0, np.nan),
        "comment_rate": df["comment_count"] / df["views"].replace(0, np.nan),
    })
    print("\nengagement-ratio summary:")
    print(eng.describe(percentiles=[0.25, 0.5, 0.75, 0.9]).T.to_string())
    print("\nlike_rate > 1 (should be rare/impossible):", int((eng["like_rate"] > 1).sum()))
    print("comment_rate > 1:", int((eng["comment_rate"] > 1).sum()))

    banner("11. PER-VIDEO DEDUP PREVIEW (last snapshot per video)")
    last_idx = df.groupby("video_id")["trending_date"].transform("max") == df["trending_date"]
    dedup = df[last_idx]
    print("rows after keeping last snapshot per video_id:", len(dedup))
    print("unique videos:", int(dedup["video_id"].nunique()))
    print("views summary (dedup):\n", dedup["views"].describe(percentiles=[.25, .5, .75, .9, .99]).to_string())


if __name__ == "__main__":
    main()
