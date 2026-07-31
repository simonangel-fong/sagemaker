# AWS Sagemaker - Deployment Endpoint

[Back](../README.md)

- [AWS Sagemaker - Deployment Endpoint](#aws-sagemaker---deployment-endpoint)
  - [Architecture](#architecture)
  - [Files](#files)
  - [Key contract](#key-contract)
  - [Use](#use)
  - [Public API](#public-api)

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
terraform -chdir=infra/mlops apply -auto-approve   # ~18 min to InService

python src/invoke_endpoint.py \
  --endpoint (terraform -chdir=infra/mlops output -raw endpoint_name) \
  --bucket   (terraform -chdir=infra/mlops output -raw data_bucket)

# test
pytest tests/ -q
# ......................                                                                                                                      [100%]
# 22 passed in 0.04s
```

---

## Public API

`11-api.tf` puts an HTTP API and Lambda in front, giving a URL any client can
call without AWS credentials:

```sh
terraform -chdir=infra/mlops output -raw api_url
# https://0li80bm2hi.execute-api.ca-central-1.amazonaws.com//predict

curl -X POST "https://0li80bm2hi.execute-api.ca-central-1.amazonaws.com//predict" -H 'content-type: application/json' -d '{"instances": [{"season": 1, "yr": 1, "mnth": 6, "hr": 8, "holiday": 0, "weekday": 3, "workingday": 1, "weathersit": 1, "temp": 0.24, "atemp": 0.2879, "hum": 0.81, "windspeed": 0.0}]}'
# {"predictions": [207.2], "count": 1}
```

![test api gtw](./img/test_api_gtw.png)
