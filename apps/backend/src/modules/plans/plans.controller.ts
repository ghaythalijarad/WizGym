import { Controller, Get } from '@nestjs/common';

@Controller('plans')
export class PlansController {
  @Get('templates')
  templates() {
    return {
      plans: [
        { id: 'p-1', name: 'Fat Loss 8 Weeks', level: 'Beginner' },
        { id: 'p-2', name: 'Strength Split', level: 'Intermediate' },
      ],
    };
  }
}
