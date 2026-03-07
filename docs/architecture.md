# WizGym Architecture

## Vision
Unified platform for platform admins, gym owners, trainers, and members with Arabic-first UX and role-driven capabilities.

## System Components
- Mobile client: Flutter (`apps/mobile`)
- Backend API: AWS Lambda + TypeScript (`apps/api`) — deployed via AWS SAM
- Admin dashboard: Static HTML/JS (`apps/admin-dashboard`)
- Shared contracts: TypeScript interfaces (`packages/contracts`)
- Data store: DynamoDB single-table (`wizgym-prod-core`)
- OTP delivery: OTPIQ service (WhatsApp/SMS) via API key in SSM Parameter Store

> `apps/backend` (NestJS/MongoDB) has been removed. The only backend is `apps/api`.

## Role-Based Capability Matrix

### Platform Admin
- Gym onboarding approval and compliance review
- Platform subscription lifecycle control (active/paused/canceled)
- Cross-tenant monitoring and audit visibility

### Owner
- Branch and staff oversight
- Membership lifecycle management
- Revenue and retention analytics
- Campaign and notification orchestration
- Publish gym facilities and product advertisements
- Configure gym audience (men-only, women-only, mixed) and amenities

### Trainer
- Client roster and adherence monitoring
- Training plan templates and progress tracking
- Session scheduling and reminders
- Can join up to 4 gyms at a time

### User
- Membership overview
- Class and PT booking
- Program adherence and streak tracking
- Discover gyms, join gyms, hire trainers, and rate gyms/trainers
- Discover gym audience and amenities (food bar, sauna, etc.)

## API Security Model
- JWT auth (planned, mock guard in current scaffold)
- RBAC through `@Roles(...)` and `RolesGuard`
- Tenant isolation per gym/branch (planned)
- Phone-only authentication via OTP (no email/password)
- OTPIQ-based SMS/WhatsApp OTP delivery (server-side generation/validation)

## Implemented Persistence
- Platform admin workflows (gym approvals and platform subscriptions) are persisted via MongoDB collections:
  - `gymApplications`
  - `platformSubscriptions`
- Gym marketplace workflows are persisted via MongoDB collections:
  - `Gym`
  - `GymMembership`
  - `GymTrainerMembership` (with max 4 active gyms per trainer enforced in service layer)
  - `TrainerHire`
  - `GymRating`
  - `TrainerRating`
  - `GymFacility`
  - `GymProduct`

## Arabic-First UI Standards
- RTL direction by default
- Arabic labels for core navigation and workflows
- Locale-aware dates and number formatting (planned)

## Deployment Blueprint
- Containers: API and workers
- Observability: OpenTelemetry traces, structured logs, metrics
- CI/CD: lint, test, build, deploy per app
- Custom/self-hosted stack (non-AWS):
  - Docker Compose for local and staging
  - MongoDB + Redis as core data services
  - Reverse proxy/load balancer in front of API (Nginx/Traefik)

## Suggested Next Build Steps
1. Add production MongoDB hardening (replica set, backups, observability).
2. Replace mock auth guard with JWT strategy.
3. Add persistent entities for users, gyms, memberships, bookings.
4. Integrate payment providers and webhook handling.
5. Add push notification worker and analytics jobs.
