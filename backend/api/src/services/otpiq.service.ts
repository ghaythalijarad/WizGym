// filepath: apps/api/src/services/otpiq.service.ts
import { GetParameterCommand, SSMClient } from "@aws-sdk/client-ssm";
import { randomBytes, randomInt } from 'crypto';
import http from "http";
import https from "https";

interface OTPIQConfig {
  apiKey: string;
  baseUrl: string;
  provider: string;
  senderId?: string;
  mockMode: boolean;
}

interface SendOTPResponse {
  success: boolean;
  sessionId?: string;
  otpCode?: string;
  message?: string;
  error?: string;
}

export class OTPIQService {
  private config: OTPIQConfig;
  private ssmClient: SSMClient;
  private apiKeyLoaded: boolean = false;

  constructor() {
    this.ssmClient = new SSMClient({ region: process.env.AWS_REGION || 'us-east-1' });
    this.config = {
      apiKey: process.env.OTPIQ_API_KEY || '',
      baseUrl: process.env.OTPIQ_BASE_URL || 'https://api.otpiq.com/api',
      provider: process.env.OTPIQ_PROVIDER || 'whatsapp-sms',
      senderId: process.env.OTPIQ_SENDER_ID || '',
      mockMode: false, // Always use real OTP IQ - No mock mode
    };
  }

  /**
   * Load API key from SSM Parameter Store
   */
  private async loadApiKey(): Promise<void> {
    if (this.apiKeyLoaded || this.config.apiKey) {
      return;
    }

    try {
      const command = new GetParameterCommand({
        Name: '/wizgym/prod/OTPIQ_API_KEY',
        WithDecryption: true,
      });

      const response = await this.ssmClient.send(command);
      if (response.Parameter?.Value) {
        this.config.apiKey = response.Parameter.Value;
        this.apiKeyLoaded = true;
        console.log('[OTPIQ] API key loaded from Parameter Store');
      }
    } catch (error) {
      console.error('[OTPIQ] Failed to load API key from Parameter Store:', error);
      // Continue with mock mode if API key is not available
    }
  }

  /**
   * Generate a cryptographically secure 6-digit OTP code
   */
  private generateOTP(): string {
    return randomInt(100000, 999999).toString();
  }

  /**
   * Send OTP via OTPIQ service
   */
  async sendOTP(phoneNumber: string, message?: string): Promise<SendOTPResponse> {
    // Load API key from Parameter Store if not already loaded
    await this.loadApiKey();

    const otpCode = this.generateOTP();

    // Check if API key is available
    if (!this.config.apiKey) {
      console.error('[OTPIQ] API key is not configured! Cannot send OTP.');
      return {
        success: false,
        error: 'OTP service is not configured. Please contact support.',
      };
    }

    // Real OTPIQ API call - NO MOCK MODE
    try {
      const payload: Record<string, string> = {
        phoneNumber: phoneNumber.replace(/^\+/, ''), // Remove + prefix, pattern ^[0-9]{10,15}$
        smsType: 'verification',                     // Required for OTP codes
        verificationCode: otpCode,                   // 1–20 chars
        provider: this.config.provider,
        ...(this.config.senderId && { senderId: this.config.senderId }),
      };

      console.log(`[OTPIQ] Sending OTP to ${phoneNumber} via ${this.config.provider}`);
      const response = await this.makeRequest('/sms', payload);
      console.log(`[OTPIQ] API response:`, JSON.stringify(response));

      // OTPIQ returns { message, smsId, remainingCredit, cost, canCover, paymentType }
      // A missing smsId or an explicit error field indicates failure
      if (response.smsId) {
        console.log(`[OTPIQ] OTP sent successfully. smsId=${response.smsId}`);
        return {
          success: true,
          sessionId: response.smsId || this.generateSessionId(),
          otpCode,           // Return the code so the caller can store it for verification
          message: 'OTP sent successfully',
        };
      } else {
        console.error(`[OTPIQ] Failed to send OTP:`, response);
        return {
          success: false,
          error: response.message || 'Failed to send OTP',
        };
      }
    } catch (error) {
      console.error('[OTPIQ] Error sending OTP:', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
      };
    }
  }

  /**
   * Make HTTP request to OTPIQ API
   */
  private async makeRequest(endpoint: string, data: any): Promise<any> {
    return new Promise((resolve, reject) => {
      // Ensure baseUrl ends with '/' so relative segments are resolved correctly.
      // e.g. new URL('sms', 'https://api.otpiq.com/api/') → 'https://api.otpiq.com/api/sms'
      const base = this.config.baseUrl.endsWith('/') ? this.config.baseUrl : this.config.baseUrl + '/';
      const url = new URL(endpoint.replace(/^\//, ''), base);
      const isHttps = url.protocol === 'https:';
      const lib = isHttps ? https : http;

      const postData = JSON.stringify(data);

      const options = {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(postData),
          'Authorization': `Bearer ${this.config.apiKey}`,
        },
      };

      const req = lib.request(url, options, (res) => {
        let body = '';

        res.on('data', (chunk) => {
          body += chunk;
        });

        res.on('end', () => {
          try {
            const response = JSON.parse(body);
            resolve(response);
          } catch (error) {
            reject(new Error(`Invalid JSON response: ${body}`));
          }
        });
      });

      req.on('error', (error) => {
        reject(error);
      });

      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Request timeout'));
      });

      req.setTimeout(10000); // 10 seconds timeout

      req.write(postData);
      req.end();
    });
  }

  /**
   * Generate a cryptographically secure session ID
   */
  private generateSessionId(): string {
    return randomBytes(16).toString('hex');
  }

  /**
   * Check if OTPIQ is properly configured
   */
  isConfigured(): boolean {
    return !!(this.config.apiKey && this.config.baseUrl);
  }

  /**
   * Get current configuration status
   */
  getStatus(): {
    configured: boolean;
    mockMode: boolean;
    provider: string;
  } {
    return {
      configured: this.isConfigured(),
      mockMode: false, // Always false - no mock mode
      provider: this.config.provider,
    };
  }
}

// Export singleton instance
export const otpiqService = new OTPIQService();
