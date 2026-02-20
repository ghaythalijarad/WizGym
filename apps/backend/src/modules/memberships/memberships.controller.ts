import { Controller, Get } from '@nestjs/common';

import { Roles } from '../../common/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';

@Controller('members')
export class MembershipsController {
  @Get('me/plan')
  @Roles(Role.USER)
  getMyPlan() {
    return {
      planName: 'Premium Plus',
      expiresAt: '2026-12-31',
      freezeDaysRemaining: 12,
      sessionsLeft: 7,
    };
  }
}
