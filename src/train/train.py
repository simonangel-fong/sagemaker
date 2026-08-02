"""
Training entry point
model: SM_MODEL_DIR
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

DROP = ["instant", "dteday", "casual", "registered", TARGET]
AWS_DEFAULT_REGION = "ca-central-1"

def parse_args():
    p = argparse.ArgumentParser()

    # Hyperparameters arrive as command line flags.
    p.add_argument("--n-estimators", type=int, default=100)
    p.add_argument("--max-depth", type=int, default=None)
    p.add_argument("--min-samples-leaf", type=int, default=5)
    p.add_argument("--random-state", type=int, default=42)

    # Paths come from the environment SageMaker sets up.
    p.add_argument("--train", default=os.environ.get("SM_CHANNEL_TRAIN", "/opt/ml/input/data/train"))
    p.add_argument("--model-dir", default=os.environ.get("SM_MODEL_DIR", "/opt/ml/model"))

    return p.parse_args()


def load(channel_dir):
    """
    Read the training channel, whichever format it arrived in.
    """
    root = Path(channel_dir)

    for pattern, reader in (("*.parquet", pd.read_parquet), ("*.csv", pd.read_csv)):
        files = sorted(root.glob(pattern))
        if files:
            return reader(files[0])

    raise FileNotFoundError(f"no .parquet or .csv found in {channel_dir}")


def main():
    args = parse_args()

    # Load
    df = load(args.train)
    print(f"loaded {len(df)} rows from {args.train}", flush=True)

    assert "hr" in df.columns, f"no hr column in {args.train} -- is this the daily file?"

    features = [c for c in df.columns if c not in DROP]

    # split
    train, test = df[df.yr == 0], df[df.yr == 1]
    print(f"train={len(train)} test={len(test)} features={len(features)}", flush=True)

    # train
    model = RandomForestRegressor(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        min_samples_leaf=args.min_samples_leaf,
        random_state=args.random_state,
        n_jobs=-1,
    )
    model.fit(train[features], train[TARGET])

    # evaluate
    pred = model.predict(test[features])
    rmse = np.sqrt(mean_squared_error(test[TARGET], pred))

    print(f"rmse={rmse:.4f}", flush=True)
    print(f"mae={mean_absolute_error(test[TARGET], pred):.4f}", flush=True)
    print(f"r2={r2_score(test[TARGET], pred):.4f}", flush=True)

    # save 
    out = Path(args.model_dir) / "model.joblib"
    joblib.dump(model, out)

    joblib.dump(features, Path(args.model_dir) / "features.joblib")

    print(f"model written to {out}", flush=True)


if __name__ == "__main__":
    main()
