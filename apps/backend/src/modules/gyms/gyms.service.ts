import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';

import { Role } from '../../common/enums/role.enum';
import { RequestUser } from '../../common/interfaces/request-user.interface';
import { MongoService } from '../../infrastructure/mongo/mongo.service';
import { GymAudience, GymDocument } from '../../infrastructure/mongo/mongo.types';
import { CreateGymFacilityDto } from './dto/create-gym-facility.dto';
import { CreateGymProductDto } from './dto/create-gym-product.dto';
import { CreateGymRatingDto } from './dto/create-gym-rating.dto';
import { UpdateGymProfileDto } from './dto/update-gym-profile.dto';

@Injectable()
export class GymsService {
  constructor(private readonly mongo: MongoService) {}

  async listOwnerGyms(ownerUserId: string) {
    const gyms = await this.mongo.gyms
      .find({ ownerUserId })
      .sort({ city: 1, name: 1 })
      .toArray();

    const metrics = await this.aggregateGymMetrics(gyms.map((item) => item.id));

    return gyms.map((gym) => ({
      id: gym.id,
      name: gym.name,
      city: gym.city,
      description: gym.description,
      coverImageUrl: gym.coverImageUrl,
      audience: gym.audience,
      amenities: gym.amenities,
      membersCount: metrics.members.get(gym.id) ?? 0,
      trainersCount: metrics.trainers.get(gym.id) ?? 0,
      facilitiesCount: metrics.facilities.get(gym.id) ?? 0,
      activeProductsCount: metrics.products.get(gym.id) ?? 0,
      averageRating: toFixed2(metrics.ratings.get(gym.id)?.average ?? 0),
      ratingsCount: metrics.ratings.get(gym.id)?.count ?? 0,
    }));
  }

  async ownerDashboard(ownerUserId: string) {
    const gyms = await this.mongo.gyms
      .find({ ownerUserId }, { projection: { id: 1 } })
      .toArray();

    const gymIds = gyms.map((item) => item.id);

    if (gymIds.length === 0) {
      return {
        activeMembers: 0,
        todayRevenue: 0,
        occupancyRate: 0,
        churnRiskMembers: 0,
        totalGyms: 0,
        averageRating: 0,
        activeTrainerHires: 0,
      };
    }

    const [activeMembers, activeTrainerHires, ratings] = await Promise.all([
      this.mongo.gymMemberships.countDocuments({ gymId: { $in: gymIds } }),
      this.mongo.trainerHires.countDocuments({ gymId: { $in: gymIds }, status: 'ACTIVE' }),
      this.mongo.gymRatings
        .aggregate<{
          _id: null;
          avgRating: number;
        }>([
          { $match: { gymId: { $in: gymIds } } },
          {
            $group: {
              _id: null,
              avgRating: { $avg: '$rating' },
            },
          },
        ])
        .toArray(),
    ]);

    const averageRating = ratings[0]?.avgRating ?? 0;
    const occupancyRate = Math.min(100, Math.round((activeMembers / (gymIds.length * 500)) * 100));

    return {
      activeMembers,
      todayRevenue: 0,
      occupancyRate,
      churnRiskMembers: Math.round(activeMembers * 0.08),
      totalGyms: gymIds.length,
      averageRating: toFixed2(averageRating),
      activeTrainerHires,
    };
  }

  async listPublicGyms(city?: string, audience?: string) {
    const gymAudience = this.normalizeAudienceFilter(audience);

    const filter: Partial<GymDocument> = {
      status: 'APPROVED',
    };

    if (city && city.trim().length > 0) {
      filter.city = city.trim();
    }

    if (gymAudience) {
      filter.audience = gymAudience;
    }

    const gyms = await this.mongo.gyms
      .find(filter)
      .sort({ city: 1, name: 1 })
      .toArray();

    const metrics = await this.aggregateGymMetrics(gyms.map((item) => item.id));

    return gyms.map((gym) => ({
      id: gym.id,
      name: gym.name,
      city: gym.city,
      description: gym.description,
      coverImageUrl: gym.coverImageUrl,
      audience: gym.audience,
      amenities: gym.amenities,
      membersCount: metrics.members.get(gym.id) ?? 0,
      trainersCount: metrics.trainers.get(gym.id) ?? 0,
      facilitiesCount: metrics.facilities.get(gym.id) ?? 0,
      activeProductsCount: metrics.products.get(gym.id) ?? 0,
      averageRating: toFixed2(metrics.ratings.get(gym.id)?.average ?? 0),
      ratingsCount: metrics.ratings.get(gym.id)?.count ?? 0,
    }));
  }

