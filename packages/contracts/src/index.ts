export enum Role {
  ADMIN = 'ADMIN',
  OWNER = 'OWNER',
  TRAINER = 'TRAINER',
  USER = 'USER',
}

export interface AuthProfile {
  id: string;
  displayName: string;
  role: Role;
  phoneNumber: string;
}

export interface LoginRequest {
  phoneNumber: string;
}

export interface LoginResponse {
  token: string;
  refreshToken: string;
  profile: AuthProfile;
}

export interface SignupRequest {
  phoneNumber: string;
  role: Role;
  displayName?: string;
}

export interface SignupResponse {
  token: string;
  refreshToken: string;
  profile: AuthProfile;
}

export interface RequestPhoneOtpRequest {
  phoneNumber: string;
}

export interface RequestPhoneOtpResponse {
  sessionId: string;
  phoneNumber: string;
  expiresAt: string;
  message: string;
  deliveryProvider: string;
  mockCode?: string;
}

export interface VerifyPhoneOtpRequest {
  phoneNumber: string;
  code: string;
}

export interface VerifyPhoneOtpResponse {
  verified: boolean;
  phoneNumber: string;
  verifiedAt: string;
  sessionId: string;
  accountExists: boolean;
}

export interface SmsProviderInfoResponse {
  projectName: string;
  credit: number;
  mocked?: boolean;
}

export interface SmsDeliveryTrackResponse {
  sessionId: string;
  phoneNumber: string;
  internalStatus: string;
  provider?: string | null;
  providerStatus:
    | {
        smsId: string;
        status: string;
        isFinalStatus: boolean;
        lastChannel: string | null;
      }
    | 'not_available';
  message?: string;
  createdAt?: string;
  updatedAt?: string;
}

export interface OwnerDashboard {
  activeMembers: number;
  todayRevenue: number;
  occupancyRate: number;
  churnRiskMembers: number;
  totalGyms?: number;
  averageRating?: number;
  activeTrainerHires?: number;
}

export interface TrainerClientsSummary {
  total: number;
  clients: Array<{
    id: string;
    name: string;
    gymId: string;
    hiredAt: string;
  }>;
}

export interface MemberPlan {
  planName: string;
  expiresAt: string;
  freezeDaysRemaining: number;
  sessionsLeft: number;
}

export type GymApprovalStatus = 'PENDING' | 'APPROVED' | 'REJECTED';

export interface GymApplication {
  id: string;
  gymName: string;
  ownerName: string;
  ownerUserId: string;
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

export interface AdminDashboardSummary {
  pendingGymApprovals: number;
  approvedGyms: number;
  activeSubscriptions: number;
  pausedSubscriptions: number;
}

export type GymAudience = 'MEN_ONLY' | 'WOMEN_ONLY' | 'MIXED';

export interface GymPublicSummary {
  id: string;
  name: string;
  city: string;
  description?: string | null;
  coverImageUrl?: string | null;
  audience: GymAudience;
  amenities: string[];
  membersCount: number;
  trainersCount: number;
  facilitiesCount: number;
  activeProductsCount: number;
  averageRating: number;
  ratingsCount: number;
}

export interface GymTrainerProfile {
  trainerId: string;
  displayName: string;
  joinedAt: string;
  activeClients: number;
  ratingsCount: number;
  averageRating: number;
  hiredByRequester?: boolean;
}

export interface GymProduct {
  id: string;
  gymId: string;
  title: string;
  description?: string | null;
  imageUrl?: string | null;
  price?: number | null;
  isActive: boolean;
}

export interface GymFacility {
  id: string;
  gymId: string;
  name: string;
  description?: string | null;
  imageUrl?: string | null;
}

export interface GymRating {
  id: string;
  gymId: string;
  userId: string;
  rating: number;
  comment?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface TrainerRating {
  id: string;
  gymId: string;
  trainerId: string;
  userId: string;
  rating: number;
  comment?: string | null;
  createdAt: string;
  updatedAt: string;
}
