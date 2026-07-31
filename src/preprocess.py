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
    return p.parse_args()


def main():
    args = parse_args()

    files = sorted(Path(args.input_dir).glob("*.csv"))
    if not files:
        raise FileNotFoundError(f"no .csv found in {args.input_dir}")

    df = pd.read_csv(files[0])
    print(f"loaded {len(df)} rows from {files[0]}", flush=True)

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
