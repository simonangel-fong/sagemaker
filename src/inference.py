"""Inference handlers for the MNIST endpoint.

The sklearn serving container imports this and calls the four hooks below.
Only model_fn is strictly required; the rest are defined so the accepted
request shapes are explicit rather than relying on container defaults.
"""

import json
from pathlib import Path

import joblib
import numpy as np

# Written by src/train.py into SM_MODEL_DIR, which the container unpacks here.
MODEL_FILE = "model.joblib"


def model_fn(model_dir):
    return joblib.load(Path(model_dir) / MODEL_FILE)


def input_fn(request_body, content_type="application/json"):
    """Accept a single 784-float image or a batch of them."""
    if content_type == "application/json":
        data = json.loads(request_body)
        # Key is optional so both {"instances": [...]} and a bare list work.
        if isinstance(data, dict):
            data = data.get("instances", data.get("inputs"))
        arr = np.asarray(data, dtype=np.float32)
    elif content_type == "text/csv":
        arr = np.genfromtxt(request_body.splitlines(), delimiter=",", dtype=np.float32)
    else:
        raise ValueError(f"unsupported content type: {content_type}")

    # A single image arrives flat; the model expects 2D.
    if arr.ndim == 1:
        arr = arr.reshape(1, -1)

    if arr.shape[1] != 784:
        raise ValueError(f"expected 784 features, got {arr.shape[1]}")

    return arr


def predict_fn(input_data, model):
    preds = model.predict(input_data)
    probs = model.predict_proba(input_data)

    return {
        "predictions": preds.tolist(),
        "confidence": probs.max(axis=1).round(4).tolist(),
    }


def output_fn(prediction, accept="application/json"):
    if accept != "application/json":
        raise ValueError(f"unsupported accept type: {accept}")

    return json.dumps(prediction), accept
