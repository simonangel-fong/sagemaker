# Amazon SageMaker Demo - Infrastructure

[Back](../README.md)

- [Amazon SageMaker Demo - Infrastructure](#amazon-sagemaker-demo---infrastructure)
  - [IaC: Terraform](#iac-terraform)
  - [Runbook](#runbook)
  - [Clean up](#clean-up)

---

## IaC: Terraform

```sh
terraform -chdir=infra init -backend-config=backend.hcl -reconfigure
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra apply -auto-approve
terraform -chdir=infra refresh
```

---

## Runbook

- debug commands

```sh
terraform -chdir=infra/domain output -raw domain_id

# apps in the domain (the things blocking space deletion)
aws sagemaker list-apps --domain-id-equals d-tjopcmpvemcl --region ca-central-1 --output table

# spaces in the domain
aws sagemaker list-spaces --domain-id-equals d-tjopcmpvemcl --region ca-central-1 --output table

# remove apps
aws sagemaker delete-app \
  --domain-id d-tjopcmpvemcl \
  --space-name admin-alice-jupyterlab \
  --app-type JupyterLab \
  --app-name default \
  --region ca-central-1
```

---

## Clean up

```sh
terraform -chdir=infra destroy -auto-approve
```
