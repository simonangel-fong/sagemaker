"""Test setup for the predict Lambda.

boto3 is provided by the Lambda runtime, not by this repo, so it is stubbed
here. The handler takes its runtime client by injection, so nothing under test
ever touches the real client.
"""

import sys
import types
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "lambda" / "predict"))

if "boto3" not in sys.modules:
    stub = types.ModuleType("boto3")
    stub.client = lambda *args, **kwargs: None
    sys.modules["boto3"] = stub

# handler reads ENDPOINT_NAME at import time.
import os  # noqa: E402

os.environ.setdefault("ENDPOINT_NAME", "sagemaker-dev-endpoint")
