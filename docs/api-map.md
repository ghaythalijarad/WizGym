# API Map (v1 Scaffold)

Base URL: `/api/v1`

Auth rule: signup/login are phone-number based only (no email/password).

## Public/Auth
- `POST /auth/signup` (phone + recently verified OTP)
- `POST /auth/login` (phone + recently verified OTP)
- `POST /auth/phone/send-otp`
- `POST /auth/phone/verify-otp`
- `GET /auth/phone/provider-info` (ADMIN)
- `GET /auth/phone/track/:sessionId` (ADMIN)

## Core
- `GET /health`
- `GET /users/me`

## Gym Discovery and Membership
- `GET /gyms/public` (optional query: `city`, `audience`)
- `GET /gyms/:gymId/public`
- `POST /gyms/:gymId/join` (USER)
- `POST /gyms/:gymId/trainers/join` (TRAINER, max 4 active gyms)
- `GET /gyms/:gymId/trainers` (USER/TRAINER/OWNER/ADMIN)
- `POST /gyms/:gymId/trainers/:trainerId/hire` (USER)

## Ratings
- `POST /gyms/:gymId/ratings` (USER)
- `GET /gyms/:gymId/ratings`
- `POST /trainers/:trainerId/ratings` (USER)
- `GET /trainers/:trainerId/ratings`

## Gym Products and Facilities
- `GET /gyms/:gymId/facilities/public`
- `POST /gyms/:gymId/facilities` (OWNER)
- `GET /gyms/:gymId/products/public`
- `POST /gyms/:gymId/products` (OWNER)
- `PATCH /gyms/:gymId/profile` (OWNER: audience + amenities)

## Platform Admin
- `GET /admin/dashboard` (ADMIN)
- `GET /admin/gyms` (ADMIN)
- `GET /admin/gyms/pending` (ADMIN)
- `POST /admin/gyms/:gymId/approve` (ADMIN)
- `POST /admin/gyms/:gymId/reject` (ADMIN)
- `GET /admin/subscriptions` (ADMIN)
- `PATCH /admin/subscriptions/:subscriptionId/status` (ADMIN)

## Owner
- `GET /gyms/owner/dashboard` (OWNER)
- `GET /gyms/owner/mine` (OWNER)
- `GET /analytics/retention` (OWNER)

## Trainer
- `GET /trainers/me/clients` (TRAINER)
- `GET /trainers/me/gyms` (TRAINER)

## Member/User
- `GET /members/me/plan` (USER)
- `GET /bookings/summary`
- `GET /classes/today`

## Platform
- `GET /plans/templates`
- `GET /payments/methods`
- `GET /notifications/channels`
