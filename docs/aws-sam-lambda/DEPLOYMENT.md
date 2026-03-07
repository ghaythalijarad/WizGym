# WizGym Production Deployment (AWS SAM + Lambda) — Source of Truth

**Last updated:** 2026-03-04  
**Account:** `940075378952` (`wizgym-prod`)  
**Region:** `us-east-1`

This document is the canonical deployment guide for WizGym going forward.

---

## 0) Target architecture (new plan)

- **API runtime:** AWS Lambda (Node.js)
- **Ingress:** API Gateway HTTP API (recommended) or REST API (only if you need advanced features)
- **Data:** DynamoDB single-table (`wizgym-prod-core`)
- **Assets:** S3 bucket (`wizzapp-gym-photos-prod-us-east-1`)
- **Auth:** Cognito (existing) or JWT validation at edge (TBD)
- **Domain:** `api.<your-domain>` via API Gateway custom domain + ACM + Route53

> Note: The previous ECS/Copilot approach is archived in `docs/legacy-ecs-copilot/`.

---

## 1) Prerequisites

### 1.1 AWS profile
Your `~/.aws/config` must contain:
- `[profile wizgym-prod]`
- `region = us-east-1`

Verify:
- `aws sts get-caller-identity --profile wizgym-prod`

### 1.2 Tooling
Install (Mac):
- AWS CLI v2
- AWS SAM CLI

Verify:
- `sam --version`

---

## 2) Repo layout (recommended)

We are migrating to a lightweight Lambda API.

Recommended layout:

- `apps/api/` (Lambda handler code)
- `infra/sam/` (SAM template, config, deployment)

If these folders don’t exist yet, create them as part of the rewrite.

---

## 3) Environment configuration

### 3.1 Non-secrets (env vars)
Use Lambda environment variables for:
- `AWS_REGION=us-east-1`
- `DYNAMODB_TABLE_NAME=wizgym-prod-core`
- `S3_BUCKET_GYM_PHOTOS=wizzapp-gym-photos-prod-us-east-1`

### 3.2 Secrets
Store secrets in **SSM Parameter Store** or **Secrets Manager**.

Recommended (SSM):
- `/wizgym/prod/JWT_ACCESS_SECRET`
- `/wizgym/prod/JWT_REFRESH_SECRET`
- `/wizgym/prod/OTPIQ_API_KEY`

> Avoid `/copilot/...` paths for new work. Those were Copilot-era.

Grant Lambda IAM permission to read these parameters.

---

## 4) SAM template requirements (high level)

Your SAM template should define:

- `AWS::Serverless::HttpApi`
- `AWS::Serverless::Function` for the API handler
- IAM policy allowing:
  - `dynamodb:*` (scoped) on table `wizgym-prod-core`
  - `s3:GetObject/PutObject` (scoped) on `wizzapp-gym-photos-prod-us-east-1/*`
  - `ssm:GetParameter(s)` for required secrets

Use least privilege.

---

## 5) Deploy (manual)

From repo root:

- `sam build`
- `sam deploy --guided --profile wizgym-prod --region us-east-1`

After deploy:
- capture the API Gateway URL output
- set up custom domain (next section)

---

## 6) Custom domain (recommended)

Goal: stable endpoint for mobile app.

Steps:
1. Request ACM cert in `us-east-1` for `api.<domain>`
2. Create API Gateway custom domain
3. Map API stage to the domain
4. Create Route53 A/ALIAS record

---

## 7) Update mobile app base URL

Mobile must NOT point to a LAN IP.

Use a single stable URL:
- `https://api.<domain>/api/v1/`

Implementation detail (Flutter): use `--dart-define=API_BASE_URL=...` for each flavor/build.

---

## 8) What to delete vs archive

- Archive legacy ECS/Copilot docs under `docs/legacy-ecs-copilot/`
- Keep `copilot/` folder only if you still need to inspect old stacks; otherwise remove later.

---

## 9) Next implementation tasks

- Implement new Lambda API skeleton
- Implement DynamoDB single-table access layer
- Implement upload/download to S3
- Add health endpoint
- Add CI/CD (GitHub Actions) for `sam deploy`
