# Admin Logic - Quick Visual Guide

## 🔐 Admin Sign-In Flow (Visual)

```
┌─────────────────────────────────────────────────────────────┐
│                     APP STARTUP                             │
│              User selects "ADMIN" role                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              AUTH GATE PAGE                                  │
│  • Mode locked to LOGIN only (no signup option)             │
│  • Phone input + Password input                             │
│  • Button: "تسجيل دخول المدير" (Admin Login)               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
         ┌──────────────────────────┐
         │ Normalize Phone Number   │
         │ +9647xxxxxxxxx          │
         └──────────────┬───────────┘
                        │
                        ▼
    ┌─────────────────────────────────────┐
    │   POST /auth/login                  │
    │   {                                 │
    │     phoneNumber: "+9647...",        │
    │     role: "ADMIN",                  │
    │     password: "min_6_chars"         │
    │   }                                 │
    └──────────────┬──────────────────────┘
                   │
                   ▼
    ┌──────────────────────────────────────┐
    │  BACKEND VERIFICATION                │
    │  1. Normalize phone                  │
    │  2. Find account by phone + role     │
    │  3. Verify password hash (scrypt)    │
    │  4. Check account exists             │
    └──────────────┬───────────────────────┘
                   │
         ┌─────────┴─────────┐
         │                   │
      SUCCESS            FAIL
         │                   │
         ▼                   ▼
    ┌─────────────┐    ┌─────────────┐
    │ Return JWT  │    │ 401 Error   │
    │ Token +     │    │ Retry login │
    │ Session     │    └─────────────┘
    └──────┬──────┘
           │
           ▼
    ┌────────────────────────────┐
    │  STORE AUTHSESSION         │
    │  • token                   │
    │  • refreshToken            │
    │  • userId                  │
    │  • phoneNumber             │
    │  • displayName             │
    │  • role: AppRole.admin     │
    └──────┬─────────────────────┘
           │
           ▼
    ┌────────────────────────────┐
    │ NAVIGATE TO ADMIN SHELL    │
    │ (Role Shell Navigation)    │
    │                            │
    │ 4 Tabs:                    │
    │ 1. Home (Dashboard)        │
    │ 2. Gym Approval            │
    │ 3. Subscriptions           │
    │ 4. Analytics               │
    └────────────────────────────┘
```

---

## 📊 Admin Authorities Diagram

```
┌──────────────────────────────────────────────────┐
│                  ADMIN ROLE                       │
│           (RBAC Authorization)                   │
└──────────────────────────┬───────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
    ┌─────────┐      ┌──────────┐     ┌──────────────┐
    │   GYM   │      │   USER   │     │ PLATFORM     │
    │ MGMT    │      │ MGMT     │     │ OPERATIONS   │
    └────┬────┘      └────┬─────┘     └──────┬───────┘
         │                │                  │
         ▼                ▼                  ▼
    ┌─────────────────────────────────────────────┐
    │ • List gym applications (all)               │
    │ • Approve gyms (→ active in marketplace)    │
    │ • Reject gyms (with notes)                  │
    │ • View all subscriptions (all gyms)         │
    │ • Pause/Resume subscriptions                │
    │ • Create user accounts (not ADMIN)          │
    │ • Track OTP delivery (SMS monitoring)       │
    │ • View provider info (SMS balance)          │
    │ • Dashboard metrics (real-time)             │
    └─────────────────────────────────────────────┘
```

---

## 🔄 Admin Workflow Examples

### Example 1: Approving a Gym

```
STEP 1: OWNER SUBMITS GYM APPLICATION
    └─→ App created with status: PENDING

STEP 2: ADMIN VIEWS DASHBOARD
    └─→ Sees "3 pending gym approvals"

STEP 3: ADMIN OPENS GYM APPROVAL PAGE
    └─→ Sees list of pending applications
    └─→ Reviews gym details

STEP 4: ADMIN CLICKS "APPROVE"
    └─→ POST /api/v1/admin/gyms/{gymId}/approve
    └─→ Application status → APPROVED
    └─→ Gym status → ACTIVE

STEP 5: GYM NOW IN MARKETPLACE
    └─→ Users can find and join gym
    └─→ Trainers can become members
    └─→ Products/facilities visible
```

### Example 2: Managing Subscriptions

```
GYM HAS ACTIVE SUBSCRIPTION
    ├─ Plan: Business Pro
    ├─ Price: 1,299 per month
    ├─ Members: 1,500
    └─ Status: ACTIVE

ADMIN PAUSES SUBSCRIPTION
    └─→ PATCH /api/v1/admin/subscriptions/{id}/status
    └─→ Body: { "status": "PAUSED" }
    └─→ Status → PAUSED

RESULT:
    ├─ Gym still visible
    ├─ New memberships blocked
    ├─ Existing members can view
    └─ Can be resumed anytime
```

### Example 3: Creating a User Account

```
ADMIN WANTS TO CREATE NEW USER
    └─→ POST /api/v1/admin/users
    └─→ Body:
        {
          "phoneNumber": "+9647901234567",
          "role": "USER",
          "password": "SecurePass123",
          "displayName": "Ahmed Ali"
        }

RESPONSE:
    ├─ Account created successfully
    ├─ User can now login
    ├─ Can join gyms and hire trainers
    └─ Can receive training plans

BUT: Cannot create ADMIN account this way!
    └─→ Must be created manually by developers
```

---

## 🔒 Security Features

