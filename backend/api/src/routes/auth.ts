import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';
import { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';
import { randomBytes } from 'crypto';
import { otpiqService } from '../services/otpiq.service';

const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME || 'wizgym-prod-core';

// Always strip leading + so GSI2PK is consistent: "PHONE#9647831367435"
function normalizePhone(phone: string): string {
  return phone.replace(/^\+/, '');
}

interface LoginRequest {
  phoneNumber: string;
  role: string;
  password: string;
}

interface SignupRequest {
  phoneNumber: string;
  role: string;
  password: string;
  displayName?: string;
  sessionId: string;
  otp: string;
}

interface SendOtpRequest {
  phoneNumber: string;
}

// Simple JWT-like token generation (in production, use proper JWT library)
function generateToken(userId: string): string {
  return Buffer.from(JSON.stringify({
    userId,
    exp: Date.now() + 24 * 60 * 60 * 1000 // 24 hours
  })).toString('base64');
}

function generateRefreshToken(): string {
  return randomBytes(32).toString('hex');
}

export async function handleAuth(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || '';
  const method = event.requestContext.http.method;

  // Handle login
  if (path.endsWith('/auth/login') && method === 'POST') {
    return await handleLogin(event, docClient);
  }

  // Handle signup
  if (path.endsWith('/auth/signup') && method === 'POST') {
    return await handleSignup(event, docClient);
  }

  // Handle send OTP
  if (path.endsWith('/auth/phone/send-otp') && method === 'POST') {
    return await handleSendOTP(event, docClient);
  }

  // Handle verify OTP
  if (path.endsWith('/auth/phone/verify-otp') && method === 'POST') {
    return await handleVerifyOTP(event, docClient);
  }

  return {
    statusCode: 404,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: 'Auth endpoint not found' }),
  };
}

async function handleLogin(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  try {
    const body: LoginRequest = JSON.parse(event.body || '{}');
    const { phoneNumber, role, password } = body;

    if (!phoneNumber || !password) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'رقم الهاتف وكلمة السر مطلوبان' }),
      };
    }

    const phone = normalizePhone(phoneNumber);

    // Query user by phone using GSI2, then filter by role
    const result = await docClient.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        IndexName: 'GSI2',
        KeyConditionExpression: 'GSI2PK = :phone',
        ExpressionAttributeValues: {
          ':phone': `PHONE#${phone}`,
        },
      })
    );

    // Find user with matching role
    const user = result.Items?.find(item => item.role === role);

    if (!user) {
      return {
        statusCode: 404,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'المستخدم غير موجود' }),
      };
    }

    // In production, use bcrypt to compare passwords
    // For now, simple comparison (REPLACE THIS IN PRODUCTION!)
    if (user.password !== password) {
      return {
        statusCode: 401,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'كلمة السر غير صحيحة' }),
      };
    }

    const token = generateToken(user.id);
    const refreshToken = generateRefreshToken();

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        token,
        refreshToken,
        profile: {
          id: user.id,
          phoneNumber: user.phoneNumber,
          displayName: user.displayName || '',
          role: user.role,
        },
      }),
    };
  } catch (error) {
    console.error('Login error:', error);
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: 'خطأ في الخادم' }),
    };
  }
}

async function handleSendOTP(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  try {
    const body: SendOtpRequest = JSON.parse(event.body || '{}');
    const { phoneNumber } = body;

    if (!phoneNumber) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'رقم الهاتف مطلوب' }),
      };
    }

    // Send OTP via OTPIQ service
    const otpResponse = await otpiqService.sendOTP(phoneNumber);

    if (!otpResponse.success) {
      return {
        statusCode: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          message: 'فشل إرسال رمز التحقق',
          error: otpResponse.error 
        }),
      };
    }

    const sessionId = otpResponse.sessionId || randomBytes(16).toString('hex');
    const expiresAt = Date.now() + 5 * 60 * 1000; // 5 minutes

    // Store OTP session in DynamoDB — always store phone WITHOUT + for consistent comparison
    const normalizedPhone = normalizePhone(phoneNumber);
    await docClient.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          PK: `OTP#${sessionId}`,
          SK: `SESSION`,
          phoneNumber: normalizedPhone,
          code: otpResponse.otpCode || '', // Store the generated code for later comparison
          expiresAt,
          verified: false,
          createdAt: new Date().toISOString(),
          ttl: Math.floor(expiresAt / 1000), // DynamoDB TTL
        },
      })
    );

    console.log(`[OTP] Sent to ${phoneNumber} via ${otpiqService.getStatus().provider}`);

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sessionId,
        message: 'تم إرسال رمز التحقق',
      }),
    };
  } catch (error) {
    console.error('Send OTP error:', error);
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: 'خطأ في إرسال الرمز' }),
    };
  }
}