  async getPublicGymDetails(gymId: string) {
    const gym = await this.ensureGymApproved(gymId);

    const [facilities, products, ratings, trainersCount] = await Promise.all([
      this.mongo.gymFacilities.find({ gymId }).sort({ createdAt: -1 }).toArray(),
      this.mongo.gymProducts.find({ gymId, isActive: true }).sort({ createdAt: -1 }).toArray(),
      this.mongo.gymRatings
        .aggregate<{
          _id: null;
          avgRating: number;
          count: number;
        }>([
          { $match: { gymId } },
          {
            $group: {
              _id: null,
              avgRating: { $avg: '$rating' },
              count: { $sum: 1 },
            },
          },
        ])
        .toArray(),
      this.mongo.gymTrainerMemberships.countDocuments({ gymId, active: true }),
    ]);

    const summary = ratings[0];

    return {
      id: gym.id,
      name: gym.name,
      city: gym.city,
      description: gym.description,
      coverImageUrl: gym.coverImageUrl,
      audience: gym.audience,
      amenities: gym.amenities,
      ownerName: gym.ownerName,
      trainersCount,
      averageRating: toFixed2(summary?.avgRating ?? 0),
      ratingsCount: summary?.count ?? 0,
      facilities,
      products,
    };
  }

  async joinGymAsUser(gymId: string, userId: string) {
    await this.ensureGymApproved(gymId);

    const existing = await this.mongo.gymMemberships.findOne({ gymId, userId });
    if (existing) {
      return {
        joined: true,
        gymId,
        userId,
        membership: existing,
      };
    }

    const membership = {
      id: randomUUID(),
      gymId,
      userId,
      joinedAt: new Date(),
    };

    try {
      await this.mongo.gymMemberships.insertOne(membership);
    } catch (error) {
      if (!isDuplicateKeyError(error)) {
        throw error;
      }
    }

    const current = await this.mongo.gymMemberships.findOne({ gymId, userId });

    return {
      joined: true,
      gymId,
      userId,
      membership: current ?? membership,
    };
  }

  async joinGymAsTrainer(gymId: string, trainerId: string) {
    await this.ensureGymApproved(gymId);

    const existing = await this.mongo.gymTrainerMemberships.findOne({ gymId, trainerId });

    if (existing?.active) {
      return {
        joined: true,
        message: 'Trainer is already active in this gym',
        membership: existing,
      };
    }

    const activeGymsCount = await this.mongo.gymTrainerMemberships.countDocuments({
      trainerId,
      active: true,
    });

    if (activeGymsCount >= 4) {
      throw new BadRequestException('Trainer can only be active in up to 4 gyms');
    }

    const now = new Date();

    if (existing) {
      await this.mongo.gymTrainerMemberships.updateOne(
        { id: existing.id },
        {
          $set: {
            active: true,
            joinedAt: now,
          },
        },
      );

      const membership = await this.mongo.gymTrainerMemberships.findOne({ id: existing.id });

      return {
        joined: true,
        membership,
      };
    }

    const membership = {
      id: randomUUID(),
      gymId,
      trainerId,
      joinedAt: now,
      active: true,
    };

    try {
      await this.mongo.gymTrainerMemberships.insertOne(membership);
    } catch (error) {
      if (!isDuplicateKeyError(error)) {
        throw error;
      }
    }

    const current = await this.mongo.gymTrainerMemberships.findOne({ gymId, trainerId });

    return {
      joined: true,
      membership: current ?? membership,
    };
  }

