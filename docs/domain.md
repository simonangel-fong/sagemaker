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

- create s3 bucket
  - key: raw/, featured/, model/
- upload data

---

3 create domain
onboard alice (admin)

- alice role: trust sagemaker only, no inline policy yet
- domain: auth IAM, vpc + subnets, retention policy delete
- user profile: alice
- verify: alice opens studio, lands in own home dir
- reference: infra/archived/06-sagemaker-domain.tf

note: role stays empty here. each later phase adds one policy.

---

part A -- alice solo, phases 4-8
one persona through the full lifecycle. bob comes after.

---

4 train

- grant: s3 rw on the bucket -- policy 1
- launch jupyterlab space, port notebooks/train.ipynb
- read raw/, write featured/ + model/
- explore: instance switch, space lifecycle, terminal
- verify: artifact lands in model/

---

5 evaluate

- eval on holdout, capture rmse / r2
- explore: notebook vs training job, cost of each
- verify: metrics reproducible across two runs

---

6 mlflow tracking

- create mlflow tracking server, artifact store -> s3
- grant: mlflow access on that server arn -- policy 2
- log params / metrics / model, compare runs
- explore: run comparison ui, model registry handoff
- verify: both runs from phase 5 show up

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
```
