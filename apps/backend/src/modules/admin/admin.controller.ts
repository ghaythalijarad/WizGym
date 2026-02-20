import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';

import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';
import { RequestUser } from '../../common/interfaces/request-user.interface';
import { RejectGymDto } from './dto/reject-gym.dto';
import { UpdateSubscriptionStatusDto } from './dto/update-subscription-status.dto';
import { AdminService } from './admin.service';
import { GymApprovalStatus } from './admin.types';

@Controller('admin')
@Roles(Role.ADMIN)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('dashboard')
  dashboard() {
    return this.adminService.getDashboardSummary();
  }

  @Get('gyms')
  gyms(@Query('status') status?: GymApprovalStatus) {
    return this.adminService.listGyms(status);
  }

  @Get('gyms/pending')
  pendingGyms() {
    return this.adminService.listGyms('PENDING');
  }

  @Post('gyms/:gymId/approve')
  approveGym(@Param('gymId') gymId: string, @CurrentUser() user: RequestUser) {
    return this.adminService.approveGym(gymId, user.name);
  }

  @Post('gyms/:gymId/reject')
  rejectGym(
    @Param('gymId') gymId: string,
    @Body() body: RejectGymDto,
    @CurrentUser() user: RequestUser,
  ) {
    return this.adminService.rejectGym(gymId, user.name, body.note);
  }

  @Get('subscriptions')
  subscriptions() {
    return this.adminService.listSubscriptions();
  }

  @Patch('subscriptions/:subscriptionId/status')
  updateSubscriptionStatus(
    @Param('subscriptionId') subscriptionId: string,
    @Body() body: UpdateSubscriptionStatusDto,
  ) {
    return this.adminService.updateSubscriptionStatus(subscriptionId, body.status);
  }
}
