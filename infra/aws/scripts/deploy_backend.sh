#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/infra/aws/terraform"
BACKEND_DIR="${ROOT_DIR}/apps/backend"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required"
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws cli is required"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required"
  exit 1
fi

IMAGE_TAG="${IMAGE_TAG:-latest}"
AWS_REGION="${AWS_REGION:-$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region)}"
ECR_REPOSITORY_URL="$(terraform -chdir="${TERRAFORM_DIR}" output -raw ecr_repository_url)"
ECS_CLUSTER_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw ecs_cluster_name)"
ECS_SERVICE_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw ecs_service_name)"
ECR_REGISTRY="$(echo "${ECR_REPOSITORY_URL}" | cut -d'/' -f1)"

echo "Logging in to ECR ${ECR_REGISTRY} (${AWS_REGION})"
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "Building backend image ${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
docker build -t "${ECR_REPOSITORY_URL}:${IMAGE_TAG}" "${BACKEND_DIR}"

echo "Pushing image ${ECR_REPOSITORY_URL}:${IMAGE_TAG}"
docker push "${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

if [[ "${IMAGE_TAG}" != "latest" ]]; then
  echo "Tagging and pushing latest"
  docker tag "${ECR_REPOSITORY_URL}:${IMAGE_TAG}" "${ECR_REPOSITORY_URL}:latest"
  docker push "${ECR_REPOSITORY_URL}:latest"
fi

echo "Triggering ECS rolling deployment"
aws ecs update-service \
  --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER_NAME}" \
  --service "${ECS_SERVICE_NAME}" \
  --force-new-deployment >/dev/null

echo "Deployment started successfully."
