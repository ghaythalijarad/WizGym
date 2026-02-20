import { Controller, Get } from '@nestjs/common';

@Controller('payments')
export class PaymentsController {
  @Get('methods')
  methods() {
    return {
      gateways: ['Stripe', 'Mada', 'STC Pay'],
      currency: 'SAR',
    };
  }
}
