# AWS Deployment (Backend)

This folder contains production infrastructure for `apps/backend` using Terraform and ECS Fargate.

## What It Provisions
- VPC with 2 public and 2 private subnets
- Public ALB for API traffic
- ECS cluster + Fargate service for NestJS backend
- ECR repository for backend images
- RDS PostgreSQL
- ElastiCache Redis
- CloudWatch log group
- Secrets Manager secret for backend runtime secrets
- IAM roles and policies for ECS tasks
- ECS autoscaling policy (CPU target tracking)

## Prerequisites
- Terraform `>= 1.5`
- AWS CLI configured with deploy permissions
- Docker installed for image build/push

## First-Time Provisioning
```bash
cd /Users/ghaythallaheebi/Handlesensitiveinformation/infra/aws/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your real values (especially otpiq_api_key)
terraform init
terraform plan
terraform apply
```

## Backend Image Deploy
After `terraform apply`, deploy backend image and restart ECS service:

```bash
cd /Users/ghaythallaheebi/Handlesensitiveinformation
IMAGE_TAG=latest AWS_REGION=us-east-1 ./infra/aws/scripts/deploy_backend.sh
```

## Notes
- ECS task startup runs: `npm run db:migrate && node dist/main.js`.
- Keep `otpiq_api_key` secret and rotate any previously exposed live key.
- For HTTPS, set `acm_certificate_arn` in Terraform variables.
