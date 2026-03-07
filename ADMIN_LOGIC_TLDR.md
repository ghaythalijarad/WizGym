# Admin Logic Summary - TL;DR

## How Admin Sign-In Works (Quick Version)

### Login Flow
```
SELECT ADMIN ROLE
    ↓
ENTER PHONE + PASSWORD (no OTP)
    ↓
POST /auth/login with role="ADMIN"
    ↓
BACKEND VALIDATES & RETURNS JWT
    ↓
ADMIN LOGGED IN → ADMIN DASHBOARD
```

### Key Difference from Other Roles
- ❌ **No OTP** - Direct login only (phone + password)
- ❌ **No Signup** - Must be created manually by developers
- ❌ **No Self-Service Password Reset** - Admin-only feature
- ✅ **Direct Phone+Password Auth** - Like traditional login

---

## Admin Authorities (What Can Admin Do?)

### 📋 Gym Management
- ✅ View ALL gym applications (pending, approved, rejected)
- ✅ Approve gyms (activates them in marketplace)
- ✅ Reject gyms (with optional review notes)

### 💳 Subscription Management
- ✅ View ALL gym subscriptions
- ✅ Pause subscriptions (blocks new memberships)
- ✅ Resume subscriptions (reactivates)
- ✅ Update subscription status

### 👥 User Management
- ✅ Create user accounts (USER, TRAINER, OWNER roles)
- ❌ Cannot create other ADMIN accounts via API

### 🔍 OTP Monitoring (Debug Only)
- ✅ View SMS provider info (balance, status)
- ✅ Track OTP delivery status
- ✅ Monitor SMS delivery channels

### 📊 Dashboard
- ✅ View real-time metrics:
  - Count of pending gym approvals
  - Count of approved gyms
  - Count of active subscriptions
  - Count of paused subscriptions

---

## Admin API Endpoints (All Require ADMIN Role)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/admin/dashboard` | GET | View admin dashboard metrics |
| `/admin/gyms` | GET | List gym applications (filterable) |
| `/admin/gyms/{id}/approve` | POST | Approve a gym |
| `/admin/gyms/{id}/reject` | POST | Reject a gym |
| `/admin/subscriptions` | GET | View all subscriptions |
| `/admin/subscriptions/{id}/status` | PATCH | Update subscription status |
| `/admin/users` | POST | Create user account |
| `/auth/phone/provider-info` | GET | Get OTP provider status |
| `/auth/phone/track/{sessionId}` | GET | Track OTP delivery |

---

## Admin Account Creation

### How to Create Admin Account?
```
❌ CANNOT: Via app signup
❌ CANNOT: Via REST API /admin/users endpoint
✅ CAN: Manual database insert
✅ CAN: Seed script during deployment
✅ CAN: Backend service (private method)
```

### Why Manual Only?
- **Security**: Prevents unauthorized admin creation
- **Control**: Only developers/sysadmins can create
- **Audit**: Requires direct database access

### Example: Manual Creation (Database)

> Admin accounts are managed manually (no public API). Use a direct database insert via the current persistence layer.

- If using Prisma-backed storage, insert via Prisma/SQL.
- If using DynamoDB-backed storage, insert via AWS CLI/console or an internal seed.

(Old MongoDB example removed.)

---

## Role-Based Access Control (RBAC)

### How It Works
```
1. DECORATOR on endpoint
   @Roles(Role.ADMIN)
   
2. GUARD middleware checks
   Is user role in @Roles()?
   
3. JWT TOKEN extracted
   User role from JWT claims
   
4. ALLOW or FORBID
   ✅ YES → Request proceeds
   ❌ NO → 403 Forbidden error
```

### Example Permission Matrix
```
                  ADMIN  OWNER  TRAINER  USER
Gym Approval      ✅     ❌     ❌      ❌
Subscriptions     ✅     ✅*    ❌      ❌
OTP Tracking      ✅     ❌     ❌      ❌
Create Users      ✅     ❌     ❌      ❌
Marketplace       ✅     ✅     ✅      ✅

* = Own data only
```

---

## Admin Flutter App Pages

### 1. Admin Home Page
- **Location**: `features/admin/admin_home_page.dart`
- **Shows**: 4 metric cards
  - Pending gym approvals
  - Approved gyms
  - Active subscriptions
  - Paused subscriptions

### 2. Gym Approval Page
- **Location**: `features/admin/gym_approval_page.dart`
- **Shows**: List of gym applications
- **Actions**: Approve/Reject buttons
- **Filter**: By status (pending/approved/rejected)

### 3. Subscription Management Page
- **Location**: `features/admin/subscription_management_page.dart`
- **Shows**: All gym subscriptions
- **Actions**: Pause/Resume buttons
- **Info**: Plan, price, members, billing date

---

## Admin Login Step-by-Step

```
STEP 1: Open App → Select "Admin" Role
   • Auth Gate Page locks to LOGIN MODE
   • Shows "تسجيل دخول المدير" (Admin Login)
   
STEP 2: Enter Credentials
   • Phone number: +9647xxxxxxxxx
   • Password: (min 6 chars)
   
STEP 3: No OTP
   • Skip OTP screen (unique to admin)
   • Directly verify password
   
STEP 4: Backend Check
   • Find account: {phoneNumber, role: ADMIN}
   • Verify password hash (scrypt algorithm)
   • Check if account exists
   
STEP 5: JWT Token Response
   • Return access token (JWT)
   • Return refresh token (JWT)
   • Include user profile
   
STEP 6: Store Session
   • Save token in AuthSession object
   • Save userId, phoneNumber, displayName, role
   
STEP 7: Navigate to Admin Dashboard
   • Load AdminHomePage
   • Show role-based navigation (4 tabs)
   • Display dashboard metrics
```

