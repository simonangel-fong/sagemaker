"""Evaluate step: score the trained artifact and emit a property file.

The pipeline's condition step reads rmse out of the JSON written here, so
the shape matters -- ConditionLessThanOrEqualTo resolves a JSONPath into
this document. Metric names match phase 5's eval.json so a pipeline run
and a notebook run stay comparable.
"""

import argparse
import json
import tarfile
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

TARGET = "cnt"


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--model-dir", default="/opt/ml/processing/model")
    p.add_argument("--test-dir", default="/opt/ml/processing/test")
    p.add_argument("--output-dir", default="/opt/ml/processing/evaluation")
    return p.parse_args()


def load_model(model_dir):
    """The training step hands over model.tar.gz, not a loose artifact.

    Returns the model and the feature order it was fit on. train.py saves
    that list alongside the model because column order is part of the
    contract -- a RandomForest takes positional input, so reordering the
    columns silently scores garbage rather than raising.
    """
    root = Path(model_dir)

    tars = sorted(root.glob("*.tar.gz"))
    if tars:
        with tarfile.open(tars[0]) as tar:
            tar.extractall(root)

    path = root / "model.joblib"
    if not path.exists():
        raise FileNotFoundError(f"model.joblib not found in {model_dir}")

    features_path = root / "features.joblib"
    if not features_path.exists():
        raise FileNotFoundError(f"features.joblib not found in {model_dir}")

    return joblib.load(path), joblib.load(features_path)


def load_frame(test_dir):
    files = sorted(Path(test_dir).glob("*.parquet"))
    if not files:
        raise FileNotFoundError(f"no .parquet found in {test_dir}")

    return pd.read_parquet(files[0])


def main():
    args = parse_args()

    model, features = load_model(args.model_dir)
    df = load_frame(args.test_dir)

    # Rebuild the frame in the order the model was fit on rather than the
    # order the parquet happens to be in. Deriving it from df.columns
    # here scored 2250 against a 227 baseline -- wrong values in every
    # column, no error raised.
    missing = [c for c in features if c not in df.columns]
    assert not missing, f"test frame is missing {missing}"

    # Same time split as phases 4-6: fit on 2011, score on 2012. The
    # model never saw yr == 1.
    test = df[df.yr == 1]

    y_true = test[TARGET]
    y_pred = model.predict(test[features])

    rmse = float(np.sqrt(mean_squared_error(y_true, y_pred)))
    mae = float(mean_absolute_error(y_true, y_pred))
    r2 = float(r2_score(y_true, y_pred))

    # Predicting the training mean is the floor any real model clears.
    # Carried through so the gate threshold has context in the report.
    baseline = float(np.sqrt(mean_squared_error(y_true, np.full(len(y_true), df[df.yr == 0][TARGET].mean()))))

    report = {
        "regression_metrics": {
            "rmse": {"value": rmse},
            "mae": {"value": mae},
            "r2": {"value": r2},
            "baseline_rmse": {"value": baseline},
        }
    }

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    out = out_dir / "evaluation.json"
    out.write_text(json.dumps(report, indent=2))

    print(f"scored {len(test)} rows (2012)", flush=True)
    print(f"rmse={rmse:.4f} mae={mae:.4f} r2={r2:.4f}", flush=True)
    print(f"baseline rmse={baseline:.4f}", flush=True)
    print(f"written to {out}", flush=True)


if __name__ == "__main__":
    main()
