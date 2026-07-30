# Training Job

Training on ephemeral compute. SageMaker provisions the instance, runs the
script, uploads the model, and terminates. Nothing bills between jobs.

```
   submit_job.py
        │
        ▼
   ┌─────────────────────────────┐
   │  Training Job (ml.m5.large) │   provisioned on demand,
   │  sklearn container          │   destroyed when done
   │  runs src/train.py          │
   └──┬───────────────────────┬──┘
      │ SM_CHANNEL_TRAIN      │ SM_MODEL_DIR
      ▼                       ▼
  s3://…/raw/mnist/     s3://…/models/…/model.tar.gz
```

## Files

| File                 | Purpose                                       |
| -------------------- | --------------------------------------------- |
| `src/train.py`       | Entry point run inside the container          |
| `src/submit_job.py`  | Submits the job                               |
| `09-training-job.tf` | IAM to create jobs + pass the role, log group |

## Key contract

The script never touches S3. SageMaker mounts the channel and collects the
output directory:

```python
p.add_argument("--train",     default=os.environ.get("SM_CHANNEL_TRAIN"))
p.add_argument("--model-dir", default=os.environ.get("SM_MODEL_DIR"))
...
joblib.dump(clf, Path(args.model_dir) / "model.joblib")
print(f"test_accuracy={acc:.4f}")   # scraped from CloudWatch
```

## Use

```sh
python -m venv .venv && .venv\Scripts\activate
pip install sagemaker-train      # SDK needs Python 3.10-3.12

python src/submit_job.py \
  --bucket (terraform -chdir=infra/mlops output -raw data_bucket) \
  --role   (terraform -chdir=infra/mlops output -raw execution_role_arn)
```

Result: `Completed`, 124 billable seconds, `test_accuracy=0.9015`.

## Notes

- SDK v3 replaced the framework estimators (`SKLearn`, `PyTorch`) with the
  unified `ModelTrainer`, which takes an explicit image URI.
- IAM needs `iam:PassRole` — submitting hands the execution role to SageMaker.
  The role also needs `ec2:*NetworkInterface*`; the SDK validates this upfront.
- **Windows:** the SDK writes `sm_train.sh` in text mode, producing CRLF that
  the Linux container rejects. `submit_job.py` patches it back to LF.
