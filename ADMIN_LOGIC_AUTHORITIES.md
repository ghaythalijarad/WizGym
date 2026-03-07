# WizGym Admin Logic & Authorities Guide

## Table of Contents
1. [Admin Role Overview](#admin-role-overview)
2. [Admin Sign-In Flow](#admin-sign-in-flow)
3. [Admin Authorities & Permissions](#admin-authorities--permissions)
4. [Admin API Endpoints](#admin-api-endpoints)
5. [Admin Features & Operations](#admin-features--operations)
6. [Role-Based Access Control (RBAC)](#role-based-access-control-rbac)

---

## Admin Role Overview

### What is an ADMIN?
- **Platform Administrator**: Manages the entire WizGym platform
- **Super User**: Has exclusive permissions beyond regular users, trainers, and gym owners
- **Manual Account Creation**: Only admins can be created manually by platform developers

### Admin Account Creation Rules
```
✅ ALLOWED:  Manual creation via admin API endpoint
❌ BLOCKED:  Self-signup (app/mobile user cannot create admin account)
❌ BLOCKED:  OTP-based flow (not available for admin role)
❌ BLOCKED:  Password reset via OTP flow
```

---

## Admin Sign-In Flow

### Step-by-Step Login Process

```
┌─────────────────────────────────────────────────────────────┐
│ 1. USER SELECTS ADMIN ROLE IN AUTH GATE PAGE                │
│    - Locks UI to LOGIN ONLY (no signup option)              │
│    - Shows "Admin Login" label                              │
│    - Requires: Phone Number + Password                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. PHONE NORMALIZATION (Frontend)                           │
│    Input: 07xxxxxxxxx or +9647xxxxxxxxx                     │
│    Output: +9647xxxxxxxxx (Iraq format)                     │
│    - Removes non-digits                                     │
│    - Converts "00964" → "964"                               │
│    - Converts "07" → "9647"                                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. DIRECT LOGIN (No OTP for Admin)                          │
│    POST /auth/login                                         │
│    Body:                                                     │
│    {                                                         │
│      "phoneNumber": "+9647xxxxxxxxx",                       │
│      "role": "ADMIN",                                       │
│      "password": "at_least_6_chars"                         │
│    }                                                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. BACKEND VALIDATION                                       │
│    ├─ Normalize phone number                                │
│    ├─ Verify role is ADMIN                                  │
│    ├─ Find account: {phoneNumber, role: "ADMIN"}            │
│    ├─ Verify password hash (scrypt)                         │
│    └─ Check account exists                                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. RESPONSE (Success)                                       │
│    {                                                         │
│      "token": "JWT_ACCESS_TOKEN",                           │
│      "refreshToken": "JWT_REFRESH_TOKEN",                   │
│      "profile": {                                            │
│        "id": "admin-user-id",                               │
│        "phoneNumber": "+9647xxxxxxxxx",                     │
│        "displayName": "Admin Name",                         │
│        "role": "ADMIN"                                      │
│      }                                                       │
│    }                                                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. STORE SESSION (Frontend)                                 │
│    AuthSession:                                              │
│    ├─ token: Access JWT                                     │
│    ├─ refreshToken: Refresh JWT                             │
│    ├─ userId: Admin ID                                      │
│    ├─ phoneNumber: +9647xxxxxxxxx                           │
│    ├─ displayName: Admin Name                               │
│    └─ role: AppRole.admin                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. NAVIGATE TO ADMIN DASHBOARD                              │
│    - Loads AdminHomePage with role-specific navigation      │
│    - 4 tabs: Home, Gym Approval, Subscriptions, Analytics   │
└─────────────────────────────────────────────────────────────┘
```

### Key Login Differences: Admin vs Other Roles

| Feature | Admin | User/Trainer/Owner |
|---------|-------|------------------|
| **Sign-up** | ❌ Not allowed | ✅ Allowed |
| **OTP Flow** | ❌ Not used | ✅ Required for signup/reset |
| **Direct Login** | ✅ Phone + Password | ✅ Available |
| **Password Reset** | ❌ Not via OTP | ✅ Via OTP verification |
| **Auth Endpoint** | POST /auth/login | POST /auth/login |

---

## Admin Authorities & Permissions

### Role Hierarchy & Authorization

```
PERMISSIONS MATRIX
═════════════════════════════════════════════════════════════

RESOURCE                    ADMIN    OWNER    TRAINER    USER
─────────────────────────────────────────────────────────────
Gym Applications
├─ List                     ✅       ❌       ❌        ❌
├─ View                     ✅       ❌       ❌        ❌
├─ Approve                  ✅       ❌       ❌        ❌
├─ Reject                   ✅       ❌       ❌        ❌

Subscriptions
├─ View All                 ✅       ✅*      ❌        ❌
├─ Update Status            ✅       ❌       ❌        ❌
├─ Pause/Resume             ✅       ❌       ❌        ❌

Phone OTP Tracking
├─ View Provider Info       ✅       ❌       ❌        ❌
├─ Track SMS Delivery       ✅       ❌       ❌        ❌

User Management
├─ Create Users             ✅       ❌       ❌        ❌
├─ Reset Password           ❌       ❌       ❌        ❌

Dashboard
├─ View Admin Stats         ✅       ✅*      ❌        ❌
├─ View Metrics             ✅       ✅*      ❌        ❌

* = Own data only
```

---

## Admin API Endpoints

### 1. Dashboard Endpoint
```
GET /api/v1/admin/dashboard
Authorization: Bearer JWT_TOKEN
Role Required: ADMIN
```

**Response:**
```json
{
  "pendingGymApprovals": 3,
  "approvedGyms": 15,
  "activeSubscriptions": 12,
  "pausedSubscriptions": 2
}
```

**Logic:**
- Counts all PENDING gym applications
- Counts all APPROVED gym applications
- Counts subscriptions with status = ACTIVE
- Counts subscriptions with status = PAUSED

---

### 2. List Gyms Endpoint
```
GET /api/v1/admin/gyms?status=PENDING
Authorization: Bearer JWT_TOKEN
Role Required: ADMIN
```

**Query Parameters:**
- `status` (optional): PENDING | APPROVED | REJECTED

**Response:**
```json
[
  {
    "id": "gym-1001",
    "gymName": "Power Zone Fitness",
    "ownerName": "Ahmed Hassan",
    "ownerUserId": "owner-1001",
    "city": "Baghdad",
    "requestedAt": "2026-02-20T10:00:00Z",
    "status": "PENDING",
    "reviewNote": null,
    "reviewedAt": null
  },
  ...
]
```

**Backend Logic:**
```typescript
async listGyms(status?: GymApprovalStatus) {
  return this.mongo.gymApplications
    .find(status ? { status } : {})
    .sort({ requestedAt: -1 })
    .toArray();
}
```

---

### 3. Approve Gym Endpoint
```
POST /api/v1/admin/gyms/{gymId}/approve
Authorization: Bearer JWT_TOKEN
Role Required: ADMIN
```

**Response:**
```json
{
  "id": "gym-1001",
  "status": "APPROVED",
  "reviewedAt": "2026-02-24T14:30:00Z",
  "reviewNote": "Approved by admin-name",
  "message": "Gym approved successfully"
}
```

**Backend Logic:**
```typescript
async approveGym(gymId: string, reviewer: string) {
  // 1. Update gym application status to APPROVED
  const applicationResult = await this.mongo.gymApplications
    .findOneAndUpdate(
      { id: gymId },
      {
        $set: {
          status: 'APPROVED',
          reviewedAt: now,
          reviewNote: `Approved by ${reviewer}`,
          updatedAt: now,
        },
      }
    );

  // 2. Also create/update gym record
  await this.mongo.gyms.updateOne(
    { id: gymId },
    {
      $set: {
        applicationId: application.id,
        status: 'APPROVED',
        updatedAt: now,
      },
    }
  );

  return { status: 'APPROVED', reviewedAt, reviewNote };
}
```

---

### 4. Reject Gym Endpoint
```
POST /api/v1/admin/gyms/{gymId}/reject
Authorization: Bearer JWT_TOKEN
Role Required: ADMIN

Body:
{
  "note": "Missing required documents"
}
```

**Response:**
```json
{
  "id": "gym-1001",
  "status": "REJECTED",
  "reviewedAt": "2026-02-24T14:30:00Z",
  "reviewNote": "Missing required documents - Rejected by admin-name",
  "message": "Gym rejected"
}
```

---

### 5. View Subscriptions Endpoint
```
GET /api/v1/admin/subscriptions
Authorization: Bearer JWT_TOKEN
Role Required: ADMIN
```

**Response:**
```json
[
  {
    "id": "sub-501",
    "gymId": "gym-1003",
    "gymName": "Iron Core Club",
    "planName": "Business Pro",
    "membersLimit": 1500,
    "monthlyPrice": 1299,
    "nextBillingDate": "2026-03-01T00:00:00Z",
    "status": "ACTIVE"
  },
  ...
]
```

---

### 6. Update Subscription Status Endpoint
```
PATCH /api/v1/admin/subscriptions/{subscriptionId}/status
Authorization: Bearer JWT_TOKEN
Role Required: ADMIN

Body:
{
  "status": "PAUSED"  // ACTIVE | PAUSED | CANCELED
}
```

**Response:**
```json
{
  "id": "sub-501",
  "status": "PAUSED",
  "message": "Subscription status updated",
  "updatedAt": "2026-02-24T14:30:00Z"
}
```

---

### 7. Get OTP Provider Info Endpoint
```
GET /api/v1/auth/phone/provider-info
Authorization: Bearer JWT_TOKEN
Role Required: ADMIN
```

**Response:**
```json
{
  "projectName": "WizGym OTP Project",
  "credit": 9850,
  "mocked": false
}
```

**Purpose:** Check OTP service provider balance and status

---

### 8. Track OTP Delivery Endpoint
```
GET /api/v1/auth/phone/track/:sessionId
Authorization: Bearer JWT_TOKEN
Role Required: ADMIN
```

**Response:**
```json
{
  "sessionId": "session-123",
  "phoneNumber": "+9647xxxxxxxxx",
  "internalStatus": "VERIFIED",
  "provider": "otpiq",
  "providerStatus": {
    "smsId": "sms-456",
    "status": "DELIVERED",
    "isFinalStatus": true,
    "lastChannel": "SMS"
  },
  "createdAt": "2026-02-24T14:00:00Z",
  "updatedAt": "2026-02-24T14:05:00Z"
}
```

---

### 9. Create User Endpoint (Admin Only)
```
POST /api/v1/admin/users
Authorization: Bearer JWT_TOKEN
Role Required: ADMIN

Body:
{
  "phoneNumber": "+9647xxxxxxxxx",
  "role": "USER",  // USER | TRAINER | OWNER (not ADMIN)
  "password": "secure_password_min_6",
  "displayName": "User Name"
}
```

**Response:**
```json
{
  "id": "user-1001",
  "phoneNumber": "+9647xxxxxxxxx",
  "displayName": "User Name",
  "role": "USER",
  "createdAt": "2026-02-24T14:30:00Z"
}
```

**Important Rule:**
- Admin cannot create other ADMIN accounts via this endpoint
- Throws: `BadRequestException('ADMIN accounts must be managed manually')`

---

## Role-Based Access Control (RBAC)

### How RBAC Works in WizGym Backend

#### 1. Decorator Pattern
```typescript
// Mark endpoint with required role
@Controller('admin')
@Roles(Role.ADMIN)
export class AdminController {
  
  @Post('gyms/:gymId/approve')
  approveGym(@Param('gymId') gymId: string) {
    // Only accessible to ADMIN role
  }
}
```

#### 2. Roles Guard (Middleware)
```typescript
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    // Get required roles from decorator
    const requiredRoles = this.reflector.getAllAndOverride<Role[]>(
      ROLES_KEY,
      [context.getHandler(), context.getClass()]
    );

    // No roles specified = endpoint is public
    if (!requiredRoles || requiredRoles.length === 0) {
      return true;
    }

    // Extract user role from JWT token
    const request = context.switchToHttp().getRequest();
    const userRole: Role | undefined = request.user?.role;

    // Check if user role is in required roles
    if (!userRole || !requiredRoles.includes(userRole)) {
      throw new ForbiddenException('Insufficient role for this endpoint');
    }

    return true;
  }
}
```

#### 3. Request User Extraction
```typescript
// CurrentUser decorator extracts JWT claims
@CurrentUser() user: RequestUser
// Provides: user.id, user.name, user.role, user.phoneNumber
```

#### 4. Multiple Roles Support
```typescript
@Get('data')
@Roles(Role.ADMIN, Role.OWNER)  // Multiple roles allowed
getSharedData() {
  // Both ADMIN and OWNER can access
}
```

---

## Admin Features & Operations

### 1. Gym Application Approval Workflow

```
GYM OWNER SUBMITS APPLICATION
        ↓
ADMIN REVIEWS IN DASHBOARD
        ↓
     APPROVE?
     /      \
   YES      NO
   ↓         ↓
APPROVED  REJECTED
   ↓         ↓
GYM      OWNER
ACTIVE   NOTIFIED
   ↓
GYM APPEARS
IN MARKETPLACE
```

### 2. Subscription Management Workflow

```
GYM OWNER PURCHASES SUBSCRIPTION
        ↓
ADMIN VIEWS IN DASHBOARD
        ↓
MONITOR ACTIVE/PAUSED
        ↓
    NEED ACTION?
    /          \
  YES          NO
   ↓           ↓
PAUSE/RESUME  CONTINUE
   ↓
UPDATE STATUS
```

### 3. OTP Monitoring (Debug Only)

```
USER REQUESTS OTP FOR LOGIN
        ↓
BACKEND SENDS VIA OTPIQ
        ↓
ADMIN CAN TRACK DELIVERY
        ↓
VIEW SMS STATUS
├─ Delivery Status
├─ Provider Response
├─ Channel Used (SMS/etc)
└─ Timestamp
```

---

## Admin Flutter App UI

### Admin Home Page
**Location:** `apps/mobile/lib/features/admin/admin_home_page.dart`

```dart
class AdminHomePage extends StatefulWidget {
  // Fetches admin dashboard summary
  // Displays metric cards:
  // - Pending gym approvals
  // - Approved gyms
  // - Active subscriptions
  // - Paused subscriptions
}
```

### Gym Approval Page
**Location:** `apps/mobile/lib/features/admin/gym_approval_page.dart`

```dart
class GymApprovalPage extends StatefulWidget {
  // Fetches pending gym applications
  // Shows approval cards with:
  // - Gym name, owner, city
  // - Application details
  // - Approve/Reject buttons
  // - Optional review note
}
```

### Subscription Management Page
**Location:** `apps/mobile/lib/features/admin/subscription_management_page.dart`

```dart
class SubscriptionManagementPage extends StatefulWidget {
  // Fetches all platform subscriptions
  // Allows admin to:
  // - View all subscriptions
  // - Pause subscriptions
  // - Resume subscriptions
  // - View billing details
}
```

---

## Security & Validation

### Password Security
```typescript
// Passwords are hashed using scrypt
// Format: scrypt(password, salt, cost=32768)
// Never stored in plain text
// Verified using timing-safe comparison

const passwordHash = scryptSync(password, salt, 32768);
const isValid = timingSafeEqual(
  passwordHash,
  storedHash
);
```

### Phone Number Normalization
```typescript
// Always normalized to +964XXXXXXXXX format
// Prevents duplicate accounts with different formats
// Examples:
// "07xxxxxxxxx" → "+9647xxxxxxxxx"
// "00967xxxxxxxxx" → "+9647xxxxxxxxx"
// "+9647xxxxxxxxx" → "+9647xxxxxxxxx"
```

### Token-Based Auth
```typescript
// Uses JWT tokens
// Access Token: Short-lived (typically 15 min)
// Refresh Token: Long-lived (typically 7 days)
// Sent in Authorization header:
// Authorization: Bearer {access_token}
```

---

## Admin Account Creation (Manual Process)

### For Developers Only
```bash
# Via Admin API endpoint
POST /api/v1/admin/users
Content-Type: application/json

{
  "phoneNumber": "+9647901234567",
  "role": "ADMIN",
  "password": "SecurePassword123",
  "displayName": "Platform Administrator"
}

# But... this endpoint rejects ADMIN role!
# Throw: BadRequestException('ADMIN accounts must be managed manually')
```

### Manual Creation Methods

1. **DynamoDB Direct Insert**: Use the AWS CLI or the `create-test-user.sh` script to insert an admin record directly into the `wizgym-prod-core` table.
2. **Seed Script**: Run `./create-test-user.sh` from the repo root to create a test admin user.
3. **Lambda Service Call**: Trigger the admin-creation logic via a direct Lambda invocation (not via REST API).

### Example Seed Data

> Admin accounts are stored in DynamoDB (`wizgym-prod-core`). Use `./create-test-user.sh` or insert a record directly with the AWS CLI (`aws dynamodb put-item --profile wizgym-prod --region us-east-1 ...`). There is no `apps/backend` — it was deleted.

---

## Error Handling for Admin

### Common Admin Errors

| Error | Code | Cause | Solution |
|-------|------|-------|----------|
| Unauthorized | 401 | Missing/invalid JWT | Re-login |
| Forbidden | 403 | Non-ADMIN trying admin endpoint | Login as ADMIN |
| Not Found | 404 | Gym/subscription ID doesn't exist | Verify ID |
| Bad Request | 400 | Invalid request data | Check request format |
| Account Not Found | 401 | Admin account not in DB | Create account manually |

---

## Summary Table

| Aspect | Details |
|--------|---------|
| **Sign-In Method** | Direct login (phone + password) |
| **OTP Required** | ❌ No |
| **Role in Auth** | Must select "Admin" role |
| **Password Reset** | ❌ Not via OTP flow |
| **Account Creation** | ✅ Manual only (not via signup) |
| **Dashboard** | View platform metrics |
| **Gym Approvals** | Approve/reject gym applications |
| **Subscriptions** | View and manage gym subscriptions |
| **User Management** | Create users (except other ADMINs) |
| **OTP Tracking** | Monitor SMS delivery (debug only) |
| **Role Scope** | Platform-wide (all gyms, users, etc) |

---

## Testing Admin Flows

### Test Credentials (Local Development)
```
Phone: +9647700000001
Role: ADMIN
Password: admin123456  (example - must be ≥6 chars)
```

### Test Cases
1. ✅ Login with correct admin credentials
2. ❌ Attempt signup as admin (should block)
3. ✅ View pending gym approvals
4. ✅ Approve a gym application
5. ✅ Reject a gym application with note
6. ✅ View all subscriptions
7. ✅ Pause a subscription
8. ✅ Create non-admin user account
9. ❌ Attempt to create admin account (should fail)
10. ✅ Track OTP delivery status

