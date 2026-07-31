Scenario

- A ml team wants to train the bike sharing model using Amazon Sagemaker.
- data dir: data/

Task

- create domain
- enable data scientists alice(the admin) and bob onboard
- use domain feature to train the model
- create mlflow to track experiments
- create pipeline to automate ml training
- deploy the ml model

---

phase

1 tf init
init terraform, reference infra/mlops
code path: infra/domain/

---

2 upload data

- tf: s3 bucket + kms, prefixes raw/, featured/, model/
- cli: aws s3 cp data/ -> raw/ (see Development)
- verify: aws s3 ls shows day.csv, hour.csv

note: tf provisions infra only. data moves via cli.

---

3 create domain
onboard alice (admin)

- alice role: trust sagemaker + studio-access policy (no data access)
- domain: auth IAM, vpc + subnets, kms, retention policy delete
- user profile: alice
- verify: alice opens studio, lands in own home dir
- reference: infra/archived/06-sagemaker-domain.tf

note: studio-access is the floor -- createapp/space, ecr pull, kms.
a truly empty role cannot open studio at all. data access is phase 4.

---

part A -- alice solo, phases 4-8
one persona through the full lifecycle. bob comes after.

---

4 train

- tf: policy 1 -- s3 rw + training job + passrole (09-iam-data.tf)
- tf: lcc clone script + alice's private space, ml.t3.medium (10-space.tf)
- studio: start the jupyterlab app on that space (manual, billed)
- repo is already cloned by the lcc -- open notebooks/studio_train.ipynb
- set BUCKET, run all: raw/ -> featured/ -> model/
- explore: instance switch, space stop/start, terminal, git ui
- verify: rmse ~126, r2 ~0.63, model.joblib in model/

note: tf declares the space, not the running app. starting the app
is manual and is the part that bills -- stop it when done, the ebs
volume persists.

---

5 evaluate

- no tf. notebooks/studio_eval.ipynb, reads featured/
- baseline (predict the mean) so rmse has something to beat
- two runs: A leaf5 (phase 4 model), B leaf1 (deeper trees)
- write model/eval.json -- phase 6 replays these into mlflow
- explore: notebook vs training job, cost of each
- verify: refit gives identical metrics, assert in the notebook

expected: baseline rmse 227.8 / A 126.3 r2 .634 12MB
B 125.2 r2 .641 70.7MB -- 0.9% better, 6x the artifact

---

6 mlflow tracking

- tf: mlflow app + its own role, artifact store -> mlflow-app/ (11-mlflow.tf)
- tf: policy 2 -- sagemaker:\*MlflowApp\* + sagemaker-mlflow:\* (12-iam-mlflow.tf)
- notebooks/studio_mlflow.ipynb: set TRACKING_ARN, run all
- log A and B with params / metrics / model, register A
- explore: run comparison ui, parallel coordinates, registry handoff
- verify: search_runs matches eval.json rmse exactly (assert in nb)

note: app, not tracking server. serverless -- no hourly charge, nothing
to stop between sessions, ~2 min to create instead of ~25. it is also
the studio-facing resource: default_domain_id_list puts it in the
sidebar, which a tracking server never appeared in.

the retired tracking server owned the mlflow/ prefix. the app uses
mlflow-app/ -- both number experiments from 1, so sharing one prefix
interleaves two unrelated id spaces.

---

7 pipeline

- steps: preprocess -> train -> eval -> [rmse gate] -> register
- tf: policy 3 -- pipeline + processing jobs + registry (13-iam-pipeline.tf)
- tf: model package group -- the registry itself, not the dag
- src/preprocess.py, src/evaluate.py new; src/train.py reused unchanged
- src/pipeline.py defines the dag, notebooks/studio_pipeline.ipynb runs it
- register lands PendingManualApproval -- phase 8 deploys only Approved
- explore: step cache on rerun, gate skip at a threshold the model misses
- verify: run green, rmse 126.3 matches phase 5, one pending version

