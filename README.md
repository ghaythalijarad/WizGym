# WizGym

Arabic-first, cross-platform gym management ecosystem for four roles:
**Platform Admin · Gym Owner · Trainer · Member (Trainee)**

---

## Architecture

```
Mobile (Flutter)  ──►  AWS API Gateway  ──►  AWS Lambda (TypeScript)  ──►  DynamoDB
```

| Layer | Technology | Location |
|-------|-----------|----------|
| Mobile App | Flutter (Dart) | `apps/mobile/` |
| Admin Dashboard | HTML/JS/CSS | `apps/admin-dashboard/` |
| Backend API | AWS Lambda + TypeScript | `apps/api/` |
| Landing Page | Static HTML | `apps/landing/` |
| Shared Types | TypeScript contracts | `packages/contracts/` |
| Infrastructure | AWS SAM + Terraform | `infra/` |
| Docs | Markdown | `docs/` |

> ⚠️ `apps/backend` (NestJS/MongoDB) has been **deleted** — it was a dead scaffold.
> The **only** backend is `apps/api` (AWS Lambda + DynamoDB). No Docker, no MongoDB, no Redis.

---

## Live Endpoints

**Base URL:** `https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1`

### Auth

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/phone/send-otp` | Send OTP via OTPIQ (WhatsApp/SMS) |
| POST | `/auth/phone/verify-otp` | Verify OTP code |
| POST | `/auth/signup` | Create account (phone + role + password) |
| POST | `/auth/login` | Login (phone + role + password) |

### Gyms

| Method | Path | Description |
|--------|------|-------------|
| GET | `/gyms/public` | List approved gyms (public) |
| GET | `/gyms/owner/mine` | Owner's gyms |
| GET | `/gyms/owner/dashboard` | Owner dashboard stats |
| PATCH | `/gyms/:id/profile` | Update gym profile |
| POST | `/gyms/:id/join` | Member joins gym |
| POST | `/gyms/:id/trainers/join` | Trainer requests to join |
| POST | `/gyms/:id/trainers/:tid/hire` | Owner hires trainer |
| POST | `/gyms/:id/ratings` | Rate a gym |

### Trainers

| Method | Path | Description |
|--------|------|-------------|
| GET | `/trainers/me/clients` | Trainer's client list |
| GET | `/trainers/me/gyms` | Trainer's affiliated gyms |
| POST | `/trainers/:id/ratings` | Rate a trainer |

### Plans

| Method | Path | Description |
|--------|------|-------------|
| GET | `/plans/me` | Member's current plan |
| POST | `/plans` | Create a plan (owner) |
| GET | `/plans/:gymId` | List gym plans |

### Analytics

| Method | Path | Description |
|--------|------|-------------|
| GET | `/analytics/owner/dashboard` | `{totalMembers, totalTrainers, totalGyms, occupancyRate, averageRating}` |
| GET | `/analytics/owner/retention` | `{month, retentionPercent, churnPercent, predictedAtRisk}` |

### Admin

| Method | Path | Description |
|--------|------|-------------|
| GET | `/admin/dashboard` | `{totalGyms, totalUsers}` |
| GET | `/admin/gyms/pending` | Gyms awaiting approval |
| POST | `/admin/gyms/:id/approve` | Approve gym |
| POST | `/admin/gyms/:id/reject` | Reject gym |
| GET | `/admin/subscriptions` | All subscriptions |

---

## Role Simulation (development only)

Add header: `x-user-role: ADMIN | OWNER | TRAINER | USER`

---

## Auth Flow

```
Send OTP  ──►  Verify OTP  ──►  Signup (first time) / Login (returning)
                                        │
                                JWT returned  ──►  Bearer token for all requests
```

- Auth is **phone-number based** — password is set after OTP verification at signup.
- **Admin login skips OTP** — direct phone + password. Admin accounts are created manually, not via signup.

---

## Quick Start

### Mobile App

```bash
cd apps/mobile
flutter pub get
flutter run          # points to live AWS API automatically
```

### Backend API

```bash
cd apps/api
npm install
npm run build
```

### Deploy API (AWS SAM)

```bash
cd infra/sam
sam build
sam deploy --config-env prod
# Profile: wizgym-prod  |  Region: us-east-1  |  Stack: sam-app
```

### Admin Dashboard

```bash
cd apps/admin-dashboard
bash deploy.sh       # deploys to S3
```

---

## OTP Setup

OTP is delivered via [OTPIQ](https://otpiq.com) (WhatsApp/SMS). The API key lives in AWS SSM Parameter Store.

```bash
# Store your OTPIQ API key (one time)
./setup-otpiq-key.sh YOUR_OTPIQ_API_KEY

# Verify it was stored
aws ssm get-parameter \
  --name "/wizgym/prod/OTPIQ_API_KEY" \
  --with-decryption \
  --profile wizgym-prod --region us-east-1

# Test the OTP endpoint
./test-otp.sh
```

---

## Useful Commands

```bash
# Tail live Lambda logs
aws logs tail /aws/lambda/sam-app-WizGymApiFunction-yE1SQSAsdJGg \
  --since 5m --follow --profile wizgym-prod --region us-east-1

# Smoke-test live endpoints
curl https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/gyms/public | jq .
curl https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/admin/dashboard | jq .

# Flutter clean build
cd apps/mobile && flutter clean && flutter pub get && flutter run

# Seed / create a test user
./create-test-user.sh
```

---

## AWS Resources

| Resource | Value |
|----------|-------|
| API Gateway URL | `https://3u10v51mvk.execute-api.us-east-1.amazonaws.com` |
| Lambda Function | `sam-app-WizGymApiFunction-yE1SQSAsdJGg` |
| DynamoDB Table | `wizgym-prod-core` |
| SSM Key path | `/wizgym/prod/OTPIQ_API_KEY` |
| AWS Profile | `wizgym-prod` |
| AWS Account | `940075378952` |
| Region | `us-east-1` |

---

## Brand Theme

| Token | Hex | Usage |
|-------|-----|-------|
| Primary green | `#00A68C` | Buttons, accents |
| Dark navy card | `#111C2E` | Card backgrounds |
| Surface high | `#1A2336` | Elevated surfaces |
| Text primary | `#EAF0FB` | Body text |
| Text secondary | `#8A96A8` | Labels, captions |
| Card pink | `#FF5C7A` | Accent cards |
| Card lavender | `#7C83FF` | Accent cards |

---

## Documentation Index

| File | Contents |
|------|----------|
| `docs/architecture.md` | System architecture |
| `docs/domain-model.md` | DynamoDB single-table design |
| `docs/api-map.md` | Full API endpoint reference |
| `docs/product-roadmap.md` | Feature backlog & milestones |
| `docs/aws-sam-lambda/DEPLOYMENT.md` | Lambda deployment deep-dive |
| `docs/OTPIQ_INTEGRATION_GUIDE.md` | OTPIQ integration details |
| `ADMIN_LOGIC_TLDR.md` | Admin role logic (quick read) |
| `ADMIN_LOGIC_AUTHORITIES.md` | Admin permission matrix |
| `ADMIN_LOGIC_VISUAL_GUIDE.md` | Admin flow diagrams |
