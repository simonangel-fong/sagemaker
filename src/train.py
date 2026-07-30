"""MNIST training entry point for a SageMaker training job.

SageMaker mounts the S3 channel locally and expects the model written to
SM_MODEL_DIR; it tars that directory and uploads it. Nothing here talks to S3
directly.
"""

import argparse
import os
from pathlib import Path

import joblib
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split


def parse_args():
    p = argparse.ArgumentParser()

    # Hyperparameters arrive as command line flags.
    p.add_argument("--max-iter", type=int, default=1000)
    p.add_argument("--n-samples", type=int, default=10_000)
    p.add_argument("--test-size", type=float, default=0.2)
    p.add_argument("--random-state", type=int, default=42)

    # Paths come from the environment SageMaker sets up.
    p.add_argument("--train", default=os.environ.get("SM_CHANNEL_TRAIN", "/opt/ml/input/data/train"))
    p.add_argument("--model-dir", default=os.environ.get("SM_MODEL_DIR", "/opt/ml/model"))

    return p.parse_args()


def load(channel_dir):
    files = sorted(Path(channel_dir).glob("*.npz"))
    if not files:
        raise FileNotFoundError(f"no .npz found in {channel_dir}")

    with np.load(files[0]) as data:
        return data["X"], data["y"]


def main():
    args = parse_args()

    X, y = load(args.train)
    print(f"loaded {X.shape[0]} rows from {args.train}", flush=True)

    n = min(args.n_samples, X.shape[0])
    X_train, X_test, y_train, y_test = train_test_split(
        X[:n],
        y[:n],
        test_size=args.test_size,
        random_state=args.random_state,
        stratify=y[:n],
    )

    clf = LogisticRegression(max_iter=args.max_iter)
    clf.fit(X_train, y_train)

    acc = accuracy_score(y_test, clf.predict(X_test))

    # Printed in this format so the metric can be scraped by a metric_definitions
    # regex if this job is ever used for tuning.
    print(f"test_accuracy={acc:.4f}", flush=True)

    out = Path(args.model_dir) / "model.joblib"
    joblib.dump(clf, out)
    print(f"model written to {out}", flush=True)


if __name__ == "__main__":
    main()