note: the dag is python, not terraform. aws_sagemaker_pipeline exists but
takes the whole definition as one json blob -- the blob the sdk generates,
and any upsert() from the notebook makes terraform's copy stale. tf owns
the policy and the package group; the definition ships with the code it
trains. same line phase 2 drew for data.

policy 3 adds processing jobs: phase 4 granted training jobs only, so
preprocess and eval 403 without it.

mlflow's AutoModelRegistrationEnabled stays off. it would promote every
log_model call, which is the ungated path this phase replaces.

---

8 deploy

- deploy approved version to a real-time endpoint
- reference infra/mlops/10-deployment-endpoint.tf, 11-lambda.tf, 12-api.tf
- smoke test with src/invoke_endpoint.py
- verify: endpoint returns a prediction

---

part B -- add bob, collaboration
alice's stack is done and working. bob tests sharing + isolation.

---

9 onboard bob

- bob role: separate role, s3 scoped to own prefix
- user profile: bob
- verify: bob opens studio; denied on alice's prefix

---

10 collaboration

- shared space: alice creates, bob joins, both edit
- explore: real-time coedit, shared ebs vs private home dir
- bob reads alice's mlflow runs, submits his own
- bob trains a variant, registers a new model version
- alice approves it in the registry -- the handoff
- verify: bob cannot approve or deploy on his own

---

11 teardown

- delete apps + shared spaces + both profiles before domain
- confirm efs removed, empty s3 buckets

---

## Development

```sh
terraform -chdir=infra/domain init -backend-config=backend.hcl -reconfigure
terraform -chdir=infra/domain fmt && terraform -chdir=infra/domain validate

terraform -chdir=infra/domain apply -auto-approve

terraform -chdir=infra/domain destroy -auto-approve

```

upload data (phase 2, after apply)

```sh
BUCKET=$(terraform -chdir=infra/domain output -raw data_bucket)
aws s3 cp data/ "s3://$BUCKET/raw/" --recursive --exclude "*" --include "*.csv"
# upload: data\day.csv to s3://sagemaker-domain-dev-data-pqkx2l/raw/day.csv
# upload: data\hour.csv to s3://sagemaker-domain-dev-data-pqkx2l/raw/hour.csv

aws s3 ls "s3://sagemaker-domain-dev-data-pqkx2l/raw/"
# 2026-07-31 06:31:51          0
# 2026-07-31 06:33:23      57569 day.csv
# 2026-07-31 06:33:23    1156736 hour.csv


```

pipeline (phase 7) -- values for the notebook

```sh
terraform -chdir=infra/domain output -raw data_bucket
terraform -chdir=infra/domain output -raw alice_role_arn
terraform -chdir=infra/domain output -raw model_package_group

# or drive it from a shell instead of the notebook
python src/pipeline.py \
  --bucket "$(terraform -chdir=infra/domain output -raw data_bucket)" \
  --role "$(terraform -chdir=infra/domain output -raw alice_role_arn)" \
  --model-package-group "$(terraform -chdir=infra/domain output -raw model_package_group)" \
  --start
```

---

## Debug

```sh
# the mlflow app creates in ~2 min. the tracking server it replaced
# took ~25, which is what this check was for.

terraform -chdir=infra/domain output -raw mlflow_app_arn

# open the ui
terraform -chdir=infra/domain output -raw mlflow_ui_command

# runs live in the app's metadata store, not in s3 -- s3 holds only the
# artifacts. an empty ui with objects under mlflow-app/ means the client
# is pointed at a different mlflow resource than the ui.
```

phase 7

```sh
# which step failed, and why
aws sagemaker list-pipeline-execution-steps --pipeline-execution-arn ARN \
  --query 'PipelineExecutionSteps[].[StepName,StepStatus,FailureReason]' --output table

# a run that ends green with nothing registered is the gate working,
# not a failure -- check the condition step's outcome before debugging.

# registry state
aws sagemaker list-model-packages --model-package-group-name GROUP \
  --query 'ModelPackageSummaryList[].[ModelPackageVersion,ModelApprovalStatus]' --output table

# ScriptProcessor uploads `code=` relative to cwd. run the notebook from
# the repo root, or preprocess.py is not found at definition time.
```
