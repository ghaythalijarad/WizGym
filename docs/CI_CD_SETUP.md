# CI/CD Pipeline Setup Guide

## Overview

WizGym uses **GitHub Actions** with **AWS OIDC** (no long-lived secrets) for automated deployment.

### Workflows

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `api-deploy.yml` | Push to `main` (apps/api/** or infra/sam/**) | TypeScript check → SAM build → Deploy to Lambda → Health smoke test |
| `mobile-build.yml` | Push to `main` (apps/mobile/**) | Flutter analyze → Build Android APK → Build iOS (no-codesign) |
| `landing-deploy.yml` | Push to `main` (apps/landing/**) | Sync HTML/CSS to S3 → CloudFront invalidation |

---

## Step 1: Create the OIDC Deploy Role

The Terraform config at `infra/aws/terraform/github-oidc.tf` creates:
- An OIDC provider for GitHub Actions
- An IAM role (`wizgym-github-actions-deploy`) with scoped permissions

```bash
cd infra/aws/terraform
terraform init
terraform plan -target=aws_iam_openid_connect_provider.github_actions \
               -target=aws_iam_role.github_actions_deploy \
               -target=aws_iam_role_policy.github_actions_deploy
terraform apply
```

Copy the output `github_actions_role_arn`.

---

## Step 2: Configure GitHub Secrets

Go to **GitHub → Settings → Secrets and variables → Actions** and add:

| Secret Name | Value |
|-------------|-------|
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::940075378952:role/wizgym-github-actions-deploy` |
| `LANDING_S3_BUCKET` | `wizgym-landing-prod` |
| `CLOUDFRONT_DISTRIBUTION_ID` | *(optional, set after creating CloudFront)* |

Also create an **Environment** named `production` under repo Settings → Environments. This enables environment-level protection rules (optional: require approval).

---

## Step 3: First Push

```bash
git add .
git commit -m "feat: add CI/CD pipeline, notifications API, subscription plan PATCH"
git push origin main
```

The `api-deploy.yml` workflow will:
1. Run `tsc --noEmit` (type check)
2. Run `sam build` (esbuild bundle)
3. Run `sam deploy` (CloudFormation update)
4. Hit `/api/v1/health` and assert `"status":"ok"`

---

## Manual Deployment (without CI)

```bash
# 1. Login to AWS SSO
aws sso login --profile wizgym-prod

# 2. Build & deploy
cd infra/sam
sam build
sam deploy --config-env prod --profile wizgym-prod --no-confirm-changeset

# 3. Verify
curl https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/health
```

---

## Flutter: Local iOS Deployment

```bash
cd apps/mobile
flutter build ios --release --dart-define=API_BASE_URL=https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/
# Or for development with hot reload:
flutter run --dart-define=API_BASE_URL=https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/
```

---

## Architecture

```
┌──────────────────┐     push to main     ┌────────────────────┐
│  Developer        │ ──────────────────▶ │  GitHub Actions     │
│  (local machine)  │                      │                    │
└──────────────────┘                      └─────────┬──────────┘
                                                     │ OIDC
                                                     ▼
                                          ┌────────────────────┐
                                          │  AWS IAM Role       │
                                          │  (wizgym-github-    │
                                          │   actions-deploy)   │
                                          └─────────┬──────────┘
                                                     │
                              ┌───────────┬──────────┼──────────┐
                              ▼           ▼          ▼          ▼
                         CloudFormation  Lambda   API Gateway   S3
                         (SAM stack)    (Node18)  (HTTP API)  (Landing)
```
