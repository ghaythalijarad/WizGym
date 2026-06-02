import { GetParameterCommand, SSMClient } from "@aws-sdk/client-ssm";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";
import bcrypt from "bcryptjs";
import { createHmac, randomBytes, randomInt } from "crypto";
import { otpiqService } from "../services/otpiq.service";

const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME || "wizgym-prod-core";
const BCRYPT_ROUNDS = 10;
const TOKEN_EXPIRY_MS = 24 * 60 * 60 * 1000; // 24 hours
const MAX_OTP_ATTEMPTS = 5; // max wrong OTP attempts before lockout

const ssmClient = new SSMClient({
  region: process.env.AWS_REGION || "us-east-1",
});
let cachedJwtSecret: string | null = null;

async function getJwtSecret(): Promise<string> {
  if (cachedJwtSecret) return cachedJwtSecret;
  try {
    const res = await ssmClient.send(
      new GetParameterCommand({
        Name: "/wizgym/prod/JWT_SECRET",
        WithDecryption: true,
      })
    );
    cachedJwtSecret = res.Parameter?.Value || "";
  } catch (e) {
    console.error("[Auth] Failed to load JWT secret from SSM:", e);
    // Fallback to env var (less secure but keeps Lambda functional)
    cachedJwtSecret = process.env.JWT_SECRET || "";
  }
  return cachedJwtSecret;
}

// Always strip leading + so GSI2PK is consistent: "PHONE#9647831367435"
function normalizePhone(phone: string): string {
  return phone.replace(/^\+/, "");
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

// ── Secure HMAC-SHA256 JWT ──────────────────────────────────────────────────

async function generateToken(userId: string): Promise<string> {
  const secret = await getJwtSecret();
  const payload = {
    sub: userId,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor((Date.now() + TOKEN_EXPIRY_MS) / 1000),
  };
  const header = Buffer.from(
    JSON.stringify({ alg: "HS256", typ: "JWT" })
  ).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const sig = createHmac("sha256", secret)
    .update(`${header}.${body}`)
    .digest("base64url");
  return `${header}.${body}.${sig}`;
}

function generateRefreshToken(): string {
  return randomBytes(32).toString("hex");
}

// ── Cryptographically secure 6-digit OTP ────────────────────────────────────

function generateSecureOTP(): string {
  return randomInt(100000, 999999).toString();
}

export async function handleAuth(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || "";
  const method = event.requestContext.http.method;

  // Handle login
  if (path.endsWith("/auth/login") && method === "POST") {
    return await handleLogin(event, docClient);
  }

  // Handle signup
  if (path.endsWith("/auth/signup") && method === "POST") {
    return await handleSignup(event, docClient);
  }

  // Handle send OTP
  if (path.endsWith("/auth/phone/send-otp") && method === "POST") {
    return await handleSendOTP(event, docClient);
  }

  // Handle verify OTP
  if (path.endsWith("/auth/phone/verify-otp") && method === "POST") {
    return await handleVerifyOTP(event, docClient);
  }

  return {
    statusCode: 404,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: "Auth endpoint not found" }),
  };
}

