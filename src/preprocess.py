"""Preprocess step: raw/hour.csv -> the featured frame.

Same framing phase 4 did in the notebook, moved onto a processing job so
the pipeline does not depend on a running kernel. SageMaker mounts the
input channel and uploads whatever lands in the output directory; nothing
here talks to S3 directly.
"""

import argparse
from pathlib import Path

import pandas as pd

TARGET = "cnt"

# casual + registered sum to cnt in every row, so they leak the target.
# instant is a row index; dteday is superseded by the calendar columns.
DROP = ["instant", "dteday", "casual", "registered", TARGET]


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input-dir", default="/opt/ml/processing/input")
    p.add_argument("--output-dir", default="/opt/ml/processing/output")
    # raw/ holds day.csv as well. Globbing *.csv and taking the first
    # match silently picked the daily file -- 731 rows, no hr column, a
    # target an order of magnitude larger -- and the run went green with
    # an rmse of 2250.
    p.add_argument("--input-file", default="hour.csv")
    return p.parse_args()


def main():
    args = parse_args()

    source = Path(args.input_dir) / args.input_file
    if not source.exists():
        available = sorted(p.name for p in Path(args.input_dir).glob("*.csv"))
        raise FileNotFoundError(f"{args.input_file} not in {args.input_dir}; found {available}")

    df = pd.read_csv(source)
    print(f"loaded {len(df)} rows from {source}", flush=True)

    # The hourly file is the one this pipeline is built around. Guard the
    # shape rather than trusting the filename alone.
    assert "hr" in df.columns, f"{args.input_file} has no hr column -- is this the daily file?"

    # The leak is the whole reason DROP exists -- assert it rather than
    # trusting the column list to stay correct.
    leak = (df.casual + df.registered != df[TARGET]).sum()
    assert leak == 0, f"{leak} rows where casual + registered != cnt"

    features = [c for c in df.columns if c not in DROP]

    # yr is already in features and doubles as the split key, so the
    # frame is just the features plus the target.
    featured = df[features + [TARGET]]

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Parquet, matching what phase 4 wrote to featured/ -- the eval
    # notebooks read that path and must keep working.
    out = out_dir / "hour.parquet"
    featured.to_parquet(out, index=False)

    print(f"{featured.shape[0]} rows x {featured.shape[1]} cols", flush=True)
    print(f"{len(features)} features: {features}", flush=True)
    print(f"written to {out}", flush=True)


if __name__ == "__main__":
    main()
