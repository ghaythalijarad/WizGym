import { Controller, Get } from '@nestjs/common';

@Controller('notifications')
export class NotificationsController {
  @Get('channels')
  channels() {
    return {
      enabled: ['push', 'email', 'whatsapp'],
    };
  }
}
