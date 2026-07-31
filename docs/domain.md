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

- tf: bob role + scoped policy, profile, private space (15-bob.tf)
- reuses the enumerated studio-access policy from phase 3 -- which is
  what it was kept for once alice moved to AmazonSageMakerFullAccess
- profile sets execution_role explicitly: the domain default points at
  alice, so without it bob inherits her role and every isolation check
  passes for the wrong reason
- verify: bob opens studio; reads alice's work; cannot overwrite it

note: the line is not "bob can do less of everything". he does the same
work alice does. three things are his alone to not do -- overwrite her
outputs, approve a version, deploy.

reads on featured/ and model/ are allowed on purpose. phase 10 has him
training a variant of alice's model, which only means anything if both
start from the same featured/ frame.

|                                        | bob      | alice |
| -------------------------------------- | -------- | ----- |
| read raw/                              | yes      | yes   |
| read featured/, model/                 | yes      | yes   |
| read mlflow-app/ artifacts             | yes      | yes   |
| write users/bob/                       | yes      | n/a   |
| write featured/, model/, mlflow-app/   | **deny** | yes   |
| training + processing jobs             | yes      | yes   |
| author + run pipelines                 | yes      | yes   |
| mlflow: read runs, log own             | yes      | yes   |
| registry: list, describe, register     | yes      | yes   |
| registry: approve (UpdateModelPackage) | **deny** | yes   |
| registry: delete version or group      | **deny** | yes   |
| deploy (Create/Update/DeleteEndpoint)  | **deny** | yes   |
| studio: Search, job logs, own space    | yes      | yes   |

the denies are explicit, not implicit. phase 10 verifies "bob cannot
approve", and a default deny reads the same as an oversight in the error
message. explicit also survives someone attaching a broader policy later.

the s3 deny covers writes only, not reads -- the boundary that matters is
that bob cannot clobber alice's outputs, which is exactly what the phase
7 preprocess bug did by accident.

```sh
# what bob can and cannot do, without opening studio
ROLE=$(terraform -chdir=infra/domain output -raw bob_role_arn)
aws iam simulate-principal-policy --policy-source-arn "$ROLE" \
  --action-names sagemaker:UpdateModelPackage \
  --query 'EvaluationResults[0].EvalDecision' --output text
# explicitDeny

# sagemaker-mlflow:* is not modelled by the simulator -- it returns
# implicitDeny for alice too, whose access demonstrably works. studio is
# the only real test for that one.
```

---

10 collaboration

not implemented. steps:

1. tf: shared space (16-shared-space.tf)
   sharing_type = "Shared", and omit ownership_settings -- that omission
   is what makes it shared. both profiles then see it in the launcher
   and share one ebs volume instead of separate home dirs.

2. bob reads alice's mlflow runs
   nothing to build. set_tracking_uri + search_runs as bob. first real
   test of his sagemaker-mlflow grant -- the simulator cannot check it.

3. bob trains a variant
   reuse src/pipeline.py with min_samples_leaf=1 -- phase 5's run B.
   125.2 rmse, 0.9% better, 6x the artifact: a real tradeoff to argue
   about, not a toy change.

4. register, then hand off
   his run writes v2 PendingManualApproval. he cannot move it.
   alice approves in studio: Models > group > v2 > Update status.

5. verify the boundary
   bob calls update_model_package and catches AccessDenied. a test that
   expects the failure is what makes the isolation real.

gotchas:

- src/pipeline.py hardcodes featured/pipeline/ and model/pipeline/.
  bob's run hits the s3 write deny and fails mid-run, after paying for
  preprocess and train. parameterise the output prefix to users/bob/
  first.

- one shared ebs volume means one clone of the repo. two people running
  notebooks in the same checkout collide on outputs and git state.

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

# the model registry has no page in the aws console left nav -- not under
# Model governance (that is Model dashboard / Model cards) and not under
# Marketplace model packages (third-party listings). registered versions
# are visible only in studio, or by the cli above.
#
# endpoints are the opposite: Deployments & inference > Endpoints shows
# them in the console once phase 8 creates one.

# ScriptProcessor uploads `code=` relative to cwd. run the notebook from
# the repo root, or preprocess.py is not found at definition time.
```

---

## Onboard Bob

```sh
terraform -chdir=infra/domain output -raw bob_login_command


```

- Bob
