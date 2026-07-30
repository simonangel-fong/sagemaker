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
network + iam prerequisites

- 07-network.tf: vpc, subnet, security group for notebook
- 08-iam.tf: sagemaker execution role + policy (s3, cloudwatch logs)
- kms key for volume/storage encryption

---

05
deploy

- tf fmt / validate
- tf plan -var-file
- tf apply
- confirm domain + notebook status InService

---

06
verify

- open presigned notebook url from output
- run a test notebook cell (boto3 / sagemaker sdk)
- confirm s3 access and cloudwatch logs

---

07
teardown

- stop notebook instance to save cost
- tf destroy
- confirm s3 backend state + kms keys cleaned up

---

## Development

- Init

```sh
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra apply -auto-approve
```