async function handleLogin(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  try {
    const body: LoginRequest = JSON.parse(event.body || "{}");
    const { phoneNumber, role, password } = body;

    if (!phoneNumber || !password) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "رقم الهاتف وكلمة السر مطلوبان" }),
      };
    }

    const phone = normalizePhone(phoneNumber);

    // Query user by phone using GSI2, then filter by role
    const result = await docClient.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        IndexName: "GSI2",
        KeyConditionExpression: "GSI2PK = :phone",
        ExpressionAttributeValues: {
          ":phone": `PHONE#${phone}`,
        },
      })
    );

    // Find user with matching role
    const user = result.Items?.find((item) => item.role === role);

    if (!user) {
      return {
        statusCode: 404,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "المستخدم غير موجود" }),
      };
    }

    // ── Secure password comparison ──
    // Support both legacy plaintext (auto-upgrade) and bcrypt hashes
    const storedPassword = String(user.password || "");
    let passwordValid = false;

    if (
      storedPassword.startsWith("$2a$") ||
      storedPassword.startsWith("$2b$")
    ) {
      // Already bcrypt-hashed
      passwordValid = await bcrypt.compare(password, storedPassword);
    } else {
      // Legacy plaintext — compare, then upgrade to bcrypt
      passwordValid = storedPassword === password;
      if (passwordValid) {
        const hashed = await bcrypt.hash(password, BCRYPT_ROUNDS);
        try {
          await docClient.send(
            new UpdateCommand({
              TableName: TABLE_NAME,
              Key: { PK: user.PK || user.id, SK: "PROFILE" },
              UpdateExpression: "SET password = :hp",
              ExpressionAttributeValues: { ":hp": hashed },
            })
          );
          console.log(`[Auth] Auto-upgraded plaintext password for ${phone}`);
        } catch {
          /* non-fatal */
        }
      }
    }

    if (!passwordValid) {
      return {
        statusCode: 401,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "كلمة السر غير صحيحة" }),
      };
    }

    const token = await generateToken(user.id);
    const refreshToken = generateRefreshToken();

    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        token,
        refreshToken,
        profile: {
          id: user.id,
          phoneNumber: user.phoneNumber,
          displayName: user.displayName || "",
          role: user.role,
        },
      }),
    };
  } catch (error) {
    console.error("Login error:", error);
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: "خطأ في الخادم" }),
    };
  }
}

async function handleSendOTP(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  try {
    const body: SendOtpRequest = JSON.parse(event.body || "{}");
    const { phoneNumber } = body;

    if (!phoneNumber) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "رقم الهاتف مطلوب" }),
      };
    }

    // Send OTP via OTPIQ service
    const otpResponse = await otpiqService.sendOTP(phoneNumber);

    if (!otpResponse.success) {
      return {
        statusCode: 500,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: "فشل إرسال رمز التحقق",
          error: otpResponse.error,
        }),
      };
    }

    const sessionId = otpResponse.sessionId || randomBytes(16).toString("hex");
    const expiresAt = Date.now() + 5 * 60 * 1000; // 5 minutes

    // Store OTP session in DynamoDB — always store phone WITHOUT + for consistent comparison
    const normalizedPhone = normalizePhone(phoneNumber);

    // Use the cryptographically secure OTP returned by the service,
    // or generate one if the service didn't provide it
    const otpCode = otpResponse.otpCode || generateSecureOTP();

    await docClient.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          PK: `OTP#${sessionId}`,
          SK: `SESSION`,
          phoneNumber: normalizedPhone,
          code: otpCode,
          expiresAt,
          verified: false,
          attempts: 0,
          createdAt: new Date().toISOString(),
          ttl: Math.floor(expiresAt / 1000), // DynamoDB TTL
        },
      })
    );

    console.log(
      `[OTP] Sent to ${phoneNumber} via ${otpiqService.getStatus().provider}`
    );

    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        sessionId,
        message: "تم إرسال رمز التحقق",
      }),
    };
  } catch (error) {
    console.error("Send OTP error:", error);
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: "خطأ في إرسال الرمز" }),
    };
  }
}

