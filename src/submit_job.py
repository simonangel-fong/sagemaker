"""Submit train.py as a SageMaker training job (SDK v3).

Runs on ephemeral compute that SageMaker provisions and tears down, so nothing
bills between jobs. Values come from `terraform -chdir=infra/mlops output`.

v3 replaced the framework estimators (SKLearn, PyTorch, ...) with the unified
ModelTrainer, which takes an explicit image URI rather than a framework version.
"""

import argparse
import os

from sagemaker.core.shapes.shapes import OutputDataConfig
from sagemaker.core.training.configs import Compute, InputData, SourceCode
from sagemaker.train.model_trainer import ModelTrainer


def _force_lf_train_script():
    """Work around an SDK bug that breaks training jobs launched from Windows.

    ModelTrainer._prepare_train_script writes sm_train.sh with open(..., "w"),
    so on Windows every \\n becomes \\r\\n. The Linux container then fails with
    "$'\\r': command not found". Rewrite the file with LF after the SDK emits it.
    """
    if os.linesep == "\n":
        return

    original = ModelTrainer._prepare_train_script

    def patched(self, tmp_dir, *a, **kw):
        result = original(self, tmp_dir, *a, **kw)

        path = os.path.join(tmp_dir.name, "sm_train.sh")
        if os.path.exists(path):
            with open(path, "rb") as f:
                data = f.read()
            with open(path, "wb") as f:
                f.write(data.replace(b"\r\n", b"\n"))

        return result

    ModelTrainer._prepare_train_script = patched


_force_lf_train_script()

# Prebuilt scikit-learn container. The registry account differs per region;
# this is ca-central-1.
SKLEARN_IMAGE = (
    "341280168497.dkr.ecr.ca-central-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--bucket", required=True, help="terraform output data_bucket")
    p.add_argument("--role", required=True, help="terraform output execution_role_arn")
    p.add_argument("--instance-type", default="ml.m5.large")
    p.add_argument("--image", default=SKLEARN_IMAGE)
    p.add_argument("--max-iter", type=int, default=1000)
    p.add_argument("--n-samples", type=int, default=10_000)
    p.add_argument("--no-wait", action="store_true", help="submit and return")
    return p.parse_args()


def main():
    args = parse_args()

    trainer = ModelTrainer(
        training_image=args.image,
        role=args.role,
        base_job_name="mnist-logreg",
        source_code=SourceCode(
            source_dir="src",
            entry_script="train.py",
        ),
        compute=Compute(
            instance_type=args.instance_type,
            instance_count=1,
        ),
        hyperparameters={
            "max-iter": args.max_iter,
            "n-samples": args.n_samples,
        },
        output_data_config=OutputDataConfig(
            s3_output_path=f"s3://{args.bucket}/models/",
        ),
    )

    trainer.train(
        input_data_config=[
            InputData(
                channel_name="train",
                data_source=f"s3://{args.bucket}/raw/mnist/",
            )
        ],
        wait=not args.no_wait,
    )


if __name__ == "__main__":
    main()
