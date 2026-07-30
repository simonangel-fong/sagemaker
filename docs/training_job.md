# AWS Sagemaker - Training Job

[Back](../README.md)

- [AWS Sagemaker - Training Job](#aws-sagemaker---training-job)
  - [Architecture](#architecture)
  - [Files](#files)
  - [Key contract](#key-contract)
  - [Use](#use)

---

## Architecture

Training on ephemeral compute. SageMaker provisions the instance, runs the script, uploads the model, and terminates. Nothing bills between jobs.

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
  s3://…/raw/bike/      s3://…/models/…/model.tar.gz
```

---

## Files

| File                 | Purpose                                       |
| -------------------- | --------------------------------------------- |
| `src/train.py`       | Entry point run inside the container          |
| `src/submit_job.py`  | Submits the job                               |
| `09-training-job.tf` | IAM to create jobs + pass the role, log group |

---

## Key contract

The script never touches S3. SageMaker mounts the channel and collects the
output directory:

```python
p.add_argument("--train",     default=os.environ.get("SM_CHANNEL_TRAIN"))
p.add_argument("--model-dir", default=os.environ.get("SM_MODEL_DIR"))
...
joblib.dump(model, Path(args.model_dir) / "model.joblib")
print(f"rmse={rmse:.4f}")            # scraped from CloudWatch
```

---

## Use

```sh
# init
python -m venv .venv
.venv\Scripts\activate

pip install sagemaker-train

# submit training job
python src/submit_job.py --bucket (terraform -chdir=infra/mlops output -raw data_bucket) --role   (terraform -chdir=infra/mlops output -raw execution_role_arn)
```

Result: `Completed`, 115 billable seconds, `rmse=126.35 r2=0.6342`.

![training](./img/training_jobs.png)
