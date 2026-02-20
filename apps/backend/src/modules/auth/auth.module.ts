import { Module } from '@nestjs/common';

import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { OtpiqClientService } from './providers/otpiq-client.service';

@Module({
  controllers: [AuthController],
  providers: [AuthService, OtpiqClientService],
})
export class AuthModule {}
