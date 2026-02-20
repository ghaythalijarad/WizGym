import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Collection, Db, Document, MongoClient } from 'mongodb';

import {
  GymApplicationDocument,
  GymBranchDocument,
  GymDocument,
  GymFacilityDocument,
  GymMembershipDocument,
  GymProductDocument,
  GymRatingDocument,
  GymTrainerMembershipDocument,
  PhoneVerificationSessionDocument,
  PlatformSubscriptionDocument,
  TrainerHireDocument,
  TrainerRatingDocument,
  UserAccountDocument,
} from './mongo.types';

@Injectable()
export class MongoService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MongoService.name);
  private readonly uri = process.env.MONGODB_URI ?? 'mongodb://localhost:27017/gymos';
  private readonly dbName = process.env.MONGODB_DB_NAME ?? this.inferDbName(this.uri) ?? 'gymos';

  private client?: MongoClient;
  private db?: Db;

  async onModuleInit() {
    this.client = new MongoClient(this.uri);
    await this.client.connect();
    this.db = this.client.db(this.dbName);
    await this.ensureIndexes();
    this.logger.log(`Connected to MongoDB database "${this.dbName}"`);
  }

  async onModuleDestroy() {
    await this.client?.close();
  }

  get gymApplications(): Collection<GymApplicationDocument> {
    return this.collection<GymApplicationDocument>('gymApplications');
  }

  get gyms(): Collection<GymDocument> {
    return this.collection<GymDocument>('gyms');
  }

  get gymMemberships(): Collection<GymMembershipDocument> {
    return this.collection<GymMembershipDocument>('gymMemberships');
  }

  get gymTrainerMemberships(): Collection<GymTrainerMembershipDocument> {
    return this.collection<GymTrainerMembershipDocument>('gymTrainerMemberships');
  }

  get trainerHires(): Collection<TrainerHireDocument> {
    return this.collection<TrainerHireDocument>('trainerHires');
  }

  get gymRatings(): Collection<GymRatingDocument> {
    return this.collection<GymRatingDocument>('gymRatings');
  }

  get trainerRatings(): Collection<TrainerRatingDocument> {
    return this.collection<TrainerRatingDocument>('trainerRatings');
  }

  get gymFacilities(): Collection<GymFacilityDocument> {
    return this.collection<GymFacilityDocument>('gymFacilities');
  }

  get gymBranches(): Collection<GymBranchDocument> {
    return this.collection<GymBranchDocument>('gymBranches');
  }

  get gymProducts(): Collection<GymProductDocument> {
    return this.collection<GymProductDocument>('gymProducts');
  }

  get platformSubscriptions(): Collection<PlatformSubscriptionDocument> {
    return this.collection<PlatformSubscriptionDocument>('platformSubscriptions');
  }

  get phoneVerificationSessions(): Collection<PhoneVerificationSessionDocument> {
    return this.collection<PhoneVerificationSessionDocument>('phoneVerificationSessions');
  }

  get userAccounts(): Collection<UserAccountDocument> {
    return this.collection<UserAccountDocument>('userAccounts');
  }

  private collection<T extends Document>(name: string): Collection<T> {
    return this.database.collection<T>(name);
  }

  private get database(): Db {
    if (!this.db) {
      throw new Error('MongoDB is not initialized');
    }

    return this.db;
  }

  private inferDbName(uri: string): string | null {
    try {
      const parsed = new URL(uri);
      const pathname = parsed.pathname.replace(/^\//, '').trim();
      return pathname.length > 0 ? pathname : null;
    } catch {
      return null;
    }
  }

  private async ensureIndexes() {
    await Promise.all([
      this.gymApplications.createIndex({ id: 1 }, { unique: true }),
      this.gyms.createIndex({ id: 1 }, { unique: true }),
      this.gyms.createIndex({ applicationId: 1 }, { unique: true, sparse: true }),
      this.gymMemberships.createIndex({ id: 1 }, { unique: true }),
      this.gymMemberships.createIndex({ gymId: 1, userId: 1 }, { unique: true }),
      this.gymTrainerMemberships.createIndex({ id: 1 }, { unique: true }),
      this.gymTrainerMemberships.createIndex({ gymId: 1, trainerId: 1 }, { unique: true }),
      this.trainerHires.createIndex({ id: 1 }, { unique: true }),
      this.trainerHires.createIndex({ gymId: 1, trainerId: 1, userId: 1 }, { unique: true }),
      this.gymRatings.createIndex({ id: 1 }, { unique: true }),
      this.gymRatings.createIndex({ gymId: 1, userId: 1 }, { unique: true }),
      this.trainerRatings.createIndex({ id: 1 }, { unique: true }),
      this.trainerRatings.createIndex({ gymId: 1, trainerId: 1, userId: 1 }, { unique: true }),
      this.gymFacilities.createIndex({ id: 1 }, { unique: true }),
      this.gymBranches.createIndex({ id: 1 }, { unique: true }),
      this.gymBranches.createIndex({ gymId: 1, city: 1, name: 1 }),
      this.gymProducts.createIndex({ id: 1 }, { unique: true }),
      this.platformSubscriptions.createIndex({ id: 1 }, { unique: true }),
      this.platformSubscriptions.createIndex({ gymId: 1 }, { unique: true }),
      this.phoneVerificationSessions.createIndex({ id: 1 }, { unique: true }),
      this.phoneVerificationSessions.createIndex({ phoneNumber: 1, status: 1, createdAt: -1 }),
      this.userAccounts.createIndex({ id: 1 }, { unique: true }),
      this.userAccounts.createIndex({ phoneNumber: 1 }, { unique: true }),
    ]);
  }
}
