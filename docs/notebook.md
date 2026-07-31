# AWS Sagemaker - Notebook Instance

[Back](../README.md)

- [AWS Sagemaker - Notebook Instance](#aws-sagemaker---notebook-instance)
  - [Architecture](#architecture)
  - [Files](#files)
  - [Key config](#key-config)
  - [Use](#use)

---

## Architecture

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

---

## Files

| File                       | Purpose                                   |
| -------------------------- | ----------------------------------------- |
| `08-sagemaker-notebook.tf` | Instance, security group, code repository |
| `07-iam.tf`                | Execution role, scoped policy             |
| `06-s3.tf`                 | Data bucket                               |
| `05-kms.tf`                | CMK for volume + bucket                   |

---

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

---

## Use

```sh
terraform -chdir=infra/mlops init -backend-config=backend.hcl
terraform -chdir=infra/mlops fmt && terraform -chdir=infra/mlops validate

terraform -chdir=infra/mlops apply -auto-approve
terraform -chdir=infra/mlops destroy -auto-approve

# presigned login URL, valid ~12h
terraform -chdir=infra/mlops output -raw notebook_login_command
```

![notebook instance](./img/notebook_instance.png)

![train notebook](./img/notebook_train01.png)

![train notebook](./img/notebook_train02.png)
