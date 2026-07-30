goal

- deploy jupyter notebook in sagemaker via terraform

---

phases
01
init

- files - 01-variables.tf - 02-locals.tf - 03-providers.tf: s3 backend - 04-outputs.tf - backend.hcl - backend.hcl.example - terraform.tfvars - terraform.tfvars.example
  tf init -backend-config

---

02
create sagemaker domain

- 05-sagamaker.tf

---

03
create notebook instance

- 06-sagamaker-notebook.tf
  output url to login notebook

---

04
harden network + iam

---

05
deploy

- tf fmt / validate
- tf plan -var-file
- tf apply
- confirm domain + notebook status InService

---

06
- connect current repo
  - aws_sagemaker_code_repository -> default_code_repository
  - cloned on instance start, git pull for later commits
- notebooks/train.ipynb: mnist end to end
  - download mnist, upload to s3 data bucket
  - train logistic regression on the instance
  - save model to s3, reload and verify

---

07
teardown

- stop notebook instance to save cost
- tf destroy
- confirm s3 backend state + kms keys cleaned up

---

08
training job

- move training out of the notebook onto ephemeral compute
- src/train.py: read SM_CHANNEL_TRAIN, write SM_MODEL_DIR
- iam: CreateTrainingJob + iam:PassRole on the execution role
- submit with the prebuilt SKLearn estimator, fit on s3://.../raw/
- model artifact lands in s3://.../models/, notebook not needed while it runs

---

09

- deployment


---

## Development

- Init

```sh
terraform -chdir=infra/mlops init -backend-config=backend.hcl
terraform -chdir=infra/mlops fmt && terraform -chdir=infra/mlops validate

terraform -chdir=infra/mlops apply -auto-approve
terraform -chdir=infra/mlops destroy -auto-approve
```


## Notebook

```sh
terraform -chdir=infra/mlops output -raw notebook_login_command
```

---

## Train job

```sh
python -m venv .venv

pip install sagemaker-train

python src/submit_job.py --bucket (terraform -chdir=infra/mlops output -raw data_bucket) --role (terraform -chdir=infra/mlops output -raw execution_role_arn)


```