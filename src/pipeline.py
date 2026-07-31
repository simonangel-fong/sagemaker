"""Phase 7: the bike sharing training pipeline (SDK v3).

    preprocess -> train -> evaluate -> [rmse gate] -> register

Phases 4-6 ran all of this inside one notebook kernel. Here each step is
a job SageMaker provisions and tears down, so the whole thing reruns
without a human in the loop.

The definition lives in code rather than Terraform on purpose: it changes
when the model changes, not when the infrastructure does. Terraform owns
policy 3 and the model package group (infra/domain/13-iam-pipeline.tf).

Registration is gated. A version only reaches the registry if rmse clears
the threshold, and it lands PendingManualApproval -- phase 8 deploys only
an approved version, and phase 10 is where bob registers and alice
approves.
"""

import argparse

from sagemaker.core.processing import ScriptProcessor
from sagemaker.core.shapes import (
    OutputDataConfig,
    ProcessingInput,
    ProcessingOutput,
    ProcessingS3Input,
    ProcessingS3Output,
)
# The workflow API is split across two packages: sagemaker.core.workflow
# holds the value types a definition is built out of -- parameters,
# conditions, property lookups -- and sagemaker.mlops.workflow holds the
# step types and the pipeline itself.
from sagemaker.core.workflow.conditions import ConditionLessThanOrEqualTo
from sagemaker.core.workflow.functions import JsonGet
from sagemaker.core.workflow.parameters import ParameterFloat, ParameterString
from sagemaker.core.workflow.pipeline_context import PipelineSession
from sagemaker.core.workflow.properties import PropertyFile
from sagemaker.mlops.workflow.condition_step import ConditionStep
from sagemaker.mlops.workflow.model_step import ModelStep
from sagemaker.mlops.workflow.pipeline import Pipeline
from sagemaker.mlops.workflow.steps import CacheConfig, ProcessingStep, TrainingStep
from sagemaker.serve.model_builder import ModelBuilder
from sagemaker.train.configs import Compute, InputData, SourceCode
from sagemaker.train.model_trainer import ModelTrainer

# Prebuilt scikit-learn container. The registry account differs per
# region; this is ca-central-1, same image submit_job.py pins.
SKLEARN_IMAGE = (
    "341280168497.dkr.ecr.ca-central-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
)

PIPELINE_NAME = "bike-sharing-rf"

# Phase 5 measured 126.3 for this configuration and 227.8 for the
# predict-the-mean baseline. The gate sits between them: comfortably
# above the model so ordinary variance does not trip it, well below the
# baseline so a genuinely broken run cannot pass.
DEFAULT_RMSE_THRESHOLD = 150.0


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--bucket", required=True, help="terraform output data_bucket")
    p.add_argument("--role", required=True, help="terraform output alice_role_arn")
    p.add_argument(
        "--model-package-group",
        required=True,
        help="terraform output model_package_group",
    )
    p.add_argument("--image", default=SKLEARN_IMAGE)
    p.add_argument("--instance-type", default="ml.m5.large")
    p.add_argument("--rmse-threshold", type=float, default=DEFAULT_RMSE_THRESHOLD)
    p.add_argument("--start", action="store_true", help="start a run after upserting")
    return p.parse_args()


