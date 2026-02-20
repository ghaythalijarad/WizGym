import { Controller, Get } from '@nestjs/common';

import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequestUser } from '../../common/interfaces/request-user.interface';

@Controller('users')
export class UsersController {
  @Get('me')
  getMe(@CurrentUser() user: RequestUser) {
    return {
      ...user,
      locale: 'ar',
      timezone: 'Asia/Riyadh',
    };
  }
}
