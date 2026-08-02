"""
Submit train.py as a SageMaker training job (SDK v3).
"""

import argparse
import os

from sagemaker.core.shapes.shapes import OutputDataConfig
from sagemaker.core.training.configs import Compute, InputData, SourceCode
from sagemaker.train.model_trainer import ModelTrainer

# Prebuilt scikit-learn container. region=ca-central-1.
SKLEARN_IMAGE = (
    "341280168497.dkr.ecr.ca-central-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--bucket", required=True, help="terraform output data_bucket")
    p.add_argument("--role", required=True, help="terraform output execution_role_arn")
    p.add_argument("--instance-type", default="ml.m5.large")
    p.add_argument("--image", default=SKLEARN_IMAGE)
    p.add_argument("--n-estimators", type=int, default=100)
    p.add_argument("--min-samples-leaf", type=int, default=5)
    p.add_argument("--no-wait", action="store_true", help="submit and return")
    return p.parse_args()


def submit(
    bucket,
    role,
    instance_type="ml.m5.large",
    image=SKLEARN_IMAGE,
    n_estimators=100,
    min_samples_leaf=5,
    wait=True,
):
    """Submit the training job and return the ModelTrainer."""
    trainer = ModelTrainer(
        training_image=image,
        role=role,
        base_job_name="bike-rf",
        source_code=SourceCode(
            source_dir=os.path.dirname(os.path.abspath(__file__)),
            entry_script="train.py",
        ),
        compute=Compute(
            instance_type=instance_type,
            instance_count=1,
        ),
        hyperparameters={
            "n-estimators": n_estimators,
            "min-samples-leaf": min_samples_leaf,
        },
        output_data_config=OutputDataConfig(
            s3_output_path=f"s3://{bucket}/model/",
        ),
    )

    trainer.train(
        input_data_config=[
            InputData(
                channel_name="train",
                data_source=f"s3://{bucket}/featured/",
            )
        ],
        wait=wait,
    )

    return trainer


def main():
    args = parse_args()

    submit(
        bucket=args.bucket,
        role=args.role,
        instance_type=args.instance_type,
        image=args.image,
        n_estimators=args.n_estimators,
        min_samples_leaf=args.min_samples_leaf,
        wait=not args.no_wait,
    )


if __name__ == "__main__":
    main()
