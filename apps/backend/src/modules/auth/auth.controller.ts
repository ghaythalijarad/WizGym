import { Body, Controller, Get, Param, Post } from '@nestjs/common';

import { Roles } from '../../common/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';
import { LoginDto } from './dto/login.dto';
import { RequestPhoneOtpDto } from './dto/request-phone-otp.dto';
import { SignupDto } from './dto/signup.dto';
import { VerifyPhoneOtpDto } from './dto/verify-phone-otp.dto';
import { AuthService } from './auth.service';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('login')
  login(@Body() body: LoginDto) {
    return this.authService.login(body);
  }

  @Post('signup')
  signup(@Body() body: SignupDto) {
    return this.authService.signup(body);
  }

  @Post('phone/send-otp')
  requestPhoneOtp(@Body() body: RequestPhoneOtpDto) {
    return this.authService.requestPhoneOtp(body);
  }

  @Post('phone/verify-otp')
  verifyPhoneOtp(@Body() body: VerifyPhoneOtpDto) {
    return this.authService.verifyPhoneOtp(body);
  }

  @Get('phone/provider-info')
  @Roles(Role.ADMIN)
  providerInfo() {
    return this.authService.getPhoneProviderInfo();
  }

  @Get('phone/track/:sessionId')
  @Roles(Role.ADMIN)
  trackOtp(@Param('sessionId') sessionId: string) {
    return this.authService.getOtpDeliveryStatus(sessionId);
  }
}
