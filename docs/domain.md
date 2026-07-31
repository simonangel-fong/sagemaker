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

- tf: tracking server + its own role, artifact store -> mlflow/ (11-mlflow.tf)
- tf: policy 2 -- sagemaker: control plane + sagemaker-mlflow:* (12-iam-mlflow.tf)
- notebooks/studio_mlflow.ipynb: set TRACKING_ARN, run all
- log A and B with params / metrics / model, register A
- explore: run comparison ui, parallel coordinates, registry handoff
- verify: search_runs matches eval.json rmse exactly (assert in nb)

note: the server bills hourly while it exists, idle or not -- the most
expensive resource in this stack. stop it between sessions, runs and
artifacts survive in s3.

---

7 pipeline

- steps: preprocess -> train -> eval -> register
- grant: passrole + pipeline exec -- policy 3
- register to model registry, manual approval gate
- reference src/train.py, src/submit_job.py
- verify: pipeline run green end to end

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

---

## Debug

```sh
#  MLflow tracking servers take ~25 minutes

aws sagemaker describe-mlflow-tracking-server \
  --tracking-server-name sagemaker-domain-dev-mlflow \
  --region ca-central-1 --query 'TrackingServerStatus'

# "Creating"
```