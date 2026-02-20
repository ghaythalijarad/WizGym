import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';

import { RolesGuard } from './common/guards/roles.guard';
import { MockAuthGuard } from './common/guards/mock-auth.guard';
import { HealthController } from './health.controller';
import { MongoModule } from './infrastructure/mongo/mongo.module';
import { AdminModule } from './modules/admin/admin.module';
import { AnalyticsModule } from './modules/analytics/analytics.module';
import { AuthModule } from './modules/auth/auth.module';
import { BookingsModule } from './modules/bookings/bookings.module';
import { ClassesModule } from './modules/classes/classes.module';
import { GymsModule } from './modules/gyms/gyms.module';
import { MembershipsModule } from './modules/memberships/memberships.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { PlansModule } from './modules/plans/plans.module';
import { TrainersModule } from './modules/trainers/trainers.module';
import { UsersModule } from './modules/users/users.module';

@Module({
  controllers: [HealthController],
  imports: [
    MongoModule,
    AdminModule,
    AuthModule,
    UsersModule,
    GymsModule,
    TrainersModule,
    MembershipsModule,
    BookingsModule,
    ClassesModule,
    PlansModule,
    PaymentsModule,
    AnalyticsModule,
    NotificationsModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: MockAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
  ],
})
export class AppModule {}
