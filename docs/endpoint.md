# Endpoint

Serverless inference. An HTTPS API that scales to zero — billed per request,
nothing while idle.

```
   caller (SigV4)
        │
        ▼
   ┌──────────────────────────┐
   │  Serverless Endpoint     │  2048 MB, max concurrency 2
   │  sklearn container       │  scales to zero when idle
   │  runs src/inference.py   │
   └──┬────────────────────┬──┘
      │ model_data_url     │ SAGEMAKER_SUBMIT_DIRECTORY
      ▼                    ▼
  models/…/model.tar.gz   code/sourcedir.tar.gz
```

## Files

| File | Purpose |
|---|---|
| `src/inference.py` | The four container hooks |
| `src/invoke_endpoint.py` | Test client |
| `10-endpoint.tf` | Model, endpoint config, endpoint |

## Key contract

The container calls these four functions. Only `model_fn` is required:

```python
def model_fn(model_dir):            # load model.joblib
def input_fn(body, content_type):   # parse JSON or CSV -> (n, 784)
def predict_fn(data, model):        # predict + confidence
def output_fn(prediction, accept):  # serialize JSON
```

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
```

Result: 5/5 correct on unseen digits, confidence 0.974-1.000.

## Notes

- Endpoint is **opt-in**: empty `model_artifact_uri` creates nothing. Set it
  back to `""` and apply to tear down just these resources.
- Not internet-facing. Requires SigV4-signed IAM requests, so browsers cannot
  call it directly — put a backend or API Gateway + Lambda in front.
- Serverless cold-starts after idle. Use provisioned concurrency for latency
  sensitive paths, at the cost of continuous billing.
- Creation takes ~18 min; deletion is fast.