async function handleVerifyOTP(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  try {
    const body = JSON.parse(event.body || '{}');
    const { sessionId, otp } = body;

    if (!sessionId || !otp) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'معرف الجلسة والرمز مطلوبان' }),
      };
    }

    // Get OTP session
    const result = await docClient.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: {
          PK: `OTP#${sessionId}`,
          SK: 'SESSION',
        },
      })
    );

    const session = result.Item;

    if (!session) {
      return {
        statusCode: 404,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'جلسة غير صالحة' }),
      };
    }

    if (session.expiresAt < Date.now()) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'انتهت صلاحية الرمز' }),
      };
    }

    if (session.code !== otp) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'الرمز غير صحيح' }),
      };
    }

    // Mark as verified
    await docClient.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          ...session,
          verified: true,
          verifiedAt: new Date().toISOString(),
        },
      })
    );

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        verified: true,
        phoneNumber: session.phoneNumber,
        message: 'تم التحقق بنجاح',
      }),
    };
  } catch (error) {
    console.error('Verify OTP error:', error);
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: 'خطأ في التحقق' }),
    };
  }
}

async function handleSignup(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  try {
    const body: SignupRequest = JSON.parse(event.body || '{}');
    const { phoneNumber, role, password, displayName, sessionId, otp } = body;

    if (!phoneNumber || !password || !sessionId || !otp) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'جميع الحقول مطلوبة' }),
      };
    }

    // Verify OTP first
    const otpResult = await docClient.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: {
          PK: `OTP#${sessionId}`,
          SK: 'SESSION',
        },
      })
    );

    const otpSession = otpResult.Item;

    if (!otpSession) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'جلسة التحقق غير صالحة أو منتهية' }),
      };
    }

    if (otpSession.expiresAt < Date.now()) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'انتهت صلاحية رمز التحقق' }),
      };
    }

    if (otpSession.code !== otp) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'رمز التحقق غير صحيح' }),
      };
    }

    // Normalize both sides before comparing (strip leading +)
    const sessionPhone = normalizePhone(otpSession.phoneNumber as string);
    const requestPhone = normalizePhone(phoneNumber);
    if (sessionPhone !== requestPhone) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'رقم الهاتف لا يتطابق مع جلسة التحقق' }),
      };
    }

    // Check if user already exists with this phone and role
    const existingUser = await docClient.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        IndexName: 'GSI2',
        KeyConditionExpression: 'GSI2PK = :phone',
        ExpressionAttributeValues: {
          ':phone': `PHONE#${requestPhone}`,
        },
      })
    );

    // Check if any user with this phone has the same role
    const userWithSameRole = existingUser.Items?.find(item => item.role === role);
    if (userWithSameRole) {
      return {
        statusCode: 409,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: 'المستخدم موجود بالفعل' }),
      };
    }

    // Create new user
    const userId = `USER#${randomBytes(16).toString('hex')}`;
    const userRole = role || 'USER';

    await docClient.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          PK: userId,
          SK: 'PROFILE',
          GSI2PK: `PHONE#${requestPhone}`,
          GSI2SK: `ROLE#${userRole}#${userId}`,
          id: userId,
          phoneNumber: requestPhone,
          password, // In production, hash this with bcrypt!
          displayName: displayName || '',
          role: userRole,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        },
      })
    );

    const token = generateToken(userId);
    const refreshToken = generateRefreshToken();

    return {
      statusCode: 201,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        token,
        refreshToken,
        profile: {
          id: userId,
          phoneNumber: requestPhone,
          displayName: displayName || '',
          role: userRole,
        },
      }),
    };
  } catch (error) {
    console.error('Signup error:', error);
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: 'خطأ في إنشاء الحساب' }),
    };
  }
}
