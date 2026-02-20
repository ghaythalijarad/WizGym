export type GymApprovalStatus = 'PENDING' | 'APPROVED' | 'REJECTED';
export type SubscriptionStatus = 'ACTIVE' | 'PAUSED' | 'CANCELED';
export type PhoneOtpStatus = 'PENDING' | 'VERIFIED' | 'FAILED' | 'EXPIRED';
export type TrainerHireStatus = 'ACTIVE' | 'COMPLETED' | 'CANCELED';
export type AccountRole = 'ADMIN' | 'OWNER' | 'TRAINER' | 'USER';
export type GymAudience = 'MEN_ONLY' | 'WOMEN_ONLY' | 'MIXED';

export interface GymApplicationDocument {
  id: string;
  gymName: string;
  ownerName: string;
  ownerUserId: string;
  city: string;
  requestedAt: Date;
  status: GymApprovalStatus;
  reviewNote?: string;
  reviewedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface GymDocument {
  id: string;
  applicationId?: string;
  name: string;
  city: string;
  ownerUserId: string;
  ownerName: string;
  description?: string;
  coverImageUrl?: string;
  audience: GymAudience;
  amenities: string[];
  status: GymApprovalStatus;
  createdAt: Date;
  updatedAt: Date;
}

export interface GymMembershipDocument {
  id: string;
  gymId: string;
  userId: string;
  joinedAt: Date;
}

export interface GymTrainerMembershipDocument {
  id: string;
  gymId: string;
  trainerId: string;
  joinedAt: Date;
  active: boolean;
}

export interface TrainerHireDocument {
  id: string;
  gymId: string;
  trainerId: string;
  userId: string;
  status: TrainerHireStatus;
  hiredAt: Date;
  endedAt?: Date | null;
}

export interface GymRatingDocument {
  id: string;
  gymId: string;
  userId: string;
  rating: number;
  comment?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface TrainerRatingDocument {
  id: string;
  gymId: string;
  trainerId: string;
  userId: string;
  rating: number;
  comment?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface GymFacilityDocument {
  id: string;
  gymId: string;
  name: string;
  description?: string;
  imageUrl?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface GymBranchDocument {
  id: string;
  gymId: string;
  name: string;
  city: string;
  address?: string;
  location?: {
    lat: number;
    lng: number;
  };
  phoneNumber?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface GymProductDocument {
  id: string;
  gymId: string;
  title: string;
  description?: string;
  imageUrl?: string;
  price?: number;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface PlatformSubscriptionDocument {
  id: string;
  gymId: string;
  gymName: string;
  planName: string;
  membersLimit: number;
  monthlyPrice: number;
  nextBillingDate: Date;
  status: SubscriptionStatus;
  createdAt: Date;
  updatedAt: Date;
}

export interface PhoneVerificationSessionDocument {
  id: string;
  phoneNumber: string;
  codeHash: string;
  codeSalt: string;
  smsId?: string;
  provider?: string;
  expiresAt: Date;
  verifiedAt?: Date;
  attempts: number;
  maxAttempts: number;
  status: PhoneOtpStatus;
  createdAt: Date;
  updatedAt: Date;
}

export interface UserAccountDocument {
  id: string;
  phoneNumber: string;
  displayName: string;
  role: AccountRole;
  lastLoginAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}
