import { Controller, Get } from '@nestjs/common';

import { Roles } from '../../common/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';

@Controller('analytics')
export class AnalyticsController {
  @Get('owner/dashboard')
  @Roles(Role.OWNER)
  ownerDashboard() {
    return {
      totalMembers: 0,
      totalTrainers: 0,
      totalGyms: 0,
      occupancyRate: 0,
      averageRating: 0,
    };
  }

  @Get('owner/retention')
  @Roles(Role.OWNER)
  ownerRetention() {
    return {
      month: new Date().toISOString().slice(0, 7),
      retentionPercent: 84.0,
      churnPercent: 16.0,
      predictedAtRisk: 0,
    };
  }

  /** @deprecated — kept for backwards compatibility */
  @Get('retention')
  @Roles(Role.OWNER)
  retention() {
    return {
      month: new Date().toISOString().slice(0, 7),
      retentionPercent: 84.0,
      churnPercent: 16.0,
      predictedAtRisk: 0,
    };
  }
}
