"""Invoke the MNIST endpoint with real digits pulled from S3.

Reads the same raw/mnist/mnist.npz the training job used, so predictions can
be checked against known labels.
"""

import argparse
import io
import json

import boto3
import numpy as np


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--endpoint", required=True, help="terraform output endpoint_name")
    p.add_argument("--bucket", required=True, help="terraform output data_bucket")
    p.add_argument("--region", default="ca-central-1")
    p.add_argument("--n", type=int, default=5, help="how many digits to send")
    return p.parse_args()


def main():
    args = parse_args()

    s3 = boto3.client("s3", region_name=args.region)
    obj = s3.get_object(Bucket=args.bucket, Key="raw/mnist/mnist.npz")

    with np.load(io.BytesIO(obj["Body"].read())) as data:
        # Tail of the set: the model trained on the first 10k rows.
        X, y = data["X"][-args.n :], data["y"][-args.n :]

    runtime = boto3.client("sagemaker-runtime", region_name=args.region)
    response = runtime.invoke_endpoint(
        EndpointName=args.endpoint,
        ContentType="application/json",
        Body=json.dumps({"instances": X.tolist()}),
    )

    result = json.loads(response["Body"].read())

    preds = result["predictions"]
    conf = result["confidence"]
    correct = sum(int(p) == int(a) for p, a in zip(preds, y))

    for p, a, c in zip(preds, y, conf):
        mark = "ok " if int(p) == int(a) else "MISS"
        print(f"  {mark} predicted={p} actual={a} confidence={c:.3f}")

    print(f"\n{correct}/{len(preds)} correct")


if __name__ == "__main__":
    main()
