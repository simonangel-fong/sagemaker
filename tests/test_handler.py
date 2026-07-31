"""Tests for the predict Lambda handler."""

import io
import json

import pytest

import handler as h


def record(**overrides):
    """A valid bike sharing record; override single fields per test."""
    base = {
        "season": 1,
        "yr": 1,
        "mnth": 6,
        "hr": 8,
        "holiday": 0,
        "weekday": 3,
        "workingday": 1,
        "weathersit": 1,
        "temp": 0.24,
        "atemp": 0.2879,
        "hum": 0.81,
        "windspeed": 0.0,
    }
    base.update(overrides)
    return base


class FakeRuntime:
    """Stand-in for the sagemaker-runtime client."""

    def __init__(self, predictions=None, error=None):
        self.predictions = predictions if predictions is not None else [42.0]
        self.error = error
        self.calls = []

    def invoke_endpoint(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        body = json.dumps({"predictions": self.predictions}).encode()
        return {"Body": io.BytesIO(body)}


def event(body, method="POST"):
    raw = body if isinstance(body, (str, type(None))) else json.dumps(body)
    return {"body": raw, "requestContext": {"http": {"method": method}}}


# ##############################
# parse_instances
# ##############################
def test_accepts_instances_wrapper():
    assert h.parse_instances(json.dumps({"instances": [record()]})) == [record()]


def test_accepts_bare_list():
    assert h.parse_instances(json.dumps([record()])) == [record()]


def test_accepts_single_object():
    assert h.parse_instances(json.dumps(record())) == [record()]


def test_reorders_to_training_column_order():
    shuffled = dict(reversed(list(record().items())))
    assert list(h.parse_instances(json.dumps(shuffled))[0]) == h.FEATURES


def test_rejects_empty_body():
    with pytest.raises(h.BadRequest, match="empty request body"):
        h.parse_instances("")


def test_rejects_malformed_json():
    with pytest.raises(h.BadRequest, match="not valid JSON"):
        h.parse_instances("{nope")


def test_rejects_empty_list():
    with pytest.raises(h.BadRequest, match="non-empty list"):
        h.parse_instances("[]")


def test_rejects_missing_feature():
    partial = record()
    del partial["hr"]
    with pytest.raises(h.BadRequest, match="missing features.*hr"):
        h.parse_instances(json.dumps(partial))


def test_rejects_unknown_feature():
    with pytest.raises(h.BadRequest, match="unrecognized features.*cnt"):
        h.parse_instances(json.dumps(record(cnt=100)))


def test_rejects_non_numeric_feature():
    with pytest.raises(h.BadRequest, match="'temp' must be a number"):
        h.parse_instances(json.dumps(record(temp="warm")))


def test_rejects_bool_feature():
    with pytest.raises(h.BadRequest, match="'holiday' must be a number"):
        h.parse_instances(json.dumps(record(holiday=True)))


def test_rejects_positional_row():
    with pytest.raises(h.BadRequest, match="expected an object"):
        h.parse_instances(json.dumps([[1, 1, 6, 8, 0, 3, 1, 1, 0.24, 0.28, 0.81, 0.0]]))


def test_rejects_oversized_batch():
    with pytest.raises(h.BadRequest, match="too many instances"):
        h.parse_instances(json.dumps([record()] * (h.MAX_INSTANCES + 1)))


def test_accepts_batch_at_limit():
    assert len(h.parse_instances(json.dumps([record()] * h.MAX_INSTANCES))) == h.MAX_INSTANCES


# ##############################
# handler
# ##############################
def test_returns_predictions():
    runtime = FakeRuntime(predictions=[123.4])
    response = h.handler(event({"instances": [record()]}), runtime=runtime)

    assert response["statusCode"] == 200
    assert json.loads(response["body"]) == {"predictions": [123.4], "count": 1}


def test_forwards_correct_payload_to_sagemaker():
    runtime = FakeRuntime()
    h.handler(event({"instances": [record()]}), runtime=runtime)

    call = runtime.calls[0]
    assert call["EndpointName"] == "sagemaker-dev-endpoint"
    assert call["ContentType"] == "application/json"
    assert json.loads(call["Body"]) == {"instances": [record()]}


def test_batch_round_trip():
    runtime = FakeRuntime(predictions=[1.0, 2.0, 3.0])
    response = h.handler(event({"instances": [record()] * 3}), runtime=runtime)

    assert json.loads(response["body"]) == {"predictions": [1.0, 2.0, 3.0], "count": 3}


def test_validation_error_is_400_and_does_not_invoke():
    runtime = FakeRuntime()
    response = h.handler(event({"instances": [{"season": 1}]}), runtime=runtime)

    assert response["statusCode"] == 400
    assert "missing features" in json.loads(response["body"])["error"]
    assert runtime.calls == []


def test_endpoint_failure_is_502_without_leaking_detail():
    runtime = FakeRuntime(error=RuntimeError("ModelError: secret internal trace"))
    response = h.handler(event({"instances": [record()]}), runtime=runtime)

    assert response["statusCode"] == 502
    assert json.loads(response["body"]) == {"error": "inference failed"}


def test_options_preflight_short_circuits():
    runtime = FakeRuntime()
    response = h.handler(event(None, method="OPTIONS"), runtime=runtime)

    assert response["statusCode"] == 204
    assert response["headers"]["Access-Control-Allow-Origin"] == "*"
    assert runtime.calls == []


def test_success_response_carries_cors_and_json_content_type():
    response = h.handler(event({"instances": [record()]}), runtime=FakeRuntime())

    assert response["headers"]["Access-Control-Allow-Origin"] == "*"
    assert response["headers"]["content-type"] == "application/json"


def test_handles_bare_prediction_payload():
    """Endpoint returning a raw list still yields a usable response."""

    class BareRuntime(FakeRuntime):
        def invoke_endpoint(self, **kwargs):
            self.calls.append(kwargs)
            return {"Body": io.BytesIO(json.dumps([7.5]).encode())}

    response = h.handler(event({"instances": [record()]}), runtime=BareRuntime())
    assert json.loads(response["body"])["predictions"] == [7.5]
