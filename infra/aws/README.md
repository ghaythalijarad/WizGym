# AWS Infrastructure (Terraform)

> ⚠️ **Note:** The Terraform configs in this folder were written for a previous ECS/NestJS architecture
> that no longer exists. The **active backend** is `apps/api` — an AWS Lambda function deployed via
> AWS SAM (see `infra/sam/`). The Terraform files are kept as reference only.

## Active Backend Stack (SAM)

```
apps/api  ──►  infra/sam/template.yaml  ──►  AWS Lambda + API Gateway + DynamoDB
```

Deploy with:
```bash
cd infra/sam
sam build
sam deploy --config-env prod
```

---

## Legacy Terraform Contents (reference only)

The Terraform configs provisioned:

- VPC with public and private subnets
- ECS cluster + Fargate service
- ECR repository
- RDS PostgreSQL
- ElastiCache Redis
- Secrets Manager

These resources are **not used** by the current Lambda-based stack.

## Prerequisites (if you ever want to use Terraform)

- Terraform `>= 1.5`
- AWS CLI configured with deploy permissions

## Notes

- Keep `otpiq_api_key` secret — it is stored in SSM Parameter Store at `/wizgym/prod/OTPIQ_API_KEY`.
- For HTTPS, API Gateway already provides TLS termination on the live Lambda endpoint.
