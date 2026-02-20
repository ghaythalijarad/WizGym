export type GymApprovalStatus = 'PENDING' | 'APPROVED' | 'REJECTED';

export interface GymApplication {
  id: string;
  gymName: string;
  ownerName: string;
  city: string;
  requestedAt: string;
  status: GymApprovalStatus;
  reviewNote?: string;
}

export type SubscriptionStatus = 'ACTIVE' | 'PAUSED' | 'CANCELED';

export interface PlatformSubscription {
  id: string;
  gymId: string;
  gymName: string;
  planName: string;
  membersLimit: number;
  monthlyPrice: number;
  nextBillingDate: string;
  status: SubscriptionStatus;
}
