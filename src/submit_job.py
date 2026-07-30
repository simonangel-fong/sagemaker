"""Submit train.py as a SageMaker training job.

Runs on ephemeral compute that SageMaker provisions and tears down, so nothing
bills between jobs. Values come from `terraform -chdir=infra/mlops output`.
"""

import argparse

import boto3
from sagemaker.inputs import TrainingInput
from sagemaker.sklearn.estimator import SKLearn


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--bucket", required=True, help="terraform output data_bucket")
    p.add_argument("--role", required=True, help="terraform output execution_role_arn")
    p.add_argument("--region", default="ca-central-1")
    p.add_argument("--instance-type", default="ml.m5.large")
    p.add_argument("--max-iter", type=int, default=1000)
    p.add_argument("--n-samples", type=int, default=10_000)
    # Blocks until the job finishes; pass --no-wait to submit and return.
    p.add_argument("--no-wait", action="store_true")
    return p.parse_args()


def main():
    args = parse_args()

    import sagemaker

    session = sagemaker.Session(boto_session=boto3.Session(region_name=args.region))

    estimator = SKLearn(
        entry_point="train.py",
        source_dir="src",
        role=args.role,
        instance_type=args.instance_type,
        instance_count=1,
        framework_version="1.2-1",
        py_version="py3",
        sagemaker_session=session,
        output_path=f"s3://{args.bucket}/models/",
        base_job_name="mnist-logreg",
        hyperparameters={
            "max-iter": args.max_iter,
            "n-samples": args.n_samples,
        },
    )

    estimator.fit(
        {"train": TrainingInput(f"s3://{args.bucket}/raw/mnist/", content_type="application/x-npz")},
        wait=not args.no_wait,
    )

    print(f"job: {estimator.latest_training_job.name}")
    if not args.no_wait:
        print(f"model: {estimator.model_data}")


if __name__ == "__main__":
    main()
