# Amazon SageMaker Studio Demo - Infrastructure

[Back](../README.md)

- [Amazon SageMaker Studio Demo - Infrastructure](#amazon-sagemaker-studio-demo---infrastructure)
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

terraform -chdir=infra destroy -auto-approve
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

step 1 -- delete the running apps studio, or cli

```sh
terraform -chdir=infra output -raw studio_domain_id
# d-grsdbi6b8zf7

aws sagemaker list-apps --domain-id-equals "d-grsdbi6b8zf7" \
  --query 'Apps[].[AppType,AppName,SpaceName,UserProfileName,Status]' --output table

# --------------------------------------------------------------------------
# |                                ListApps                                |
# +------------+----------+--------------------------+-------+-------------+
# |  JupyterLab|  default |  bob-jupyterlab          |  None |  InService  |
# |  JupyterLab|  default |  admin-alice-jupyterlab  |  None |  InService  |
# +------------+----------+--------------------------+-------+-------------+

# remove notebook
aws sagemaker delete-app --domain-id "d-grsdbi6b8zf7" --space-name admin-alice-jupyterlab \
  --app-type JupyterLab --app-name default

aws sagemaker delete-app --domain-id "d-grsdbi6b8zf7" --space-name bob-jupyterlab \
  --app-type JupyterLab --app-name default
```

step 2 -- delete the sdk-created resources cli

```sh
# remove pipeline
aws sagemaker list-pipelines

aws sagemaker delete-pipeline --pipeline-name bike-sharing-rf
# {
#     "PipelineArn": "arn:aws:sagemaker:ca-central-1:099139718958:pipeline/bike-sharing-rf"
# }

# remove model
terraform -chdir=infra output -raw model_package_group
# mlops-sagemaker-studio-dev-bike-sharing-rf

for arn in $(aws sagemaker list-model-packages --model-package-group-name "mlops-sagemaker-studio-dev-bike-sharing-rf" \
    --query 'ModelPackageSummaryList[].ModelPackageArn' --output text); do
  aws sagemaker delete-model-package --model-package-name "$arn"
done

aws sagemaker list-models --query 'Models[].ModelName' --output text | \
  xargs -r -n1 aws sagemaker delete-model --model-name
```

step 3 -- destroy the stack cli

```sh
terraform -chdir=infra destroy -auto-approve
```

step 4 -- confirm nothing is left cli

```sh
aws efs describe-file-systems \
  --query 'FileSystems[?Tags[?Value==`'"sagemaker-domain-dev-bike-sharing-rf"'`]].FileSystemId' --output text

aws iam list-roles \
  --query 'Roles[?starts_with(RoleName,`sagemaker-domain-dev`)].RoleName' --output text
```
