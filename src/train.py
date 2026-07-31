"""Bike sharing demand training entry point for a SageMaker training job.

SageMaker mounts the S3 channel locally and expects the model written to
SM_MODEL_DIR; it tars that directory and uploads it. Nothing here talks to S3
directly.
"""

import argparse
import os
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

TARGET = "cnt"

# casual + registered sum to cnt in every row, so they leak the target.
# instant is a row index; dteday is superseded by the calendar columns.
DROP = ["instant", "dteday", "casual", "registered", TARGET]


def parse_args():
    p = argparse.ArgumentParser()

    # Hyperparameters arrive as command line flags.
    p.add_argument("--n-estimators", type=int, default=100)
    p.add_argument("--max-depth", type=int, default=None)
    # Fully grown trees memorize: 1M nodes, 70 MB. Capping the leaf size costs
    # ~0.7% r2 and cuts the artifact to 12 MB, which matters on a serverless
    # endpoint that reloads the model on every cold start.
    p.add_argument("--min-samples-leaf", type=int, default=5)
    p.add_argument("--random-state", type=int, default=42)

    # Paths come from the environment SageMaker sets up.
    p.add_argument("--train", default=os.environ.get("SM_CHANNEL_TRAIN", "/opt/ml/input/data/train"))
    p.add_argument("--model-dir", default=os.environ.get("SM_MODEL_DIR", "/opt/ml/model"))

    return p.parse_args()


def load(channel_dir):
    """Read the training channel, whichever format it arrived in.

    submit_job.py points this at raw/ and gets CSV. The phase 7 pipeline
    feeds it the preprocess step's parquet output. Both callers stay
    working rather than one format being hardcoded.
    """
    root = Path(channel_dir)

    for pattern, reader in (("*.parquet", pd.read_parquet), ("*.csv", pd.read_csv)):
        files = sorted(root.glob(pattern))
        if files:
            return reader(files[0])

    raise FileNotFoundError(f"no .parquet or .csv found in {channel_dir}")


def main():
    args = parse_args()

    df = load(args.train)
    print(f"loaded {len(df)} rows from {args.train}", flush=True)

    features = [c for c in df.columns if c not in DROP]

    # Split by time: train on 2011, test on 2012. A random split would let the
    # model see hours adjacent to the ones it is scored on.
    train, test = df[df.yr == 0], df[df.yr == 1]
    print(f"train={len(train)} test={len(test)} features={len(features)}", flush=True)

    model = RandomForestRegressor(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        min_samples_leaf=args.min_samples_leaf,
        random_state=args.random_state,
        n_jobs=-1,
    )
    model.fit(train[features], train[TARGET])

    pred = model.predict(test[features])
    rmse = np.sqrt(mean_squared_error(test[TARGET], pred))

    # Printed in this format so the metrics can be scraped by a
    # metric_definitions regex if this job is ever used for tuning.
    print(f"rmse={rmse:.4f}", flush=True)
    print(f"mae={mean_absolute_error(test[TARGET], pred):.4f}", flush=True)
    print(f"r2={r2_score(test[TARGET], pred):.4f}", flush=True)

    out = Path(args.model_dir) / "model.joblib"
    joblib.dump(model, out)

    # Saved alongside the model so inference reconstructs the column order.
    joblib.dump(features, Path(args.model_dir) / "features.joblib")

    print(f"model written to {out}", flush=True)


if __name__ == "__main__":
    main()