---

## Common Admin Tasks

### Task 1: Approve a Pending Gym
```
1. Login as admin
2. Go to "Gym Approval" tab
3. See list of pending gyms
4. Click "Approve" on gym
5. Gym now visible in marketplace
6. Owner gets notification (if implemented)
```

### Task 2: Pause Subscription
```
1. Go to "Subscriptions" tab
2. Find gym subscription
3. Click "Pause"
4. New memberships blocked
5. Existing members can still view
6. Can resume anytime
```

### Task 3: Create User Account
```
1. Use POST /admin/users endpoint
2. Provide: phone, role, password, displayName
3. Backend creates account
4. User can now login
5. Cannot create ADMIN accounts this way!
```

### Task 4: Track OTP Delivery (Debug)
```
1. Get SMS session ID from OTP attempt
2. Call GET /auth/phone/track/{sessionId}
3. View:
   - SMS delivery status
   - Provider response
   - Channel used
   - Timestamps
```

---

## Security Measures

### Password Hashing
- Algorithm: **scrypt**
- Cost: 32768 iterations
- Salt: Cryptographically random
- Never stored plain text
- Verification: Timing-safe comparison

### JWT Tokens
- **Access Token**: Short-lived (typically 15 min)
- **Refresh Token**: Long-lived (typically 7 days)
- **Claims**: User ID, role, phone, name
- **Header**: `Authorization: Bearer {token}`

### Phone Normalization
- All formats → `+964XXXXXXXXX`
- Examples:
  - `07xxxxxxxxx` → `+9647xxxxxxxxx`
  - `00967xxxxxxxxx` → `+9647xxxxxxxxx`
- Prevents duplicate accounts

### Role-Based Guards
- Every endpoint checks role
- @Roles(Role.ADMIN) decorator
- RolesGuard middleware validation
- Returns 403 Forbidden if unauthorized

---

## Differences: Admin vs Other Roles

| Aspect | Admin | Other Roles |
|--------|-------|------------|
| **Signup** | ❌ Manual only | ✅ Self-service |
| **OTP** | ❌ Not used | ✅ Required |
| **Login Method** | Direct (phone+pwd) | Phone+pwd OR OTP |
| **Password Reset** | Manual only | Via OTP |
| **Scope** | Platform-wide | Own data |
| **Gym Management** | ALL gyms | Own gym |
| **User Creation** | ✅ Can create | ❌ Cannot |

---

## Troubleshooting Admin Issues

### Problem: Admin Login Fails
**Cause**: Account not in database
**Solution**: Create account manually (database insert)

### Problem: Password Reset Not Working
**Cause**: Admin password reset via OTP not allowed
**Solution**: Manual database update or developer intervention

### Problem: Cannot Create User Account
**Cause**: Missing POST /admin/users endpoint access
**Solution**: Ensure logged in as ADMIN role

### Problem: "Insufficient role for this endpoint"
**Cause**: User role doesn't match @Roles() requirement
**Solution**: Login as correct role (ADMIN)

---

## Admin Features Roadmap

### ✅ Already Implemented
- Direct phone+password login
- Gym application approval/rejection
- Subscription status management
- User account creation (non-admin)
- OTP delivery tracking
- Dashboard metrics

### 🔄 In Progress / Pending
- Advanced analytics dashboard
- User behavior reports
- Subscription billing reports
- Gym performance metrics
- Trainer performance tracking
- System activity logs

### 📋 Future Features
- Bulk operations (approve multiple gyms)
- Scheduled reports
- Admin activity audit log
- Multi-admin support with permissions
- Admin role sub-roles (e.g., content manager, finance)

---

## Quick Reference: Admin Login vs Regular Login

### Admin Login
```
POST /auth/login
{
  "phoneNumber": "+9647xxxxxxxxx",
  "role": "ADMIN",
  "password": "password123"
}
```

### Regular User Login
```
POST /auth/login
{
  "phoneNumber": "+9647xxxxxxxxx",
  "role": "USER",  // or TRAINER or OWNER
  "password": "password123"
}
```

### Regular User Signup (with OTP)
```
STEP 1: POST /auth/phone/send-otp
STEP 2: POST /auth/phone/verify-otp
STEP 3: POST /auth/signup
```

### Admin Signup
```
❌ NOT ALLOWED
Must create manually via database or seed script
```

---

## Key Takeaways

1. **Admin Login** = Direct phone + password (NO OTP)
2. **Admin Account** = Manual creation only (security)
3. **Admin Scope** = Platform-wide (all gyms, users, data)
4. **Admin Powers** = Approve gyms, manage subscriptions, create users
5. **Admin Security** = RBAC guards, JWT tokens, scrypt hashing
6. **Admin UI** = 4-tab navigation (Home, Approval, Subscriptions, Analytics)

---

## Need More Details?

See full documentation:
- **`ADMIN_LOGIC_AUTHORITIES.md`** - Comprehensive guide with all endpoints
- **`ADMIN_LOGIC_VISUAL_GUIDE.md`** - Diagrams and visual explanations
- **`SCREEN_FUNCTIONS_COMPREHENSIVE.md`** - All screen functions
- **`SCREEN_FUNCTIONS_QUICK_REFERENCE.md`** - Quick visual reference

