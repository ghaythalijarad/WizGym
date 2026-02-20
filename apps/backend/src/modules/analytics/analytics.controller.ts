import { Controller, Get } from '@nestjs/common';

import { Roles } from '../../common/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';

@Controller('analytics')
export class AnalyticsController {
  @Get('retention')
  @Roles(Role.OWNER)
  retention() {
    return {
      month: '2026-02',
      retentionRate: 0.84,
      churnRate: 0.16,
      predictedAtRisk: 52,
    };
  }
}
