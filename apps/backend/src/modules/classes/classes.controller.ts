import { Controller, Get } from '@nestjs/common';

@Controller('classes')
export class ClassesController {
  @Get('today')
  todayClasses() {
    return {
      date: '2026-02-13',
      list: [
        { id: 'c-1', title: 'HIIT', start: '18:00', capacity: 20, available: 5 },
        { id: 'c-2', title: 'Yoga', start: '20:00', capacity: 15, available: 4 },
      ],
    };
  }
}
