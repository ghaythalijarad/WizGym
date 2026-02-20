# GymOS Backend

## Start
```bash
cp .env.example .env
cd /Users/ghaythallaheebi/Handlesensitiveinformation
docker compose up -d mongodb redis
cd /Users/ghaythallaheebi/Handlesensitiveinformation/apps/backend
npm install
npm run db:migrate
npm run db:seed
npm run start:dev
```

## Base URL
`http://localhost:3000/api/v1`

## Role Simulation
Use request headers:
- `x-user-role: ADMIN | OWNER | TRAINER | USER`
- `x-user-id: any-id`
- `x-user-name: display-name`

## Current Modules
- admin
- auth
- users
- gyms
- trainers
- memberships
- bookings
- classes
- plans
- payments
- analytics
- notifications

## Admin Dashboard Endpoints
- `GET /admin/dashboard`
- `GET /admin/gyms`
- `GET /admin/gyms/pending`
- `POST /admin/gyms/:gymId/approve`
- `POST /admin/gyms/:gymId/reject`
- `GET /admin/subscriptions`
- `PATCH /admin/subscriptions/:subscriptionId/status`

## Gym and Trainer Marketplace Endpoints
- `GET /gyms/public` (optional query: `city`, `audience`)
- `GET /gyms/:gymId/public`
- `GET /gyms/owner/mine` (OWNER)
- `POST /gyms/:gymId/join` (USER)
- `POST /gyms/:gymId/trainers/join` (TRAINER, max 4 gyms)
- `GET /gyms/:gymId/trainers`
- `POST /gyms/:gymId/trainers/:trainerId/hire` (USER)
- `POST /gyms/:gymId/ratings` (USER)
- `GET /gyms/:gymId/ratings`
- `POST /trainers/:trainerId/ratings` (USER)
- `GET /trainers/:trainerId/ratings`
- `GET /trainers/me/gyms` (TRAINER)
- `GET /gyms/:gymId/facilities/public`
- `POST /gyms/:gymId/facilities` (OWNER)
- `GET /gyms/:gymId/products/public`
- `POST /gyms/:gymId/products` (OWNER)
- `PATCH /gyms/:gymId/profile` (OWNER: audience + amenities)

## Phone Verification Endpoints
- `POST /auth/phone/send-otp`
- `POST /auth/phone/verify-otp`
- `POST /auth/signup` (phone + recently verified OTP)
- `POST /auth/login` (phone + recently verified OTP)
- `GET /auth/phone/provider-info` (ADMIN)
- `GET /auth/phone/track/:sessionId` (ADMIN)

Auth flow:
1. Call `POST /auth/phone/send-otp`.
2. Call `POST /auth/phone/verify-otp` with the code.
3. Call `POST /auth/signup` once (new account) or `POST /auth/login` (existing account) using only `phoneNumber`.

### Environment
- `MONGODB_URI`
- `MONGODB_DB_NAME`
- `OTPIQ_API_KEY`
- `OTPIQ_BASE_URL` (default `https://api.otpiq.com/api`)
- `OTPIQ_PROVIDER` (default `whatsapp-sms`)
- `OTPIQ_SENDER_ID` (optional)
- `OTPIQ_TIMEOUT_MS`
- `OTPIQ_MOCK_MODE` (`true` enables local mock delivery when key is missing)
- `PHONE_OTP_LENGTH`
- `PHONE_OTP_TTL_SECONDS`
- `PHONE_OTP_MAX_ATTEMPTS`
- `PHONE_OTP_RATE_LIMIT_SECONDS`

### Request Examples
```json
{
  "phoneNumber": "+9647XXXXXXXXX"
}
```

Gym profile update payload example (`PATCH /gyms/:gymId/profile`):
```json
{
  "audience": "WOMEN_ONLY",
  "amenities": ["Food Bar", "Sauna", "Steam Room"],
  "description": "Private ladies-only studio with wellness area."
}
```

```json
{
  "phoneNumber": "+9647XXXXXXXXX",
  "code": "123456"
}
```

```json
{
  "phoneNumber": "+9647XXXXXXXXX",
  "role": "USER",
  "displayName": "Ghayth"
}
```

```json
{
  "phoneNumber": "+9647XXXXXXXXX"
}
```

## Persistence
- Admin gym approvals and subscription updates are persisted in MongoDB.
- Seed data is loaded through `npm run db:seed`.
- Phone OTP sessions are persisted in MongoDB and validated server-side.
- Gym discovery, joins, trainer hiring, ratings, facilities, and product ads are persisted in MongoDB.
- Gym profile audience is persisted as `MEN_ONLY | WOMEN_ONLY | MIXED`.
- Gym amenities are persisted as a string list (examples: `Food Bar`, `Sauna`, `Steam Room`).
