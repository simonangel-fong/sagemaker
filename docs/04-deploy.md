# AWS Sagemaker - Deployment Endpoint

[Back](../README.md)

- [AWS Sagemaker - Deployment Endpoint](#aws-sagemaker---deployment-endpoint)
  - [Architecture](#architecture)
  - [Files](#files)
  - [Key contract](#key-contract)
  - [Use](#use)
  - [Test: Public API](#test-public-api)
  - [Runbook](#runbook)

---

## Architecture

Serverless inference. An HTTPS API that scales to zero — billed per request,
nothing while idle.

```
   browser / curl (no auth)      caller (SigV4)
        │                             │
        ▼                             │
   ┌─────────────────────┐            │
   │  HTTP API           │  POST /predict, 10 rps
   │  └ Lambda (predict) │  validates, signs, forwards
   └──────────┬──────────┘            │
              │                       │
              ▼                       ▼
   ┌──────────────────────────┐
   │  Serverless Endpoint     │  2048 MB, max concurrency 2
   │  sklearn container       │  scales to zero when idle
   │  runs src/inference.py   │
   └──┬────────────────────┬──┘
      │ model_data_url     │ SAGEMAKER_SUBMIT_DIRECTORY
      ▼                    ▼
  models/…/model.tar.gz   code/sourcedir.tar.gz
```

---

## Files

| File                        | Purpose                          |
| --------------------------- | -------------------------------- |
| `src/inference.py`          | The four container hooks         |
| `src/invoke_endpoint.py`    | Test client (SigV4, direct)      |
| `lambda/predict/handler.py` | Public API handler               |
| `tests/test_handler.py`     | Handler tests, no AWS needed     |
| `10-deployment-endpoint.tf` | Model, endpoint config, endpoint |
| `11-api.tf`                 | Lambda, HTTP API, route          |

---

## Key contract

The container calls these four functions. Only `model_fn` is required:

```python
def model_fn(model_dir):            # load model.joblib
def input_fn(body, content_type):   # parse JSON or CSV -> records
def predict_fn(data, model):        # predict + confidence
def output_fn(prediction, accept):  # serialize JSON
```

![deploy engpoint](./img/deploy_endpoint.png)

---

## Use

Set the artifact in `terraform.tfvars`, then apply:

```hcl
model_artifact_uri = "s3://<bucket>/models/<job>/output/model.tar.gz"
```

```sh
terraform -chdir=infra apply -auto-approve   # ~18 min to InService

# test
pytest lambda/tests/ -q
# ......................                                                                                                                      [100%]
# 22 passed in 0.04s
```

---

## Test: Public API

```sh
terraform -chdir=infra output -raw api_url
# https://ngn74uwg7f.execute-api.ca-central-1.amazonaws.com/predict

curl -X POST "https://ngn74uwg7f.execute-api.ca-central-1.amazonaws.com/predict" -H 'content-type: application/json' -d '{"instances": [{"season": 1, "yr": 1, "mnth": 6, "hr": 8, "holiday": 0, "weekday": 3, "workingday": 1, "weathersit": 1, "temp": 0.24, "atemp": 0.2879, "hum": 0.81, "windspeed": 0.0}]}'
# {"predictions": [207.2], "count": 1}
```

---

## Runbook

```sh
# confirm endpiont status
aws sagemaker list-endpoints --region ca-central-1  --query 'Endpoints[].[EndpointName,EndpointStatus' --output text
aws sagemaker list-endpoints  \
  --region ca-central-1     \
  --query 'Endpoints[].[EndpointName,EndpointStatus]'   \
  --output text

# mlops-sagemaker-dev-endpoint    InService

# get log stream
aws logs describe-log-streams   \
  --log-group-name /aws/sagemaker/Endpoints/mlops-sagemaker-dev-endpoint    \
  --region ca-central-1     \
  --order-by LastEventTime    \
  --descending --max-items 3    \
  --query 'logStreams[].logStreamName'      \
  --output text 2>&1

# get log event in stream
aws logs get-log-events \
  --log-group-name "/aws/sagemaker/Endpoints/mlops-sagemaker-dev-endpoint"  \
  --log-stream-name "AllTraffic/bada2215750460a8d77c73c9047f920d-cdeed22d3d664776b149162253db461d"  \
  --region ca-central-1     \
  --limit 60    \
  --query "events[].message"    \
  --output text


```
