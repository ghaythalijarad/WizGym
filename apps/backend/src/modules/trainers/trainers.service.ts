import { ForbiddenException, Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';

import { MongoService } from '../../infrastructure/mongo/mongo.service';
import { CreateTrainerRatingDto } from './dto/create-trainer-rating.dto';

@Injectable()
export class TrainersService {
  constructor(private readonly mongo: MongoService) {}

  async getMyClients(trainerId: string) {
    const hires = await this.mongo.trainerHires
      .find({
        trainerId,
        status: 'ACTIVE',
      })
      .sort({ hiredAt: -1 })
      .toArray();

    return {
      total: hires.length,
      clients: hires.map((item) => ({
        id: item.userId,
        name: `User ${item.userId}`,
        gymId: item.gymId,
        hiredAt: item.hiredAt,
      })),
    };
  }

  async getMyGyms(trainerId: string) {
    const memberships = await this.mongo.gymTrainerMemberships
      .find({
        trainerId,
        active: true,
      })
      .sort({ joinedAt: -1 })
      .toArray();

    if (memberships.length === 0) {
      return [];
    }

    const gymIds = [...new Set(memberships.map((item) => item.gymId))];

    const [gyms, ratings, hires] = await Promise.all([
      this.mongo.gyms.find({ id: { $in: gymIds } }).toArray(),
      this.mongo.trainerRatings
        .aggregate<{
          _id: string;
          avgRating: number;
          count: number;
        }>([
          { $match: { trainerId, gymId: { $in: gymIds } } },
          {
            $group: {
              _id: '$gymId',
              avgRating: { $avg: '$rating' },
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
          { $match: { trainerId, gymId: { $in: gymIds } } },
          {
            $group: {
              _id: '$gymId',
              count: { $sum: 1 },
            },
          },
        ])
        .toArray(),
    ]);

    const gymMap = new Map(gyms.map((item) => [item.id, item]));
    const ratingMap = new Map(ratings.map((item) => [item._id, item]));
    const hireMap = new Map(hires.map((item) => [item._id, item.count]));

    return memberships.map((item) => {
      const gym = gymMap.get(item.gymId);
      const rating = ratingMap.get(item.gymId);

      return {
        gymId: item.gymId,
        gymName: gym?.name ?? item.gymId,
        city: gym?.city ?? '-',
        joinedAt: item.joinedAt,
        activeClients: hireMap.get(item.gymId) ?? 0,
        ratingsCount: rating?.count ?? 0,
        averageRating: toFixed2(rating?.avgRating ?? 0),
      };
    });
  }

  async rateTrainer(userId: string, trainerId: string, body: CreateTrainerRatingDto) {
    const userMembership = await this.mongo.gymMemberships.findOne({
      gymId: body.gymId,
      userId,
    });

    if (!userMembership) {
      throw new ForbiddenException('Join the gym before rating a trainer');
    }

    const trainerMembership = await this.mongo.gymTrainerMemberships.findOne({
      gymId: body.gymId,
      trainerId,
    });

    if (!trainerMembership || !trainerMembership.active) {
      throw new ForbiddenException('Trainer is not active in this gym');
    }

    const existing = await this.mongo.trainerRatings.findOne({
      gymId: body.gymId,
      trainerId,
      userId,
    });

    const now = new Date();

    if (existing) {
      await this.mongo.trainerRatings.updateOne(
        { id: existing.id },
        {
          $set: {
            rating: body.rating,
            comment: body.comment,
            updatedAt: now,
          },
        },
      );

      const updated = await this.mongo.trainerRatings.findOne({ id: existing.id });
      return {
        submitted: true,
        rating: updated,
      };
    }

    const rating = {
      id: randomUUID(),
      gymId: body.gymId,
      trainerId,
      userId,
      rating: body.rating,
      comment: body.comment,
      createdAt: now,
      updatedAt: now,
    };

    await this.mongo.trainerRatings.insertOne(rating);

    return {
      submitted: true,
      rating,
    };
  }

  async getTrainerRatings(trainerId: string) {
    const ratings = await this.mongo.trainerRatings
      .find({ trainerId })
      .sort({ updatedAt: -1 })
      .toArray();

    const total = ratings.length;
    const average = total === 0 ? 0 : ratings.reduce((sum, item) => sum + item.rating, 0) / total;

    return {
      summary: {
        averageRating: toFixed2(average),
        totalRatings: total,
      },
      ratings,
    };
  }
}

function toFixed2(value: number): number {
  return Number(value.toFixed(2));
}
