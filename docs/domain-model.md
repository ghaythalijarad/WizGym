# Domain Model (Target)

## Core Entities
- Gym
- Branch
- User
- TrainerProfile
- MembershipPlan
- MembershipSubscription
- ClassSession
- Booking
- WorkoutPlan
- WorkoutAssignment
- PaymentTransaction
- Notification

## Key Relationships
- Gym 1..* Branch
- Gym 1..* User
- User 1..1 TrainerProfile (optional)
- User 1..* MembershipSubscription
- MembershipPlan 1..* MembershipSubscription
- Branch 1..* ClassSession
- User *..* ClassSession via Booking
- TrainerProfile 1..* WorkoutPlan
- WorkoutPlan *..* User via WorkoutAssignment

## Multi-Tenancy
- All business entities carry `gymId`
- Optional `branchId` for branch-scoped resources
- RBAC is evaluated within tenant boundaries
