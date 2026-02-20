import {
  BadRequestException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { createHash, randomBytes, randomInt, randomUUID } from 'crypto';

import { Role } from '../../common/enums/role.enum';
import { MongoService } from '../../infrastructure/mongo/mongo.service';
import { AccountRole, PhoneVerificationSessionDocument, UserAccountDocument } from '../../infrastructure/mongo/mongo.types';
import { LoginDto } from './dto/login.dto';
import { RequestPhoneOtpDto } from './dto/request-phone-otp.dto';
import { SignupDto } from './dto/signup.dto';
import { VerifyPhoneOtpDto } from './dto/verify-phone-otp.dto';
import { OtpiqClientService, OtpiqSendResult } from './providers/otpiq-client.service';

@Injectable()
export class AuthService {
  private readonly otpLength = this.bound(
    this.parseIntEnv('PHONE_OTP_LENGTH', 6),
    4,
    8,
  );
  private readonly otpTtlSeconds = this.bound(
    this.parseIntEnv('PHONE_OTP_TTL_SECONDS', 300),
    60,
    1200,
  );
  private readonly otpMaxAttempts = this.bound(
    this.parseIntEnv('PHONE_OTP_MAX_ATTEMPTS', 5),
    1,
    10,
  );
  private readonly otpRateLimitSeconds = this.bound(
    this.parseIntEnv('PHONE_OTP_RATE_LIMIT_SECONDS', 45),
    5,
    300,
  );

  constructor(
    private readonly mongo: MongoService,
    private readonly otpiqClient: OtpiqClientService,
  ) {}

  async login(body: LoginDto) {
    const phoneNumber = this.normalizePhone(body.phoneNumber);
    await this.assertRecentlyVerifiedPhone(phoneNumber);

    const account = await this.mongo.userAccounts.findOne({ phoneNumber });

    if (!account) {
      throw new UnauthorizedException('Account not found. Complete signup first');
    }

    const now = new Date();
    await this.mongo.userAccounts.updateOne(
      { id: account.id },
      { $set: { lastLoginAt: now, updatedAt: now } },
    );

    return this.buildAuthResponse({
      id: account.id,
      phoneNumber: account.phoneNumber,
      displayName: account.displayName,
      role: account.role,
    });
  }

  async signup(body: SignupDto) {
    const phoneNumber = this.normalizePhone(body.phoneNumber);
    await this.assertRecentlyVerifiedPhone(phoneNumber);

    if (body.role === Role.ADMIN) {
      throw new BadRequestException('ADMIN accounts cannot be self-registered');
    }

    const existing = await this.mongo.userAccounts.findOne(
      { phoneNumber },
      { projection: { id: 1 } },
    );

    if (existing) {
      throw new BadRequestException('Account already exists for this phone number. Use login');
    }

    const now = new Date();
    const account: UserAccountDocument = {
      id: randomUUID(),
      phoneNumber,
      displayName: this.resolveDisplayName(body.displayName, phoneNumber, body.role),
      role: this.toAccountRole(body.role),
      createdAt: now,
      updatedAt: now,
    };

    await this.mongo.userAccounts.insertOne(account);

    return this.buildAuthResponse(account);
  }

  async getPhoneProviderInfo() {
    return this.otpiqClient.getProjectInfo();
  }

  async getOtpDeliveryStatus(sessionId: string) {
    const session = await this.mongo.phoneVerificationSessions.findOne(
      { id: sessionId },
      {
        projection: {
          id: 1,
          phoneNumber: 1,
          smsId: 1,
          provider: 1,
          status: 1,
          createdAt: 1,
          updatedAt: 1,
        },
      },
    );

    if (!session) {
      throw new NotFoundException(`OTP session ${sessionId} not found`);
    }

    if (!session.smsId) {
      return {
        sessionId: session.id,
        phoneNumber: session.phoneNumber,
        internalStatus: session.status,
        providerStatus: 'not_available',
        provider: session.provider,
        message: 'SMS provider message ID is not available for this session',
      };
    }

    const providerStatus = await this.otpiqClient.trackSms(session.smsId);

    return {
      sessionId: session.id,
      phoneNumber: session.phoneNumber,
      internalStatus: session.status,
      provider: session.provider,
      providerStatus,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
    };
  }

  async requestPhoneOtp(body: RequestPhoneOtpDto) {
    const phoneNumber = this.normalizePhone(body.phoneNumber);

    await this.expireStaleOtps(phoneNumber);
    await this.enforceRateLimit(phoneNumber);

    const verificationCode = this.generateOtpCode();
    const salt = randomBytes(16).toString('hex');
    const now = new Date();

    const session: PhoneVerificationSessionDocument = {
      id: randomUUID(),
      phoneNumber,
      codeSalt: salt,
      codeHash: this.hashCode(verificationCode, salt),
      expiresAt: new Date(Date.now() + this.otpTtlSeconds * 1000),
      maxAttempts: this.otpMaxAttempts,
      attempts: 0,
      status: 'PENDING',
      createdAt: now,
      updatedAt: now,
    };

    await this.mongo.phoneVerificationSessions.insertOne(session);

    let sendResult: OtpiqSendResult;
    try {
      sendResult = await this.otpiqClient.sendVerificationOtp(phoneNumber, verificationCode);
    } catch (error) {
      await this.mongo.phoneVerificationSessions.updateOne(
        { id: session.id },
        { $set: { status: 'FAILED', updatedAt: new Date() } },
      );

      throw error;
    }

    await this.mongo.phoneVerificationSessions.updateOne(
      { id: session.id },
      {
        $set: {
          smsId: sendResult.messageId ?? undefined,
          provider: sendResult.provider,
          updatedAt: new Date(),
        },
      },
    );

    const updated = await this.mongo.phoneVerificationSessions.findOne({ id: session.id });

    if (!updated) {
      throw new NotFoundException(`OTP session ${session.id} not found after creation`);
    }

    const response: Record<string, unknown> = {
      sessionId: updated.id,
      phoneNumber: updated.phoneNumber,
      expiresAt: updated.expiresAt,
      message: 'OTP sent successfully',
      deliveryProvider: updated.provider ?? sendResult.provider,
    };

    if (this.otpiqClient.isMockMode()) {
      response.mockCode = verificationCode;
    }

    return response;
  }

  async verifyPhoneOtp(body: VerifyPhoneOtpDto) {
    const phoneNumber = this.normalizePhone(body.phoneNumber);
    await this.expireStaleOtps(phoneNumber);

    const session = await this.mongo.phoneVerificationSessions
      .find({
        phoneNumber,
        status: 'PENDING',
      })
      .sort({ createdAt: -1 })
      .limit(1)
      .next();

    if (!session) {
      throw new UnauthorizedException('No active OTP session found');
    }

    if (session.expiresAt.getTime() < Date.now()) {
      await this.mongo.phoneVerificationSessions.updateOne(
        { id: session.id },
        { $set: { status: 'EXPIRED', updatedAt: new Date() } },
      );

      throw new UnauthorizedException('OTP has expired');
    }

    if (session.attempts >= session.maxAttempts) {
      await this.mongo.phoneVerificationSessions.updateOne(
        { id: session.id },
        { $set: { status: 'FAILED', updatedAt: new Date() } },
      );

      throw new HttpException('OTP attempts exceeded', HttpStatus.TOO_MANY_REQUESTS);
    }

    const valid = this.hashCode(body.code, session.codeSalt) === session.codeHash;

    if (!valid) {
      const attempts = session.attempts + 1;
      await this.mongo.phoneVerificationSessions.updateOne(
        { id: session.id },
        {
          $set: {
            attempts,
            status: attempts >= session.maxAttempts ? 'FAILED' : 'PENDING',
            updatedAt: new Date(),
          },
        },
      );

      throw new UnauthorizedException('Invalid OTP code');
    }

    const verifiedAt = new Date();
    await this.mongo.phoneVerificationSessions.updateOne(
      { id: session.id },
      {
        $set: {
          status: 'VERIFIED',
          verifiedAt,
          updatedAt: verifiedAt,
        },
      },
    );

    const account = await this.mongo.userAccounts.findOne(
      { phoneNumber },
      { projection: { id: 1 } },
    );

    return {
      verified: true,
      phoneNumber,
      verifiedAt,
      sessionId: session.id,
      accountExists: Boolean(account),
    };
  }

  private async expireStaleOtps(phoneNumber: string) {
    await this.mongo.phoneVerificationSessions.updateMany(
      {
        phoneNumber,
        status: 'PENDING',
        expiresAt: { $lt: new Date() },
      },
      { $set: { status: 'EXPIRED', updatedAt: new Date() } },
    );
  }

  private async enforceRateLimit(phoneNumber: string) {
    const latest = await this.mongo.phoneVerificationSessions
      .find({ phoneNumber })
      .sort({ createdAt: -1 })
      .limit(1)
      .next();

    if (!latest) {
      return;
    }

    const elapsed = Date.now() - latest.createdAt.getTime();
    if (elapsed < this.otpRateLimitSeconds * 1000) {
      throw new HttpException(
        `Please wait ${Math.ceil((this.otpRateLimitSeconds * 1000 - elapsed) / 1000)}s before requesting another OTP`,
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  private normalizePhone(raw: string): string {
    const normalized = raw.replace(/[^\d]/g, '');

    if (!/^\d{9,15}$/.test(normalized)) {
      throw new BadRequestException('Invalid phone number format');
    }

    return normalized;
  }

  private hashCode(code: string, salt: string): string {
    return createHash('sha256').update(`${code}:${salt}`).digest('hex');
  }

  private generateOtpCode(): string {
    const min = 10 ** (this.otpLength - 1);
    const max = 10 ** this.otpLength;
    return randomInt(min, max).toString();
  }

  private async assertRecentlyVerifiedPhone(phoneNumber: string) {
    const session = await this.mongo.phoneVerificationSessions
      .find({
        phoneNumber,
        status: 'VERIFIED',
        verifiedAt: { $exists: true },
      })
      .sort({ verifiedAt: -1 })
      .limit(1)
      .next();

    if (!session || !session.verifiedAt) {
      throw new UnauthorizedException('Phone number is not verified yet');
    }

    const ageMs = Date.now() - session.verifiedAt.getTime();
    if (ageMs > this.otpTtlSeconds * 1000) {
      throw new UnauthorizedException('Phone verification has expired. Request a new OTP');
    }
  }

  private buildAuthResponse(account: Pick<UserAccountDocument, 'id' | 'phoneNumber' | 'displayName' | 'role'>) {
    const role = this.toRole(account.role);

    return {
      token: `mock-jwt-token-for-${role.toLowerCase()}-${account.id}`,
      refreshToken: `mock-refresh-token-${account.id}`,
      profile: {
        id: account.id,
        role,
        displayName: account.displayName,
        phoneNumber: account.phoneNumber,
      },
    };
  }

  private toAccountRole(role: Role): AccountRole {
    if (role === Role.ADMIN || role === Role.OWNER || role === Role.TRAINER || role === Role.USER) {
      return role;
    }

    throw new BadRequestException('Unsupported role value');
  }

  private toRole(role: AccountRole): Role {
    if (role === 'ADMIN') {
      return Role.ADMIN;
    }

    if (role === 'OWNER') {
      return Role.OWNER;
    }

    if (role === 'TRAINER') {
      return Role.TRAINER;
    }

    return Role.USER;
  }

  private resolveDisplayName(
    displayName: string | undefined,
    phoneNumber: string,
    role: Role,
  ): string {
    const value = displayName?.trim();
    if (value) {
      return value;
    }

    return `${role.toLowerCase()}-${phoneNumber.slice(-4)}`;
  }

  private parseIntEnv(key: string, fallback: number): number {
    const parsed = Number.parseInt(process.env[key] ?? '', 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private bound(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max);
  }
}
