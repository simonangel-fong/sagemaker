"""HTTP API front door for the bike sharing endpoint.

The SageMaker endpoint only accepts SigV4-signed IAM requests, so it cannot be
called from a browser. This handler holds the IAM role, validates the payload,
and forwards it to InvokeEndpoint.

Kept out of src/ on purpose: src/ is tarred wholesale into sourcedir.tar.gz and
shipped into the model container, which has no business carrying this.
"""

import json
import os

import boto3

ENDPOINT_NAME = os.environ["ENDPOINT_NAME"]

# Mirrors src/train.py's column set. Declared here so a malformed request fails
# at the door with a 400 instead of costing an inference and returning a 500.
FEATURES = [
    "season",
    "yr",
    "mnth",
    "hr",
    "holiday",
    "weekday",
    "workingday",
    "weathersit",
    "temp",
    "atemp",
    "hum",
    "windspeed",
]

MAX_INSTANCES = 100

_runtime = boto3.client("sagemaker-runtime")

CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
}


class BadRequest(Exception):
    """Client-side error: surfaces as a 400 rather than a stack trace."""


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json", **CORS},
        "body": json.dumps(body),
    }


def parse_instances(raw_body):
    """Normalize a request body into a list of feature dicts.

    Accepts {"instances": [...]}, a bare list, or a single record object, so
    the API tolerates the same shapes as inference.input_fn.
    """
    if not raw_body:
        raise BadRequest("empty request body")

    try:
        data = json.loads(raw_body)
    except (ValueError, TypeError) as exc:
        raise BadRequest(f"body is not valid JSON: {exc}") from exc

    if isinstance(data, dict):
        data = data.get("instances", data.get("inputs", data))

    # A single record arrives as a bare object.
    if isinstance(data, dict):
        data = [data]

    if not isinstance(data, list) or not data:
        raise BadRequest("expected a non-empty list of records under 'instances'")

    if len(data) > MAX_INSTANCES:
        raise BadRequest(f"too many instances: {len(data)} > {MAX_INSTANCES}")

    return [_validate(record, i) for i, record in enumerate(data)]


def _validate(record, index):
    """Check one record has exactly the training features, all numeric."""
    if not isinstance(record, dict):
        raise BadRequest(
            f"instance {index}: expected an object of named features, got {type(record).__name__}"
        )

    missing = [f for f in FEATURES if f not in record]
    if missing:
        raise BadRequest(f"instance {index}: missing features: {missing}")

    unknown = [k for k in record if k not in FEATURES]
    if unknown:
        raise BadRequest(f"instance {index}: unrecognized features: {unknown}")

    clean = {}
    for feature in FEATURES:
        value = record[feature]
        # bool is an int subclass, but a bool here means the caller sent the
        # wrong type for a numeric field.
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise BadRequest(f"instance {index}: feature '{feature}' must be a number")
        clean[feature] = value

    return clean


def invoke(instances, runtime=None):
    """Call the SageMaker endpoint and return its parsed predictions."""
    client = runtime or _runtime
    response = client.invoke_endpoint(
        EndpointName=ENDPOINT_NAME,
        ContentType="application/json",
        Accept="application/json",
        Body=json.dumps({"instances": instances}),
    )

    payload = response["Body"].read()
    if isinstance(payload, bytes):
        payload = payload.decode()

    return json.loads(payload)


def handler(event, context=None, runtime=None):
    method = (
        event.get("requestContext", {}).get("http", {}).get("method")
        or event.get("httpMethod")
        or "POST"
    )

    if method == "OPTIONS":
        return {"statusCode": 204, "headers": CORS, "body": ""}

    try:
        instances = parse_instances(event.get("body"))
    except BadRequest as exc:
        return _response(400, {"error": str(exc)})

    try:
        result = invoke(instances, runtime=runtime)
    except Exception as exc:  # noqa: BLE001 - never leak a stack trace to callers
        print(f"invoke_endpoint failed: {type(exc).__name__}: {exc}")
        return _response(502, {"error": "inference failed"})

    # output_fn returns {"predictions": [...]}, but tolerate a bare list so a
    # change on the container side degrades instead of 500-ing.
    predictions = result.get("predictions", result) if isinstance(result, dict) else result
    return _response(200, {"predictions": predictions, "count": len(instances)})
