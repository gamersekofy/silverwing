"""Print the compact set of numbers cited in Progress Report 1."""
from __future__ import annotations

from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
videos = pd.read_csv(ROOT / "analysis" / "output" / "videos.csv")
raw = pd.read_csv(ROOT / "data" / "USvideos.csv")

pd.set_option("display.width", 160)

print("### video level: n =", len(videos))
print("\n-- engagement ratios --")
print(videos[["like_rate", "comment_rate", "dislike_rate"]].describe(
    percentiles=[.25, .5, .75]).T.to_string())

print("\n-- correlations with log_views (video level) --")
cols = ["title_length", "title_word_count", "tag_count", "publish_hour",
        "days_to_trend", "log_likes", "log_dislikes", "log_comments"]
print(videos[cols].corrwith(videos["log_views"]).round(3).to_string())

print("\n-- title / tag features --")
print(videos[["title_length", "title_word_count", "tag_count"]].describe(
    percentiles=[.25, .5, .75]).T.to_string())
print("tag_count == 0:", int((videos.tag_count == 0).sum()))
print("title_length == 0:", int((videos.title_length == 0).sum()))

print("\n-- days_to_trend --")
print(videos["days_to_trend"].describe().to_string())
print("negative days_to_trend:", int((videos.days_to_trend < 0).sum()))
print("days_to_trend > 365:", int((videos.days_to_trend > 365).sum()))

print("\n-- flags at video level --")
for c in ["comments_disabled", "ratings_disabled"]:
    print(c, "n_true =", int(videos[c].sum()))

print("\n-- zeros at video level --")
for c in ["likes", "dislikes", "comment_count"]:
    print(f"{c} == 0:", int((videos[c] == 0).sum()))

print("\n-- top categories (video level) --")
print(videos["category"].value_counts().head(8).to_string())

print("\n-- raw snapshots --")
print("unique videos in raw:", raw.video_id.nunique())
vc = raw.groupby("video_id").size()
print("mean snapshots/video: %.2f" % vc.mean(), "| max:", int(vc.max()))
print("videos trending >= 2 days: %d (%.1f%%)" % ((vc >= 2).sum(), 100 * (vc >= 2).mean()))

print("\n-- raw views percentiles (snapshot) --")
print(raw["views"].describe(percentiles=[.25, .5, .75, .99]).to_string())