async function handleVerifyOTP(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  try {
    const body = JSON.parse(event.body || "{}");
    const { sessionId, otp } = body;

    if (!sessionId || !otp) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "معرف الجلسة والرمز مطلوبان" }),
      };
    }

    // Get OTP session
    const result = await docClient.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: {
          PK: `OTP#${sessionId}`,
          SK: "SESSION",
        },
      })
    );

    const session = result.Item;

    if (!session) {
      return {
        statusCode: 404,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "جلسة غير صالحة" }),
      };
    }

    if (session.expiresAt < Date.now()) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "انتهت صلاحية الرمز" }),
      };
    }

    // ── Brute-force protection: max attempts ──
    const attempts = Number(session.attempts || 0);
    if (attempts >= MAX_OTP_ATTEMPTS) {
      return {
        statusCode: 429,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: "تم تجاوز الحد الأقصى من المحاولات. أعد إرسال الرمز.",
        }),
      };
    }

    if (session.code !== otp) {
      // Increment attempt counter
      await docClient.send(
        new UpdateCommand({
          TableName: TABLE_NAME,
          Key: { PK: `OTP#${sessionId}`, SK: "SESSION" },
          UpdateExpression: "SET attempts = :a",
          ExpressionAttributeValues: { ":a": attempts + 1 },
        })
      );
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "الرمز غير صحيح" }),
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
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        verified: true,
        phoneNumber: session.phoneNumber,
        message: "تم التحقق بنجاح",
      }),
    };
  } catch (error) {
    console.error("Verify OTP error:", error);
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: "خطأ في التحقق" }),
    };
  }
}

async function handleSignup(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  try {
    const body: SignupRequest = JSON.parse(event.body || "{}");
    const { phoneNumber, role, password, displayName, sessionId, otp } = body;

    if (!phoneNumber || !password || !sessionId || !otp) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "جميع الحقول مطلوبة" }),
      };
    }

    // Password strength validation
    if (password.length < 6) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: "كلمة السر يجب أن تكون 6 أحرف على الأقل",
        }),
      };
    }

    // Verify OTP first
    const otpResult = await docClient.send(
      new GetCommand({
        TableName: TABLE_NAME,
        Key: {
          PK: `OTP#${sessionId}`,
          SK: "SESSION",
        },
      })
    );

    const otpSession = otpResult.Item;

    if (!otpSession) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "جلسة التحقق غير صالحة أو منتهية" }),
      };
    }

    if (otpSession.expiresAt < Date.now()) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "انتهت صلاحية رمز التحقق" }),
      };
    }

    if (otpSession.code !== otp) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "رمز التحقق غير صحيح" }),
      };
    }

    // Normalize both sides before comparing (strip leading +)
    const sessionPhone = normalizePhone(otpSession.phoneNumber as string);
    const requestPhone = normalizePhone(phoneNumber);
    if (sessionPhone !== requestPhone) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: "رقم الهاتف لا يتطابق مع جلسة التحقق",
        }),
      };
    }

    // Check if user already exists with this phone and role
    const existingUser = await docClient.send(
      new QueryCommand({
        TableName: TABLE_NAME,
        IndexName: "GSI2",
        KeyConditionExpression: "GSI2PK = :phone",
        ExpressionAttributeValues: {
          ":phone": `PHONE#${requestPhone}`,
        },
      })
    );

    // Check if any user with this phone has the same role
    const userWithSameRole = existingUser.Items?.find(
      (item) => item.role === role
    );
    if (userWithSameRole) {
      return {
        statusCode: 409,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "المستخدم موجود بالفعل" }),
      };
    }

    // Create new user with hashed password
    const userId = `USER#${randomBytes(16).toString("hex")}`;
    const userRole = role || "USER";
    const hashedPassword = await bcrypt.hash(password, BCRYPT_ROUNDS);

    await docClient.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          PK: userId,
          SK: "PROFILE",
          GSI2PK: `PHONE#${requestPhone}`,
          GSI2SK: `ROLE#${userRole}#${userId}`,
          id: userId,
          phoneNumber: requestPhone,
          password: hashedPassword,
          displayName: displayName || "",
          role: userRole,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        },
      })
    );

    const token = await generateToken(userId);
    const refreshToken = generateRefreshToken();

    return {
      statusCode: 201,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        token,
        refreshToken,
        profile: {
          id: userId,
          phoneNumber: requestPhone,
          displayName: displayName || "",
          role: userRole,
        },
      }),
    };
  } catch (error) {
    console.error("Signup error:", error);
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: "خطأ في إنشاء الحساب" }),
    };
  }
}
