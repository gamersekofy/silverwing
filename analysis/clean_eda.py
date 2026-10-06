"""Phase 1-2: cleaning, feature engineering, and EDA for the US YouTube trending data.

Produces:
  analysis/output/videos.csv            video-level (deduplicated) analysis table
  analysis/output/summary_*.csv         numeric summaries used in the report
  report/figures/fig*.png               report figures

Run:  python analysis/clean_eda.py
"""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
OUT = ROOT / "analysis" / "output"
FIGS = ROOT / "report" / "figures"
OUT.mkdir(parents=True, exist_ok=True)
FIGS.mkdir(parents=True, exist_ok=True)

sns.set_theme(style="whitegrid", context="talk")
plt.rcParams.update({"figure.dpi": 140, "savefig.bbox": "tight", "font.size": 12})

LOG = "\n[clean_eda] "
step_log: list[str] = []


def log(msg: str) -> None:
    print(LOG + msg)
    step_log.append(msg)


def savefig(fig, name: str) -> None:
    path = FIGS / f"{name}.png"
    fig.savefig(path)
    plt.close(fig)
    log(f"wrote figure {path.relative_to(ROOT)}")


def main() -> None:
    raw = pd.read_csv(DATA / "USvideos.csv")
    n0 = len(raw)
    log(f"raw rows = {n0}, columns = {raw.shape[1]}")

    # ---- parse dates -----------------------------------------------------
    # trending_date uses an unusual YY.DD.MM format (17.14.11 -> 2017-11-14).
    raw["trending_date_parsed"] = pd.to_datetime(raw["trending_date"], format="%y.%d.%m")
    raw["publish_time_parsed"] = pd.to_datetime(raw["publish_time"], utc=True)
    log(f"trending range {raw.trending_date_parsed.min().date()} .. {raw.trending_date_parsed.max().date()}")
    log(f"publish  range {raw.publish_time_parsed.min()} .. {raw.publish_time_parsed.max()}")

    # ---- cleaning steps with counts --------------------------------------
    clean = raw.copy()
    counts = {"raw": n0}

    n_removed_flag = int((clean["video_error_or_removed"]).sum())
    clean = clean[~clean["video_error_or_removed"]].copy()
    counts["drop_error_or_removed"] = len(clean)
    log(f"drop video_error_or_removed: -{n0 - len(clean)} rows (flagged={n_removed_flag})")

    before = len(clean)
    clean = clean.drop_duplicates()
    counts["drop_full_dup"] = len(clean)
    log(f"drop fully duplicated rows: -{before - len(clean)} rows")

    before = len(clean)
    clean = clean.drop_duplicates(subset=["video_id", "trending_date_parsed"], keep="last")
    counts["drop_dup_snapshot"] = len(clean)
    log(f"drop duplicate (video_id, trending_date) snapshots: -{before - len(clean)} rows")

    # ---- feature engineering --------------------------------------------
    clean["publish_hour"] = clean["publish_time_parsed"].dt.hour
    clean["publish_dayofweek"] = clean["publish_time_parsed"].dt.dayofweek  # 0=Mon
    clean["publish_date"] = clean["publish_time_parsed"].dt.tz_localize(None).dt.normalize()
    clean["days_to_trend"] = (clean["trending_date_parsed"] - clean["publish_date"]).dt.days

    clean["title_length"] = clean["title"].str.len()
    clean["title_word_count"] = clean["title"].str.split().str.len()
    # tags is a '|'-separated list; '[none]' means no tags.
    tags_clean = clean["tags"].fillna("").str.strip()
    clean["tag_count"] = np.where(tags_clean == "[none]", 0, tags_clean.str.count(r"\|") + 1)
    clean.loc[tags_clean == "", "tag_count"] = 0

    with open(DATA / "US_category_id.json", encoding="utf-8") as fh:
        cats = json.load(fh)
    id2name = {int(i["id"]): i["snippet"]["title"] for i in cats["items"]}
    clean["category"] = clean["category_id"].map(id2name)

    clean["log_views"] = np.log1p(clean["views"])
    clean["log_likes"] = np.log1p(clean["likes"])
    clean["log_dislikes"] = np.log1p(clean["dislikes"])
    clean["log_comments"] = np.log1p(clean["comment_count"])
    clean["like_rate"] = clean["likes"] / clean["views"]
    clean["comment_rate"] = clean["comment_count"] / clean["views"]
    clean["dislike_rate"] = clean["dislikes"] / clean["views"]

    log(f"snapshot-level table after cleaning: {len(clean)} rows")

    # ---- deduplicate to one row per video (final cumulative snapshot) ----
    idx_last = clean.sort_values("trending_date_parsed").groupby("video_id").tail(1).index
    videos = clean.loc[idx_last].copy()
    counts["video_level"] = len(videos)
    log(f"video-level table (last trending snapshot per video): {len(videos)} videos")

    # classification target: top-quartile final views
    q75 = videos["views"].quantile(0.75)
    videos["high_views"] = (videos["views"] >= q75).astype(int)
    log(f"top-quartile views threshold = {q75:,.0f}; positives = {videos.high_views.mean():.1%}")

    videos.to_csv(OUT / "videos.csv", index=False)

    # persistence/summary tables ------------------------------------------
    pd.DataFrame(
        [{"step": k, "rows": v} for k, v in counts.items()]
    ).to_csv(OUT / "summary_cleaning_counts.csv", index=False)

    num = ["views", "likes", "dislikes", "comment_count"]
    videos[num].describe(percentiles=[.25, .5, .75, .9, .99]).T.join(
        videos[num].skew().rename("skew")
    ).to_csv(OUT / "summary_numeric.csv")

    videos.groupby("category")["log_views"].agg(["count", "mean", "median", "std"]).sort_values(
        "median", ascending=False
    ).to_csv(OUT / "summary_by_category.csv")

    videos.groupby("publish_hour")["log_views"].mean().to_csv(OUT / "summary_by_hour.csv")
    videos.groupby("publish_dayofweek")["log_views"].mean().to_csv(OUT / "summary_by_dow.csv")

    # ---- figures ---------------------------------------------------------
    # Fig 1: raw vs log views
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    sns.histplot(videos["views"], bins=60, ax=axes[0], color="#c44e52")
    axes[0].set_title(f"Raw views (skew = {videos.views.skew():.1f})")
    axes[0].set_xlabel("views")
    sns.histplot(videos["log_views"], bins=60, ax=axes[1], color="#4c72b0")
    axes[1].set_title(f"log(1 + views) (skew = {videos.log_views.skew():.2f})")
    axes[1].set_xlabel("log(1 + views)")
    savefig(fig, "fig01_views_transform")

    # Fig 2: log views by category
    order = videos.groupby("category")["log_views"].median().sort_values(ascending=False).index
    fig, ax = plt.subplots(figsize=(12, 7))
    sns.boxplot(data=videos, y="category", x="log_views", order=order, ax=ax,
                color="#4c72b0", fliersize=2)
    ax.set_title("log(1 + views) by category (video level)")
    ax.set_xlabel("log(1 + views)")
    ax.set_ylabel("")
    savefig(fig, "fig02_logviews_by_category")

    # Fig 3: engagement rates by category
    eng = videos.melt(id_vars="category", value_vars=["like_rate", "comment_rate"],
                      var_name="metric", value_name="rate")
    order2 = videos.groupby("category")["like_rate"].median().sort_values(ascending=False).index
    fig, ax = plt.subplots(figsize=(12, 7))
    sns.boxplot(data=eng, y="category", x="rate", hue="metric", order=order2, ax=ax, fliersize=2)
    ax.set_xlim(0, 0.15)
    ax.set_title("Engagement ratios by category")
    ax.set_xlabel("ratio")
    ax.set_ylabel("")
    savefig(fig, "fig03_engagement_by_category")

    # Fig 4: flags vs log views
    flags = videos.melt(id_vars=["log_views"],
                        value_vars=["comments_disabled", "ratings_disabled"],
                        var_name="flag", value_name="value")
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    for ax, flag in zip(axes, ["comments_disabled", "ratings_disabled"]):
        sub = videos[videos[flag]]
        sns.boxplot(data=videos, x=flag, y="log_views", ax=ax, color="#55a868",
                    fliersize=2)
        ax.set_title(f"{flag}\n(TRUE n={len(sub)})")
        ax.set_xlabel(flag)
        ax.set_ylabel("log(1 + views)")
    savefig(fig, "fig04_flags_vs_views")

    # Fig 5: publish hour & day of week
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    hourly = videos.groupby("publish_hour")["log_views"].mean()
    sns.lineplot(x=hourly.index, y=hourly.values, marker="o", ax=axes[0], color="#c44e52")
    axes[0].set_title("Mean log(1 + views) by publish hour (UTC)")
    axes[0].set_xlabel("publish hour (UTC)")
    axes[0].set_ylabel("mean log(1 + views)")
    dow = videos.groupby("publish_dayofweek")["log_views"].mean()
    names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    sns.barplot(x=names, y=dow.values, ax=axes[1], color="#8172b3")
    axes[1].set_title("Mean log(1 + views) by publish day")
    axes[1].set_xlabel("")
    axes[1].set_ylabel("mean log(1 + views)")
    savefig(fig, "fig05_time_effects")

    # Fig 6: title length & tag count
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    sns.regplot(data=videos, x="title_length", y="log_views", ax=axes[0],
                scatter_kws={"s": 6, "alpha": 0.25}, line_kws={"color": "red"})
    axes[0].set_title(f"log(1 + views) vs title length (r={videos.title_length.corr(videos.log_views):.2f})")
    axes[0].set_xlabel("title length (characters)")
    axes[0].set_ylabel("log(1 + views)")
    sns.regplot(data=videos, x="tag_count", y="log_views", ax=axes[1],
                scatter_kws={"s": 6, "alpha": 0.25}, line_kws={"color": "red"})
    axes[1].set_title(f"log(1 + views) vs tag count (r={videos.tag_count.corr(videos.log_views):.2f})")
    axes[1].set_xlabel("tag count")
    axes[1].set_ylabel("log(1 + views)")
    savefig(fig, "fig06_text_metrics")

    # Fig 7: correlation heatmap
    corr_cols = ["log_views", "log_likes", "log_dislikes", "log_comments",
                 "like_rate", "comment_rate", "dislike_rate", "title_length",
                 "title_word_count", "tag_count", "publish_hour", "days_to_trend"]
    fig, ax = plt.subplots(figsize=(11, 9))
    sns.heatmap(videos[corr_cols].corr(), annot=True, fmt=".2f", cmap="coolwarm",
                center=0, square=True, ax=ax, cbar_kws={"shrink": 0.7}, annot_kws={"size": 9})
    ax.set_title("Correlation matrix (video level)")
    savefig(fig, "fig07_correlation")

    # Fig 8: class balance + snapshot multiplicity
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    videos["high_views"].value_counts().sort_index().plot.bar(ax=axes[0], color="#4c72b0")
    axes[0].set_title("Classification target: top-quartile views")
    axes[0].set_xticklabels(["Not top quartile (0)", "Top quartile (1)"], rotation=0)
    axes[0].set_ylabel("videos")
    mult = raw.groupby("video_id").size().value_counts().sort_index()
    axes[1].bar(mult.index, mult.values, color="#c44e52")
    axes[1].set_title("Trending snapshots per video (raw data)")
    axes[1].set_xlabel("number of daily snapshots")
    axes[1].set_ylabel("videos")
    savefig(fig, "fig08_class_and_multiplicity")

    # write a human-readable cleaning log
    (OUT / "cleaning_log.txt").write_text("\n".join(step_log), encoding="utf-8")
    log("done")


if __name__ == "__main__":
    main()
