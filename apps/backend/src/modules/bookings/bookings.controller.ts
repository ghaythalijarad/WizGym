import { Controller, Get } from '@nestjs/common';

@Controller('bookings')
export class BookingsController {
  @Get('summary')
  getSummary() {
    return {
      upcoming: 3,
      waitlist: 1,
      completedThisMonth: 14,
    };
  }
}
