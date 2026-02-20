import { Injectable, NotFoundException } from '@nestjs/common';

import { MongoService } from '../../infrastructure/mongo/mongo.service';
import { GymApprovalStatus, SubscriptionStatus } from './admin.types';

@Injectable()
export class AdminService {
  constructor(private readonly mongo: MongoService) {}

  async getDashboardSummary() {
    const [pendingGymApprovals, approvedGyms, activeSubscriptions, pausedSubscriptions] =
      await Promise.all([
        this.mongo.gymApplications.countDocuments({ status: 'PENDING' }),
        this.mongo.gymApplications.countDocuments({ status: 'APPROVED' }),
        this.mongo.platformSubscriptions.countDocuments({ status: 'ACTIVE' }),
        this.mongo.platformSubscriptions.countDocuments({ status: 'PAUSED' }),
      ]);

    return {
      pendingGymApprovals,
      approvedGyms,
      activeSubscriptions,
      pausedSubscriptions,
    };
  }

  async listGyms(status?: GymApprovalStatus) {
    return this.mongo.gymApplications
      .find(status ? { status } : {})
      .sort({ requestedAt: -1 })
      .toArray();
  }

  async approveGym(gymId: string, reviewer: string) {
    const now = new Date();
    const applicationResult = await this.mongo.gymApplications.findOneAndUpdate(
      { id: gymId },
      {
        $set: {
          status: 'APPROVED',
          reviewedAt: now,
          reviewNote: `Approved by ${reviewer}`,
          updatedAt: now,
        },
      },
      { returnDocument: 'after' },
    );

    const application = applicationResult;
    if (!application) {
      throw new NotFoundException(`Gym application ${gymId} not found`);
    }

    await this.mongo.gyms.updateOne(
      { id: gymId },
      {
        $set: {
          applicationId: application.id,
          name: application.gymName,
          city: application.city,
          ownerUserId: application.ownerUserId,
          ownerName: application.ownerName,
          status: 'APPROVED',
          updatedAt: now,
        },
        $setOnInsert: {
          id: application.id,
          createdAt: now,
          audience: 'MIXED',
          amenities: [],
        },
      },
      { upsert: true },
    );

    return application;
  }

  async rejectGym(gymId: string, reviewer: string, note?: string) {
    const now = new Date();
    const applicationResult = await this.mongo.gymApplications.findOneAndUpdate(
      { id: gymId },
      {
        $set: {
          status: 'REJECTED',
          reviewedAt: now,
          reviewNote: note ? `${note} (Reviewer: ${reviewer})` : `Rejected by ${reviewer}`,
          updatedAt: now,
        },
      },
      { returnDocument: 'after' },
    );

    const application = applicationResult;
    if (!application) {
      throw new NotFoundException(`Gym application ${gymId} not found`);
    }

    await this.mongo.gyms.updateMany(
      {
        $or: [{ id: gymId }, { applicationId: gymId }],
      },
      {
        $set: {
          status: 'REJECTED',
          updatedAt: now,
        },
      },
    );

    return application;
  }

  async listSubscriptions() {
    return this.mongo.platformSubscriptions.find({}).sort({ createdAt: -1 }).toArray();
  }

  async updateSubscriptionStatus(subscriptionId: string, status: SubscriptionStatus) {
    const subscription = await this.mongo.platformSubscriptions.findOneAndUpdate(
      { id: subscriptionId },
      {
        $set: {
          status,
          updatedAt: new Date(),
        },
      },
      { returnDocument: 'after' },
    );

    if (!subscription) {
      throw new NotFoundException(`Subscription ${subscriptionId} not found`);
    }

    return subscription;
  }
}
