import { BadGatewayException, Injectable, ServiceUnavailableException } from '@nestjs/common';

export interface OtpiqSendResult {
  messageId: string | null;
  provider: string;
  rawResponse: unknown;
}

export interface OtpiqProjectInfo {
  projectName: string;
  credit: number;
  mocked?: boolean;
}

export interface OtpiqTrackResult {
  smsId: string;
  status: string;
  isFinalStatus: boolean;
  lastChannel: string | null;
  rawResponse: unknown;
}

@Injectable()
export class OtpiqClientService {
  private readonly baseUrl = this.normalizeBaseUrl(
    process.env.OTPIQ_BASE_URL ?? 'https://api.otpiq.com/api',
  );
  private readonly apiKey = this.normalizeApiKey(process.env.OTPIQ_API_KEY);
  private readonly provider = process.env.OTPIQ_PROVIDER ?? 'whatsapp-sms';
  private readonly senderId = process.env.OTPIQ_SENDER_ID;
  private readonly timeoutMs = this.parseNumberEnv('OTPIQ_TIMEOUT_MS', 10000);
  private readonly mockMode = this.parseBooleanEnv('OTPIQ_MOCK_MODE', false);

  async sendVerificationOtp(phoneNumber: string, verificationCode: string): Promise<OtpiqSendResult> {
    if (!this.apiKey) {
      if (this.mockMode) {
        return {
          messageId: null,
          provider: 'mock',
          rawResponse: { mocked: true },
        };
      }

      throw new ServiceUnavailableException('OTPIQ_API_KEY is not configured');
    }

    const payload: Record<string, unknown> = {
      phoneNumber,
      smsType: 'verification',
      verificationCode,
      provider: this.provider,
    };

    if (this.senderId) {
      payload.senderId = this.senderId;
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await fetch(`${this.baseUrl}/sms`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });

      const text = await response.text();
      const body = text ? this.tryParseJson(text) : null;

      if (!response.ok) {
        throw new BadGatewayException(
          `OTPIQ send failed (${response.status}): ${this.errorText(body, text)}`,
        );
      }

      return {
        messageId: this.extractMessageId(body),
        provider: this.provider,
        rawResponse: body ?? text,
      };
    } catch (error) {
      if (error instanceof BadGatewayException || error instanceof ServiceUnavailableException) {
        throw error;
      }

      throw new BadGatewayException('Failed to call OTPIQ API');
    } finally {
      clearTimeout(timeout);
    }
  }

  async getProjectInfo(): Promise<OtpiqProjectInfo> {
    if (!this.apiKey) {
      if (this.mockMode) {
        return {
          projectName: 'Mock Project',
          credit: 0,
          mocked: true,
        };
      }

      throw new ServiceUnavailableException('OTPIQ_API_KEY is not configured');
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await fetch(`${this.baseUrl}/info`, {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
        },
        signal: controller.signal,
      });

      const text = await response.text();
      const body = text ? this.tryParseJson(text) : null;

      if (!response.ok) {
        throw new BadGatewayException(
          `OTPIQ project info failed (${response.status}): ${this.errorText(body, text)}`,
        );
      }

      if (!body || typeof body !== 'object') {
        throw new BadGatewayException('OTPIQ project info response is invalid');
      }

      const payload = body as Record<string, unknown>;
      return {
        projectName: (payload.projectName ?? '').toString(),
        credit: this.toNumber(payload.credit),
      };
    } catch (error) {
      if (error instanceof BadGatewayException || error instanceof ServiceUnavailableException) {
        throw error;
      }

      throw new BadGatewayException('Failed to fetch OTPIQ project info');
    } finally {
      clearTimeout(timeout);
    }
  }

  async trackSms(smsId: string): Promise<OtpiqTrackResult> {
    if (!this.apiKey) {
      if (this.mockMode) {
        return {
          smsId,
          status: 'pending',
          isFinalStatus: false,
          lastChannel: null,
          rawResponse: { mocked: true },
        };
      }

      throw new ServiceUnavailableException('OTPIQ_API_KEY is not configured');
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await fetch(`${this.baseUrl}/sms/track/${encodeURIComponent(smsId)}`, {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
        },
        signal: controller.signal,
      });

      const text = await response.text();
      const body = text ? this.tryParseJson(text) : null;

      if (!response.ok) {
        throw new BadGatewayException(
          `OTPIQ track failed (${response.status}): ${this.errorText(body, text)}`,
        );
      }

      if (!body || typeof body !== 'object') {
        throw new BadGatewayException('OTPIQ track response is invalid');
      }

      const payload = this.unwrapData(body as Record<string, unknown>);
      return {
        smsId: (payload.smsId ?? smsId).toString(),
        status: (payload.status ?? 'unknown').toString(),
        isFinalStatus: Boolean(payload.isFinalStatus),
        lastChannel: payload.lastChannel ? payload.lastChannel.toString() : null,
        rawResponse: body,
      };
    } catch (error) {
      if (error instanceof BadGatewayException || error instanceof ServiceUnavailableException) {
        throw error;
      }

      throw new BadGatewayException('Failed to track OTPIQ SMS status');
    } finally {
      clearTimeout(timeout);
    }
  }

  isMockMode(): boolean {
    return this.mockMode && !this.apiKey;
  }

  private normalizeApiKey(value: string | undefined): string {
    const trimmed = (value ?? '').trim();

    if (!trimmed) {
      return '';
    }

    // Keep `.env` templates usable out-of-the-box.
    if (trimmed.toLowerCase() === 'replace_me') {
      return '';
    }

    return trimmed;
  }

  private normalizeBaseUrl(url: string): string {
    return url.endsWith('/') ? url.slice(0, -1) : url;
  }

  private parseNumberEnv(key: string, fallback: number): number {
    const value = Number.parseInt(process.env[key] ?? '', 10);
    return Number.isFinite(value) ? value : fallback;
  }

  private parseBooleanEnv(key: string, fallback: boolean): boolean {
    const value = process.env[key];

    if (value == null || value === '') {
      return fallback;
    }

    return value.toLowerCase() === 'true';
  }

  private tryParseJson(raw: string): unknown {
    try {
      return JSON.parse(raw);
    } catch {
      return null;
    }
  }

  private extractMessageId(body: unknown): string | null {
    if (!body || typeof body !== 'object') {
      return null;
    }

    const data = body as Record<string, unknown>;
    const direct = data.messageId;
    if (typeof direct === 'string' && direct.length > 0) {
      return direct;
    }

    const nestedData = data.data;
    if (nestedData && typeof nestedData === 'object') {
      const nested = (nestedData as Record<string, unknown>).messageId;
      if (typeof nested === 'string' && nested.length > 0) {
        return nested;
      }
    }

    return null;
  }

  private unwrapData(body: Record<string, unknown>): Record<string, unknown> {
    const nested = body.data;
    if (nested && typeof nested === 'object') {
      return nested as Record<string, unknown>;
    }

    return body;
  }

  private errorText(parsedBody: unknown, rawText: string): string {
    if (parsedBody && typeof parsedBody === 'object') {
      const maybe = (parsedBody as Record<string, unknown>).message;
      if (typeof maybe === 'string' && maybe.length > 0) {
        return maybe;
      }
    }

    return rawText || 'unknown provider error';
  }

  private toNumber(value: unknown): number {
    if (typeof value === 'number') {
      return value;
    }

    const parsed = Number.parseFloat(String(value));
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