### 1. Password Hashing
```
PASSWORD INPUT
    ↓
scrypt(password, salt, cost=32768)
    ↓
HASH STORED IN DB
    ↓
LOGIN: Hash input, compare (timing-safe)
```

### 2. JWT Token Flow
```
LOGIN SUCCESS
    ↓
GENERATE TOKENS:
├─ Access Token (short-lived, 15 min)
└─ Refresh Token (long-lived, 7 days)
    ↓
RETURN TO MOBILE APP
    ↓
STORE IN AUTHSESSION
    ↓
USE IN API CALLS:
Authorization: Bearer {access_token}
```

### 3. Role-Based Guard
```
REQUEST TO ADMIN ENDPOINT
    ↓
CHECK @Roles(Role.ADMIN) DECORATOR
    ↓
EXTRACT JWT → GET USER ROLE
    ↓
IS ROLE == ADMIN?
    ├─ YES → ALLOW ✅
    └─ NO → FORBIDDEN 403 ❌
```

---

## 📱 Admin App Structure

```
ADMIN AUTH GATE
    └─→ Admin selects role
    └─→ Sees LOGIN ONLY UI
    └─→ No signup option
    └─→ Direct phone + password auth

ADMIN HOME PAGE
    └─→ Dashboard with 4 metrics:
        ├─ Pending gym approvals (count)
        ├─ Approved gyms (count)
        ├─ Active subscriptions (count)
        └─ Paused subscriptions (count)

GYM APPROVAL PAGE
    └─→ List of gym applications
    └─→ Filterable by status (PENDING/APPROVED/REJECTED)
    └─→ Approve/Reject buttons
    └─→ Can add review notes

SUBSCRIPTION MGMT PAGE
    └─→ List of all gym subscriptions
    └─→ Show plan name, price, members
    └─→ Pause/Resume buttons
    └─→ View billing dates

ROLE-BASED NAVIGATION (4 TABS)
    ├─ Home (Dashboard)
    ├─ Gym Approvals
    ├─ Subscriptions
    └─ Analytics (placeholder)
```

---

## 🚀 Admin API Endpoints Summary

```
ADMIN ENDPOINTS (All require @Roles(Role.ADMIN))

Dashboard
├─ GET /admin/dashboard
└─ Returns: pending, approved, subscriptions counts

Gym Management
├─ GET /admin/gyms?status=PENDING
├─ POST /admin/gyms/{gymId}/approve
└─ POST /admin/gyms/{gymId}/reject

Subscription Management
├─ GET /admin/subscriptions
└─ PATCH /admin/subscriptions/{id}/status

User Management
└─ POST /admin/users (create non-admin users)

OTP Tracking (Debugging)
├─ GET /auth/phone/provider-info
└─ GET /auth/phone/track/{sessionId}
```

---

## ⚙️ Admin Account Creation Flow

```
NORMAL USERS
    ├─ Signup via OTP flow
    ├─ Phone + OTP + Password
    └─ Can create any role except ADMIN

ADMIN ACCOUNTS (Special)
    ├─ ❌ Cannot signup via OTP
    ├─ ❌ Cannot be created via REST API
    ├─ ✅ Manual database insert
    ├─ ✅ Seed script during deployment
    └─ ✅ Backend service call (private)

WHY? SECURITY
    └─ Prevents unauthorized admin creation
    └─ Requires direct database access
    └─ Only developer/sysadmin can do it
```

---

## 🔐 Login Comparison: All Roles

```
┌─────────────┬─────────┬─────────┬─────────┬────────┐
│ Feature     │ ADMIN   │ OWNER   │ TRAINER │ USER   │
├─────────────┼─────────┼─────────┼─────────┼────────┤
│ Signup      │ ❌ NO   │ ✅ OTP  │ ✅ OTP  │ ✅ OTP │
│ Login       │ ✅ DIRECT│ ✅ BOTH │ ✅ BOTH │ ✅ BOTH│
│ OTP Method  │ ❌ NO   │ ✅ YES  │ ✅ YES  │ ✅ YES │
│ Password    │ ✅ REQ  │ ✅ REQ  │ ✅ REQ  │ ✅ REQ │
│ Direct Auth │ ✅ YES  │ ✅ YES  │ ✅ YES  │ ✅ YES │
│ Creation    │ 🔧 MAN  │ 👤 SELF │ 👤 SELF │ 👤 SELF│
│ Password    │ 🔧 MAN  │ 🔄 OTP  │ 🔄 OTP  │ 🔄 OTP │
│ Reset       │         │         │         │        │
└─────────────┴─────────┴─────────┴─────────┴────────┘

Legend:
✅ = Available     ❌ = Not available
🔧 = Manual only   👤 = Self-service
🔄 = Via OTP flow  REQ = Required
MAN = Manual
DIRECT = Phone + Password
```

---

## 🎯 Key Points to Remember

1. **Admin Login is Direct**
   - No OTP flow
   - Phone number + Password only
   - Similar to traditional login

2. **Admin Accounts are Manual**
   - Cannot be created via signup
   - Must be inserted into database
   - Only developers can create

3. **Admin has Full Control**
   - Approve/reject all gyms
   - Manage all subscriptions
   - View platform-wide metrics
   - Create user accounts

4. **RBAC Protects Endpoints**
   - @Roles(Role.ADMIN) decorator
   - RolesGuard middleware checks
   - JWT token validates user role

5. **Security Best Practices**
   - Passwords hashed with scrypt
   - JWT tokens with expiration
   - Timing-safe comparison
   - No plain text storage