def build(bucket, role, model_package_group, image, instance_type, rmse_threshold):
    """Return the Pipeline object. Nothing is created until upsert()."""
    # PipelineSession is what makes .run()/.train() below return step
    # arguments instead of launching a job immediately.
    #
    # default_bucket matters as much as that. Left unset, the SDK reaches
    # for sagemaker-<region>-<account> and tries to create it -- alice's
    # policy is scoped to the data bucket, so that 403s on HeadBucket
    # before any job is even defined. ScriptProcessor also uploads the
    # `code=` script to whatever this points at, and there is no
    # per-processor override for it.
    session = PipelineSession(default_bucket=bucket)

    # Exposed as parameters so a run can be retried with a different
    # threshold or instance from the Studio UI without editing code.
    param_instance_type = ParameterString(
        name="InstanceType", default_value=instance_type
    )
    param_threshold = ParameterFloat(
        name="RmseThreshold", default_value=rmse_threshold
    )

    # Steps are cached so a rerun that only changes the gate does not
    # refit the model.
    cache = CacheConfig(enable_caching=True, expire_after="30d")

    # ##############################
    # 1. preprocess
    # ##############################
    processor = ScriptProcessor(
        image_uri=image,
        command=["python3"],
        instance_type=param_instance_type,
        instance_count=1,
        role=role,
        base_job_name="bike-preprocess",
        sagemaker_session=session,
    )

    step_preprocess = ProcessingStep(
        name="Preprocess",
        step_args=processor.run(
            code="src/preprocess.py",
            inputs=[
                ProcessingInput(
                    input_name="raw",
                    s3_input=ProcessingS3Input(
                        s3_uri=f"s3://{bucket}/raw/",
                        local_path="/opt/ml/processing/input",
                        s3_data_type="S3Prefix",
                        s3_input_mode="File",
                    ),
                )
            ],
            outputs=[
                ProcessingOutput(
                    output_name="featured",
                    # featured/pipeline/, not featured/. Writing the bare
                    # prefix overwrote the hour.parquet phase 4 produced,
                    # which phases 5 and 6 both read -- one pipeline run
                    # silently rewrote their input.
                    s3_output=ProcessingS3Output(
                        s3_uri=f"s3://{bucket}/featured/pipeline/",
                        local_path="/opt/ml/processing/output",
                        s3_upload_mode="EndOfJob",
                    ),
                )
            ],
        ),
        cache_config=cache,
    )

    featured_uri = step_preprocess.properties.ProcessingOutputConfig.Outputs[
        "featured"
    ].S3Output.S3Uri

    # ##############################
    # 2. train
    # ##############################
    # src/train.py unchanged from phase 4 -- it already reads
    # SM_CHANNEL_TRAIN and writes SM_MODEL_DIR, which is exactly the
    # contract a TrainingStep needs.
    trainer = ModelTrainer(
        training_image=image,
        role=role,
        base_job_name="bike-train",
        source_code=SourceCode(source_dir="src", entry_script="train.py"),
        compute=Compute(instance_type=instance_type, instance_count=1),
        hyperparameters={"n-estimators": 100, "min-samples-leaf": 5},
        # Without this the SDK falls back to its own default bucket
        # (sagemaker-<region>-<account>), which alice's policy does not
        # cover -- HeadBucket 403 before a single job is defined. Every
        # artifact belongs in the data bucket anyway.
        output_data_config=OutputDataConfig(
            s3_output_path=f"s3://{bucket}/model/pipeline/",
        ),
        sagemaker_session=session,
    )

    step_train = TrainingStep(
        name="Train",
        step_args=trainer.train(
            input_data_config=[
                InputData(channel_name="train", data_source=featured_uri)
            ]
        ),
        cache_config=cache,
    )

    model_artifact = step_train.properties.ModelArtifacts.S3ModelArtifacts

    # ##############################
    # 3. evaluate
    # ##############################
    # The condition step resolves a JSONPath into this file, so it has to
    # be declared as a property file rather than just written to S3.
    evaluation_report = PropertyFile(
        name="EvaluationReport",
        output_name="evaluation",
        path="evaluation.json",
    )

    evaluator = ScriptProcessor(
        image_uri=image,
        command=["python3"],
        instance_type=param_instance_type,
        instance_count=1,
        role=role,
        base_job_name="bike-evaluate",
        sagemaker_session=session,
    )

    step_evaluate = ProcessingStep(
        name="Evaluate",
        step_args=evaluator.run(
            code="src/evaluate.py",
            inputs=[
                ProcessingInput(
                    input_name="model",
                    s3_input=ProcessingS3Input(
                        s3_uri=model_artifact,
                        local_path="/opt/ml/processing/model",
                        s3_data_type="S3Prefix",
                        s3_input_mode="File",
                    ),
                ),
                ProcessingInput(
                    input_name="test",
                    s3_input=ProcessingS3Input(
                        s3_uri=featured_uri,
                        local_path="/opt/ml/processing/test",
                        s3_data_type="S3Prefix",
                        s3_input_mode="File",
                    ),
                ),
            ],
            outputs=[
                ProcessingOutput(
                    output_name="evaluation",
                    s3_output=ProcessingS3Output(
                        s3_uri=f"s3://{bucket}/model/evaluation/",
                        local_path="/opt/ml/processing/evaluation",
                        s3_upload_mode="EndOfJob",
                    ),
                )
            ],
        ),
        property_files=[evaluation_report],
        cache_config=cache,
    )

    # ##############################
    # 4. register, behind the gate
    # ##############################
    builder = ModelBuilder(
        s3_model_data_url=model_artifact,
        image_uri=image,
        role_arn=role,
        sagemaker_session=session,
    )

    step_register = ModelStep(
        name="Register",
        step_args=builder.register(
            model_package_group_name=model_package_group,
            # The gate that phase 8 reads. Nothing deploys until a human
            # moves this to Approved.
            approval_status="PendingManualApproval",
            content_types=["text/csv"],
            response_types=["text/csv"],
            inference_instances=["ml.m5.large"],
            transform_instances=["ml.m5.large"],
        ),
    )

    step_gate = ConditionStep(
        name="CheckRmse",
        conditions=[
            ConditionLessThanOrEqualTo(
                left=JsonGet(
                    step_name=step_evaluate.name,
                    property_file=evaluation_report,
                    json_path="regression_metrics.rmse.value",
                ),
                right=param_threshold,
            )
        ],
        if_steps=[step_register],
        # No else_steps: a run that misses the threshold ends green with
        # nothing registered. The registry staying empty is the signal.
        else_steps=[],
    )

    return Pipeline(
        name=PIPELINE_NAME,
        parameters=[param_instance_type, param_threshold],
        steps=[step_preprocess, step_train, step_evaluate, step_gate],
        sagemaker_session=session,
    )


def main():
    args = parse_args()

    pipeline = build(
        bucket=args.bucket,
        role=args.role,
        model_package_group=args.model_package_group,
        image=args.image,
        instance_type=args.instance_type,
        rmse_threshold=args.rmse_threshold,
    )

    # upsert, not create: rerunning this is the normal way to iterate.
    pipeline.upsert(role_arn=args.role)
    print(f"upserted pipeline {PIPELINE_NAME}")

    if args.start:
        execution = pipeline.start()
        print(f"started {execution.arn}")


if __name__ == "__main__":
    main()
