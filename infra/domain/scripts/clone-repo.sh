#!/bin/bash
# Clone the project repo into a JupyterLab space on app start.
#
# Runs on EVERY app start, not just the first, and the space EBS volume
# persists across restarts -- so this must be idempotent. A bare `git
# clone` would fail on the second start with "directory already exists"
# and, because LCC failures block the app, leave the space stuck.

set -eux

REPO_URL="${repo_url}"
REPO_DIR="/home/sagemaker-user/$(basename "$REPO_URL" .git)"

if [ -d "$REPO_DIR/.git" ]; then
  echo "repo already present at $REPO_DIR, skipping clone"
else
  git clone "$REPO_URL" "$REPO_DIR"
  echo "cloned $REPO_URL -> $REPO_DIR"
fi
