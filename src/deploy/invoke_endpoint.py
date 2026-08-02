"""
Invoke endpoint
"""

import argparse
import io
import json

import boto3
import pandas as pd

DROP = ["instant", "dteday", "casual", "registered", "cnt"]


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--endpoint", required=True, help="terraform output endpoint_name")
    p.add_argument("--bucket", required=True, help="terraform output data_bucket")
    p.add_argument("--region", default="ca-central-1")
    p.add_argument("--n", type=int, default=8, help="how many hours to send")
    return p.parse_args()


def main():
    args = parse_args()

    s3 = boto3.client("s3", region_name=args.region)
    obj = s3.get_object(Bucket=args.bucket, Key="raw/bike/hour.csv")
    df = pd.read_csv(io.BytesIO(obj["Body"].read()))

    # 2012 rows: held out from training.
    test = df[df.yr == 1]
    sample = test.sample(n=args.n, random_state=0).sort_values(["dteday", "hr"])

    features = [c for c in df.columns if c not in DROP]
    payload = sample[features].to_dict(orient="records")

    runtime = boto3.client("sagemaker-runtime", region_name=args.region)
    response = runtime.invoke_endpoint(
        EndpointName=args.endpoint,
        ContentType="application/json",
        Body=json.dumps({"instances": payload}),
    )

    preds = json.loads(response["Body"].read())["predictions"]
    actuals = sample.cnt.tolist()

    print(f"{'date':12} {'hr':>3} {'predicted':>10} {'actual':>7} {'error':>7}")
    for (_, row), p, a in zip(sample.iterrows(), preds, actuals):
        print(f"{row.dteday:12} {row.hr:3d} {p:10.1f} {a:7d} {p - a:+7.1f}")

    mae = sum(abs(p - a) for p, a in zip(preds, actuals)) / len(preds)
    print(f"\nmean absolute error: {mae:.1f} rentals")


if __name__ == "__main__":
    main()