  async listGymTrainers(gymId: string, requester: RequestUser) {
    await this.ensureGymApproved(gymId);

    if (requester.role === Role.USER) {
      const membership = await this.mongo.gymMemberships.findOne({
        gymId,
        userId: requester.id,
      });

      if (!membership) {
        throw new ForbiddenException('Join the gym first to view available trainers');
      }
    }

    const [memberships, ratings, hires] = await Promise.all([
      this.mongo.gymTrainerMemberships
        .find({ gymId, active: true })
        .sort({ joinedAt: 1 })
        .toArray(),
      this.mongo.trainerRatings
        .aggregate<{
          _id: string;
          averageRating: number;
          count: number;
        }>([
          { $match: { gymId } },
          {
            $group: {
              _id: '$trainerId',
              averageRating: { $avg: '$rating' },
              count: { $sum: 1 },
            },
          },
        ])
        .toArray(),
      this.mongo.trainerHires
        .aggregate<{
          _id: string;
          count: number;
        }>([
          { $match: { gymId } },
          {
            $group: {
              _id: '$trainerId',
              count: { $sum: 1 },
            },
          },
        ])
        .toArray(),
    ]);

    const ratingMap = new Map(ratings.map((item) => [item._id, item]));
    const hiresMap = new Map(hires.map((item) => [item._id, item.count]));

    const hiredSet = new Set<string>();
    if (requester.role === Role.USER) {
      const activeHires = await this.mongo.trainerHires
        .find({
          gymId,
          userId: requester.id,
          status: 'ACTIVE',
        })
        .project<{ trainerId: string }>({ trainerId: 1, _id: 0 })
        .toArray();

      for (const item of activeHires) {
        hiredSet.add(item.trainerId);
      }
    }

    return memberships.map((item) => {
      const rating = ratingMap.get(item.trainerId);

      return {
        trainerId: item.trainerId,
        displayName: `Trainer ${item.trainerId}`,
        joinedAt: item.joinedAt,
        activeClients: hiresMap.get(item.trainerId) ?? 0,
        ratingsCount: rating?.count ?? 0,
        averageRating: toFixed2(rating?.averageRating ?? 0),
        hiredByRequester: hiredSet.has(item.trainerId),
      };
    });
  }

  async hireTrainer(gymId: string, trainerId: string, userId: string) {
    await this.ensureGymApproved(gymId);

    const userMembership = await this.mongo.gymMemberships.findOne({
      gymId,
      userId,
    });

    if (!userMembership) {
      throw new ForbiddenException('Join the gym before hiring a trainer');
    }

    const trainerMembership = await this.mongo.gymTrainerMemberships.findOne({
      gymId,
      trainerId,
    });

    if (!trainerMembership || !trainerMembership.active) {
      throw new BadRequestException('Trainer is not active in this gym');
    }

    const existing = await this.mongo.trainerHires.findOne({ gymId, trainerId, userId });
    const now = new Date();

    if (existing) {
      await this.mongo.trainerHires.updateOne(
        { id: existing.id },
        {
          $set: {
            status: 'ACTIVE',
            endedAt: null,
            hiredAt: now,
          },
        },
      );

      const hire = await this.mongo.trainerHires.findOne({ id: existing.id });

      return {
        hired: true,
        hire,
      };
    }

    const hire = {
      id: randomUUID(),
      gymId,
      trainerId,
      userId,
      status: 'ACTIVE' as const,
      hiredAt: now,
      endedAt: null,
    };

    try {
      await this.mongo.trainerHires.insertOne(hire);
    } catch (error) {
      if (!isDuplicateKeyError(error)) {
        throw error;
      }
    }

    const current = await this.mongo.trainerHires.findOne({ gymId, trainerId, userId });

    return {
      hired: true,
      hire: current ?? hire,
    };
  }

