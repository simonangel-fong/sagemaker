# Notebook Instance

A managed Jupyter server for authoring. Bills per hour while `InService`.

```
                    ┌──────────────────────┐
   presigned URL    │  Notebook Instance   │
   ───────────────► │  ml.t3.medium        │
                    │  Jupyter + git clone │
                    └──────────┬───────────┘
                               │ execution role
                    ┌──────────┴───────────┐
                    ▼                      ▼
              ┌──────────┐          ┌────────────┐
              │ S3 data  │          │ CloudWatch │
              │ (KMS)    │          │ logs       │
              └──────────┘          └────────────┘
```

## Files

| File                       | Purpose                                   |
| -------------------------- | ----------------------------------------- |
| `08-sagemaker-notebook.tf` | Instance, security group, code repository |
| `07-iam.tf`                | Execution role, scoped policy             |
| `06-s3.tf`                 | Data bucket                               |
| `05-kms.tf`                | CMK for volume + bucket                   |

## Key config

The repo is cloned into the instance on start, so notebooks live in git:

```hcl
resource "aws_sagemaker_notebook_instance" "this" {
  subnet_id               = var.public_subnet_ids[0]
  direct_internet_access  = "Enabled"
  kms_key_id              = aws_kms_key.this.arn
  default_code_repository = aws_sagemaker_code_repository.this.code_repository_name
}
```

## Use

```sh
terraform -chdir=infra/mlops apply -auto-approve

# presigned login URL, valid ~12h
terraform -chdir=infra/mlops output -raw notebook_login_command
```

Open `notebooks/train.ipynb` and run all cells: downloads MNIST, uploads to
`raw/`, trains, writes the model to `models/`.

## Notes

- Subnet **must** route to an IGW or NAT, or pip and dataset downloads hang.
- The clone happens at instance start only. Later commits need `git pull`.
- No push: the code repository has no credentials attached.
- `08-sagemaker-notebook.tf` is currently commented out to stop the hourly
  charge. Uncomment and re-apply to bring the instance back; S3, KMS and IAM
  are independent, so data survives either way.
