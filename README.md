# GymOS

Arabic-first, cross-platform gym management ecosystem for four roles:
- Platform Admin
- Gym Owners
- Trainers
- Users (Members)

All project apps, packages, and docs are contained under this single main folder:
`/Users/ghaythallaheebi/Handlesensitiveinformation`

This repository is a v1 execution scaffold with:
- `apps/mobile`: Flutter app shell (RTL Arabic UX, role-based navigation)
- `apps/backend`: NestJS backend foundation (RBAC, modular architecture)
- `packages/contracts`: shared TypeScript contracts
- `docs`: architecture and product docs

## Quick Start

### 1) Mobile (Flutter)
```bash
cd /Users/ghaythallaheebi/Handlesensitiveinformation/apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:3000/api/v1/
```

### 2) Backend (NestJS)
```bash
cd /Users/ghaythallaheebi/Handlesensitiveinformation
docker compose up -d mongodb redis
cd /Users/ghaythallaheebi/Handlesensitiveinformation/apps/backend
npm install
npm run db:migrate
npm run db:seed
npm run start:dev
```

### 3) Shared contracts
```bash
cd /Users/ghaythallaheebi/Handlesensitiveinformation/packages/contracts
npm install
npm run build
```

## Initial APIs
- `GET /health`
- `POST /auth/signup`
- `POST /auth/login`
- `POST /auth/phone/send-otp`
- `POST /auth/phone/verify-otp`
- `GET /auth/phone/provider-info`
- `GET /auth/phone/track/:sessionId`
- `GET /gyms/public`
- `GET /gyms/owner/mine`
- `POST /gyms/:gymId/join`
- `POST /gyms/:gymId/trainers/join`
- `POST /gyms/:gymId/trainers/:trainerId/hire`
- `POST /gyms/:gymId/ratings`
- `PATCH /gyms/:gymId/profile`
- `POST /trainers/:trainerId/ratings`
- `GET /users/me`
- `GET /admin/dashboard`
- `GET /admin/gyms/pending`
- `POST /admin/gyms/:gymId/approve`
- `POST /admin/gyms/:gymId/reject`
- `GET /admin/subscriptions`
- `PATCH /admin/subscriptions/:subscriptionId/status`
- `GET /gyms/owner/dashboard`
- `GET /trainers/me/clients`
- `GET /trainers/me/gyms`
- `GET /members/me/plan`

Role can be simulated via request header:
- `x-user-role: ADMIN`
- `x-user-role: OWNER`
- `x-user-role: TRAINER`
- `x-user-role: USER`

Auth is phone-number based only (no email/password): request OTP -> verify OTP -> signup/login with `phoneNumber`.