  async rateGym(gymId: string, userId: string, dto: CreateGymRatingDto) {
    await this.ensureGymApproved(gymId);
    await this.assertUserJoinedGym(gymId, userId);

    const existing = await this.mongo.gymRatings.findOne({ gymId, userId });
    const now = new Date();

    if (existing) {
      await this.mongo.gymRatings.updateOne(
        { id: existing.id },
        {
          $set: {
            rating: dto.rating,
            comment: dto.comment,
            updatedAt: now,
          },
        },
      );

      const rating = await this.mongo.gymRatings.findOne({ id: existing.id });

      return {
        submitted: true,
        rating,
      };
    }

    const rating = {
      id: randomUUID(),
      gymId,
      userId,
      rating: dto.rating,
      comment: dto.comment,
      createdAt: now,
      updatedAt: now,
    };

    await this.mongo.gymRatings.insertOne(rating);

    return {
      submitted: true,
      rating,
    };
  }

  async getGymRatings(gymId: string) {
    await this.ensureGymApproved(gymId);

    const ratings = await this.mongo.gymRatings
      .find({ gymId })
      .sort({ updatedAt: -1 })
      .toArray();

    const totalRatings = ratings.length;
    const averageRating =
      totalRatings === 0 ? 0 : ratings.reduce((sum, item) => sum + item.rating, 0) / totalRatings;

    return {
      summary: {
        averageRating: toFixed2(averageRating),
        totalRatings,
      },
      ratings,
    };
  }

  async createFacility(gymId: string, ownerUserId: string, dto: CreateGymFacilityDto) {
    await this.assertGymOwner(gymId, ownerUserId);

    const now = new Date();
    const facility = {
      id: randomUUID(),
      gymId,
      name: dto.name,
      description: dto.description,
      imageUrl: dto.imageUrl,
      createdAt: now,
      updatedAt: now,
    };

    await this.mongo.gymFacilities.insertOne(facility);

    return {
      created: true,
      facility,
    };
  }

  async listFacilities(gymId: string) {
    await this.ensureGymApproved(gymId);

    return this.mongo.gymFacilities.find({ gymId }).sort({ createdAt: -1 }).toArray();
  }

  async createProduct(gymId: string, ownerUserId: string, dto: CreateGymProductDto) {
    await this.assertGymOwner(gymId, ownerUserId);

    const now = new Date();
    const product = {
      id: randomUUID(),
      gymId,
      title: dto.title,
      description: dto.description,
      imageUrl: dto.imageUrl,
      price: dto.price,
      isActive: dto.isActive ?? true,
      createdAt: now,
      updatedAt: now,
    };

    await this.mongo.gymProducts.insertOne(product);

    return {
      created: true,
      product,
    };
  }

  async listProducts(gymId: string) {
    await this.ensureGymApproved(gymId);

    return this.mongo.gymProducts
      .find({
        gymId,
        isActive: true,
      })
      .sort({ createdAt: -1 })
      .toArray();
  }

  async updateGymProfile(gymId: string, ownerUserId: string, dto: UpdateGymProfileDto) {
    await this.assertGymOwner(gymId, ownerUserId);

    const update: Partial<GymDocument> = {
      updatedAt: new Date(),
    };

    if (dto.audience) {
      update.audience = dto.audience;
    }

    if (dto.amenities !== undefined) {
      update.amenities = [...new Set(dto.amenities.map((item) => item.trim()).filter((item) => item.length > 0))];
    }

    if (dto.description !== undefined) {
      update.description = dto.description;
    }

    const gym = await this.mongo.gyms.findOneAndUpdate(
      { id: gymId },
      { $set: update },
      { returnDocument: 'after' },
    );

    if (!gym) {
      throw new NotFoundException(`Gym ${gymId} not found`);
    }

    return {
      updated: true,
      gym: {
        id: gym.id,
        name: gym.name,
        city: gym.city,
        audience: gym.audience,
        amenities: gym.amenities,
        description: gym.description,
      },
    };
  }

