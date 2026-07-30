"""Inference handlers for the bike sharing endpoint.

The sklearn serving container imports this and calls the four hooks below.
Only model_fn is strictly required; the rest are defined so the accepted
request shapes are explicit rather than relying on container defaults.
"""

import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

# Written by src/train.py into SM_MODEL_DIR, which the container unpacks here.
MODEL_FILE = "model.joblib"
FEATURES_FILE = "features.joblib"


def model_fn(model_dir):
    """Return both the regressor and the column order it was trained on."""
    model_dir = Path(model_dir)
    return {
        "model": joblib.load(model_dir / MODEL_FILE),
        "features": joblib.load(model_dir / FEATURES_FILE),
    }


def input_fn(request_body, content_type="application/json"):
    """Accept one record or a batch, as objects or positional rows.

    Objects are safer: {"season": 1, "hr": 8, ...} is order independent.
    A bare list of numbers must already be in training column order.
    """
    if content_type == "application/json":
        data = json.loads(request_body)
        if isinstance(data, dict):
            data = data.get("instances", data.get("inputs", data))
        # A single record, either {..} or [v1, v2, ...].
        if isinstance(data, dict) or not isinstance(data[0], (list, dict)):
            data = [data]
        return data

    if content_type == "text/csv":
        rows = np.genfromtxt(request_body.splitlines(), delimiter=",", dtype=np.float64)
        return (rows if rows.ndim == 2 else rows.reshape(1, -1)).tolist()

    raise ValueError(f"unsupported content type: {content_type}")


def predict_fn(input_data, model_bundle):
    model = model_bundle["model"]
    features = model_bundle["features"]

    # Reindex puts columns in training order and surfaces missing keys as NaN
    # rather than silently shifting values into the wrong column.
    frame = pd.DataFrame(input_data)
    if frame.shape[1] != len(features):
        raise ValueError(f"expected {len(features)} features, got {frame.shape[1]}")

    frame = frame.reindex(columns=features) if frame.columns.dtype == object else frame
    frame.columns = features

    if frame.isnull().any().any():
        missing = frame.columns[frame.isnull().any()].tolist()
        raise ValueError(f"missing or unrecognized features: {missing}")

    preds = model.predict(frame)

    # Rentals are a non-negative count; a regressor can undershoot below zero.
    return {"predictions": np.maximum(preds, 0).round(1).tolist()}


def output_fn(prediction, accept="application/json"):
    if accept != "application/json":
        raise ValueError(f"unsupported accept type: {accept}")

    return json.dumps(prediction), accept
