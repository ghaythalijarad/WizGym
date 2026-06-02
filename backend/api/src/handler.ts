import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { GetParameterCommand, SSMClient } from "@aws-sdk/client-ssm";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";
import { createHmac } from "crypto";
import { handleAdmin } from "./routes/admin";
import { handleAnalytics } from "./routes/analytics";
import { handleAuth } from "./routes/auth";
import { handleGyms } from "./routes/gyms";
import { handleNotifications } from "./routes/notifications";
import { handlePlans } from "./routes/plans";
import { handleTrainers } from "./routes/trainers";
import { handleUsers } from "./routes/users";

const ddbClient = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(ddbClient);

const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME || "wizgym-prod-core";

const CORS_HEADERS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "Content-Type,x-user-id,x-user-role,x-user-name,Authorization",
  "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
};

// ── JWT verification ──────────────────────────────────────────────────────────

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
    console.error("[Handler] Failed to load JWT_SECRET:", e);
    cachedJwtSecret = process.env.JWT_SECRET || "";
  }
  return cachedJwtSecret;
}

/**
 * Verify HMAC-SHA256 JWT from Authorization: Bearer <token>.
 * Returns the payload (with `sub` = userId) or null if invalid.
 */
async function verifyJwt(
  authHeader: string | undefined
): Promise<{ sub: string; iat: number; exp: number } | null> {
  if (!authHeader || !authHeader.startsWith("Bearer ")) return null;
  const token = authHeader.slice(7).trim();
  const parts = token.split(".");
  if (parts.length !== 3) return null;

  const [header, body, sig] = parts;
  const secret = await getJwtSecret();
  if (!secret) return null;

  const expected = createHmac("sha256", secret)
    .update(`${header}.${body}`)
    .digest("base64url");
  if (expected !== sig) return null;

  try {
    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
    if (payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

// Routes that do NOT require user JWT verification.
// Admin routes use their own token (ADMIN_JWT_SECRET) verified inside admin.ts.
const PUBLIC_PATH_PATTERNS = [
  /\/api\/v1\/health$/,
  /\/api\/v1\/auth\//,
  /\/api\/v1\/gyms\/public/,
  /\/api\/v1\/subscriptions\/plans/,
  /\/api\/v1\/admin\//,
];

function isPublicRoute(path: string): boolean {
  return PUBLIC_PATH_PATTERNS.some((p) => p.test(path));
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function notFound(path: string): APIGatewayProxyResultV2 {
  return {
    statusCode: 404,
    headers: CORS_HEADERS,
    body: JSON.stringify({ message: "Not Found", path }),
  };
}

// ── Main handler ──────────────────────────────────────────────────────────────

export async function handler(
  event: APIGatewayProxyEventV2
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || "";
  const method = event.requestContext.http.method;

  console.log(`[${method}] ${path}`);

  // CORS preflight
  if (method === "OPTIONS") {
    return { statusCode: 204, headers: CORS_HEADERS, body: "" };
  }

  try {
    // ── JWT enforcement for authenticated routes ──────────────────────────
    // Public routes skip token verification.
    // For all non-public routes: require a valid JWT. The verified
    // identity (sub claim) overrides x-user-id to prevent spoofing.
    // If no valid JWT is present, return 401.

    if (!isPublicRoute(path)) {
      const authHeader =
        event.headers?.["authorization"] || event.headers?.["Authorization"];
      const jwtPayload = await verifyJwt(authHeader);

      if (jwtPayload) {
        // Verified — inject the trusted userId into the headers
        event.headers["x-user-id"] = jwtPayload.sub;
      } else {
        // Strict mode: reject unauthenticated requests to protected routes
        return {
          statusCode: 401,
          headers: CORS_HEADERS,
          body: JSON.stringify({ message: "غير مصرح — يرجى تسجيل الدخول" }),
        };
      }
    }

    // Health
    if (path.endsWith("/api/v1/health")) {
      return {
        statusCode: 200,
        headers: CORS_HEADERS,
        body: JSON.stringify({
          status: "ok",
          runtime: "lambda-node",
          table: TABLE_NAME,
        }),
      };
    }

    // Auth
    if (path.includes("/api/v1/auth/")) {
      const res = (await handleAuth(event, docClient)) as {
        statusCode: number;
        body: string;
      };
      return { ...res, headers: CORS_HEADERS };
    }

    // Gyms + Subscriptions plans (public, owner)
    if (
      path.includes("/api/v1/gyms") ||
      path.includes("/api/v1/subscriptions")
    ) {
      const res = (await handleGyms(event, docClient)) as {
        statusCode: number;
        body: string;
      };
      return { ...res, headers: CORS_HEADERS };
    }

    // Trainers
    if (path.includes("/api/v1/trainers")) {
      const res = (await handleTrainers(event, docClient)) as {
        statusCode: number;
        body: string;
      };
      return { ...res, headers: CORS_HEADERS };
    }

    // Plans
    if (path.includes("/api/v1/plans")) {
      const res = (await handlePlans(event, docClient)) as {
        statusCode: number;
        body: string;
      };
      return { ...res, headers: CORS_HEADERS };
    }

    // Analytics
    if (path.includes("/api/v1/analytics")) {
      const res = (await handleAnalytics(event, docClient)) as {
        statusCode: number;
        body: string;
      };
      return { ...res, headers: CORS_HEADERS };
    }

    // Users
    if (path.includes("/api/v1/users")) {
      const res = (await handleUsers(event, docClient)) as {
        statusCode: number;
        body: string;
      };
      return { ...res, headers: CORS_HEADERS };
    }

    // Notifications
    if (path.includes("/api/v1/notifications")) {
      const res = (await handleNotifications(event, docClient)) as {
        statusCode: number;
        body: string;
      };
      return { ...res, headers: CORS_HEADERS };
    }

    // Admin
    if (path.includes("/api/v1/admin")) {
      const res = (await handleAdmin(event, docClient)) as {
        statusCode: number;
        body: string;
      };
      return { ...res, headers: CORS_HEADERS };
    }

    return notFound(path);
  } catch (error) {
    console.error("Unhandled error:", error);
    return {
      statusCode: 500,
      headers: CORS_HEADERS,
      body: JSON.stringify({ message: "خطأ في الخادم" }),
    };
  }
}