  private async ensureGymApproved(gymId: string) {
    const gym = await this.mongo.gyms.findOne({ id: gymId });

    if (!gym) {
      throw new NotFoundException(`Gym ${gymId} not found`);
    }

    if (gym.status !== 'APPROVED') {
      throw new BadRequestException('Gym is not approved for public operations');
    }

    return gym;
  }

  private async assertGymOwner(gymId: string, ownerUserId: string) {
    const gym = await this.mongo.gyms.findOne(
      { id: gymId },
      { projection: { id: 1, ownerUserId: 1 } },
    );

    if (!gym) {
      throw new NotFoundException(`Gym ${gymId} not found`);
    }

    if (gym.ownerUserId !== ownerUserId) {
      throw new ForbiddenException('You are not allowed to manage this gym');
    }
  }

  private async assertUserJoinedGym(gymId: string, userId: string) {
    const membership = await this.mongo.gymMemberships.findOne({ gymId, userId });

    if (!membership) {
      throw new ForbiddenException('Join the gym before performing this action');
    }
  }

  private normalizeAudienceFilter(audience?: string): GymAudience | undefined {
    if (!audience || audience.trim().length === 0) {
      return undefined;
    }

    const normalized = audience.trim().toUpperCase();
    if (normalized === 'MEN_ONLY' || normalized === 'WOMEN_ONLY' || normalized === 'MIXED') {
      return normalized;
    }

    throw new BadRequestException('Invalid audience value');
  }

  private async aggregateGymMetrics(gymIds: string[]) {
    if (gymIds.length === 0) {
      return {
        members: new Map<string, number>(),
        trainers: new Map<string, number>(),
        facilities: new Map<string, number>(),
        products: new Map<string, number>(),
        ratings: new Map<string, { average: number; count: number }>(),
      };
    }

    const [members, trainers, facilities, products, ratings] = await Promise.all([
      this.mongo.gymMemberships
        .aggregate<{
          _id: string;
          count: number;
        }>([
          { $match: { gymId: { $in: gymIds } } },
          {
            $group: {
              _id: '$gymId',
              count: { $sum: 1 },
            },
          },
        ])
        .toArray(),
      this.mongo.gymTrainerMemberships
        .aggregate<{
          _id: string;
          count: number;
        }>([
          { $match: { gymId: { $in: gymIds }, active: true } },
          {
            $group: {
              _id: '$gymId',
              count: { $sum: 1 },
            },
          },
        ])
        .toArray(),
      this.mongo.gymFacilities
        .aggregate<{
          _id: string;
          count: number;
        }>([
          { $match: { gymId: { $in: gymIds } } },
          {
            $group: {
              _id: '$gymId',
              count: { $sum: 1 },
            },
          },
        ])
        .toArray(),
      this.mongo.gymProducts
        .aggregate<{
          _id: string;
          count: number;
        }>([
          { $match: { gymId: { $in: gymIds } } },
          {
            $group: {
              _id: '$gymId',
              count: { $sum: 1 },
            },
          },
        ])
        .toArray(),
      this.mongo.gymRatings
        .aggregate<{
          _id: string;
          average: number;
          count: number;
        }>([
          { $match: { gymId: { $in: gymIds } } },
          {
            $group: {
              _id: '$gymId',
              average: { $avg: '$rating' },
              count: { $sum: 1 },
            },
          },
        ])
        .toArray(),
    ]);

    return {
      members: new Map(members.map((item) => [item._id, item.count])),
      trainers: new Map(trainers.map((item) => [item._id, item.count])),
      facilities: new Map(facilities.map((item) => [item._id, item.count])),
      products: new Map(products.map((item) => [item._id, item.count])),
      ratings: new Map(ratings.map((item) => [item._id, { average: item.average, count: item.count }])),
    };
  }
}

function toFixed2(value: number): number {
  return Number(value.toFixed(2));
}

function isDuplicateKeyError(error: unknown): boolean {
  if (!error || typeof error !== 'object') {
    return false;
  }

  const maybeCode = (error as { code?: unknown }).code;
  return maybeCode === 11000;
}
