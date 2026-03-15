import { GetParameterCommand, SSMClient } from "@aws-sdk/client-ssm";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  ScanCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";
import { createHmac, randomBytes } from "crypto";
import { otpiqService } from "../services/otpiq.service";

const ssmClient = new SSMClient({
  region: process.env.AWS_REGION || "us-east-1",
});
let cachedJwtSecret: string | null = null;

async function getJwtSecret(): Promise<string> {
  if (cachedJwtSecret) return cachedJwtSecret;
  try {
    const res = await ssmClient.send(
      new GetParameterCommand({
        Name: "/wizgym/prod/ADMIN_JWT_SECRET",
        WithDecryption: true,
      })
    );
    cachedJwtSecret = res.Parameter?.Value || "";
  } catch (e) {
    console.error("[Admin] Failed to load JWT secret:", e);
    cachedJwtSecret = "";
  }
  return cachedJwtSecret;
}

function signAdminToken(phone: string, secret: string): string {
  const payload = {
    sub: `ADMIN#${phone}`,
    phone,
    role: "superadmin",
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 12 * 60 * 60, // 12h
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

function normalizePhone(p: string) {
  return p.replace(/^\+/, "");
}

/** Verify an HS256 admin JWT. Returns the payload or throws. */
async function verifyAdminToken(authHeader: string | undefined): Promise<{
  sub: string;
  phone: string;
  role: string;
  exp: number;
}> {
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    throw new Error("MISSING_TOKEN");
  }
  const token = authHeader.slice(7).trim();
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("INVALID_TOKEN");
  const [header, body, sig] = parts;

  const secret = await getJwtSecret();
  if (!secret) throw new Error("SECRET_UNAVAILABLE");

  const expected = createHmac("sha256", secret)
    .update(`${header}.${body}`)
    .digest("base64url");
  if (expected !== sig) throw new Error("INVALID_SIGNATURE");

  const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
  if (payload.exp < Math.floor(Date.now() / 1000))
    throw new Error("TOKEN_EXPIRED");
  if (payload.role !== "superadmin") throw new Error("INSUFFICIENT_ROLE");

  return payload;
}

function unauthorizedResponse(message: string): APIGatewayProxyResultV2 {
  return {
    statusCode: 401,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message }),
  };
}

/** Convert local Iraqi 07XXXXXXXXX → international 9647XXXXXXXXX for OTPIQ */
function toInternational(phone: string): string {
  const p = normalizePhone(phone);
  // Iraqi local: 07XXXXXXXXX (11 digits total, starts with 07)
  if (/^07\d{9}$/.test(p)) return `964${p.slice(1)}`; // strip leading 0, add 964 → 9647XXXXXXXXX
  // Already international (e.g. 9647XXXXXXXXX)
  return p;
}

const TABLE = process.env.DYNAMODB_TABLE_NAME || "wizgym-prod-core";
const SUBSCRIPTION_PROOFS_BUCKET = process.env.SUBSCRIPTION_PROOFS_BUCKET || "";

function ok(body: unknown): APIGatewayProxyResultV2 {
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}
function notFound(): APIGatewayProxyResultV2 {
  return {
    statusCode: 404,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: "المسار غير موجود" }),
  };
}
function badRequest(message: string): APIGatewayProxyResultV2 {
  return {
    statusCode: 400,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message }),
  };
}

function gymFromItem(i: Record<string, unknown>) {
  return {
    id: String(i["gymId"] || i["PK"] || "").replace("GYM#", ""),
    gymName: i["name"] || "",
    name: i["name"] || "",
    city: i["city"] || "",
    audience: i["audience"] || "MIXED",
    status: i["status"] || "ACTIVE",
    membersCount: Number(i["membersCount"] || 0),
    trainersCount: Number(i["trainersCount"] || 0),
    averageRating: Number(i["averageRating"] || 0),
    ownerName: (() => {
      const v = String(i["ownerName"] || "");
      try {
        return decodeURIComponent(v);
      } catch {
        return v;
      }
    })(),
    amenities: (i["amenities"] as string[]) || [],
    description: i["description"] || null,
    coverImageUrl: i["coverImageUrl"] || null,
    requestedAt: i["createdAt"] || i["updatedAt"] || "",
    reviewNote: i["reviewNote"] || null,
  };
}

export async function handleAdmin(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || "";
  const method = event.requestContext.http.method;

  // ── POST /admin/auth/send-otp ──────────────────────────────────────────────
  if (path.endsWith("/admin/auth/send-otp") && method === "POST") {
    try {
      const body = JSON.parse(event.body || "{}");
      const phone = normalizePhone(String(body.phoneNumber || ""));
      if (!phone) {
        return {
          statusCode: 400,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ message: "رقم الهاتف مطلوب" }),
        };
      }

      // Verify phone is in the admin whitelist
      const adminItem = await docClient.send(
        new GetCommand({
          TableName: TABLE,
          Key: { PK: `ADMIN#${phone}`, SK: "PROFILE" },
        })
      );
      if (!adminItem.Item) {
        return {
          statusCode: 403,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ message: "رقم الهاتف غير مصرح له بالدخول" }),
        };
      }

      // Send OTP via OTPIQ — must use international format (9647XXXXXXXX)
      const otpRes = await otpiqService.sendOTP(toInternational(phone));
      if (!otpRes.success) {
        return {
          statusCode: 500,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            message: "فشل إرسال رمز التحقق",
            error: otpRes.error,
          }),
        };
      }

      const sessionId = otpRes.sessionId || randomBytes(16).toString("hex");
      const expiresAt = Date.now() + 5 * 60 * 1000; // 5 min

      await docClient.send(
        new PutCommand({
          TableName: TABLE,
          Item: {
            PK: `ADMINOTP#${sessionId}`,
            SK: "SESSION",
            phoneNumber: phone,
            code: otpRes.otpCode || "",
            expiresAt,
            verified: false,
            createdAt: new Date().toISOString(),
            ttl: Math.floor(expiresAt / 1000),
          },
        })
      );

      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          sessionId,
          message: "تم إرسال رمز التحقق عبر واتساب/SMS",
        }),
      };
    } catch (err) {
      console.error("[Admin OTP] send-otp error:", err);
      return {
        statusCode: 500,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "خطأ في إرسال الرمز" }),
      };
    }
  }

  // ── POST /admin/auth/verify-otp ────────────────────────────────────────────
  if (path.endsWith("/admin/auth/verify-otp") && method === "POST") {
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

      const sessionRes = await docClient.send(
        new GetCommand({
          TableName: TABLE,
          Key: { PK: `ADMINOTP#${sessionId}`, SK: "SESSION" },
        })
      );
      const session = sessionRes.Item;
      if (!session) {
        return {
          statusCode: 404,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ message: "جلسة غير صالحة" }),
        };
      }
      if (session["expiresAt"] < Date.now()) {
        return {
          statusCode: 400,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ message: "انتهت صلاحية الرمز" }),
        };
      }
      if (session["code"] !== String(otp)) {
        return {
          statusCode: 400,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ message: "الرمز غير صحيح" }),
        };
      }

      // Mark session verified
      await docClient.send(
        new PutCommand({
          TableName: TABLE,
          Item: {
            ...session,
            verified: true,
            verifiedAt: new Date().toISOString(),
          },
        })
      );

      // Issue signed admin JWT
      const secret = await getJwtSecret();
      const token = signAdminToken(String(session["phoneNumber"]), secret);

      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, message: "تم تسجيل الدخول بنجاح" }),
      };
    } catch (err) {
      console.error("[Admin OTP] verify-otp error:", err);
      return {
        statusCode: 500,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "خطأ في التحقق" }),
      };
    }
  }

  // ── JWT guard — every route below this point requires a valid admin token ──
  try {
    await verifyAdminToken(
      event.headers?.["authorization"] || event.headers?.["Authorization"]
    );
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "UNAUTHORIZED";
    if (msg === "TOKEN_EXPIRED") {
      return unauthorizedResponse(
        "انتهت صلاحية الجلسة، يرجى تسجيل الدخول مجدداً"
      );
    }
    return unauthorizedResponse("غير مصرح — يرجى تسجيل الدخول");
  }

  // GET /admin/dashboard
  if (path.endsWith("/admin/dashboard") && method === "GET") {
    const [g, u, pending, activeSubs] = await Promise.all([
      docClient.send(
        new ScanCommand({
          TableName: TABLE,
          FilterExpression: "begins_with(PK, :g) AND SK = :p",
          ExpressionAttributeValues: { ":g": "GYM#", ":p": "PROFILE" },
          Select: "COUNT",
        })
      ),
      docClient.send(
        new ScanCommand({
          TableName: TABLE,
          FilterExpression: "begins_with(PK, :u) AND SK = :p",
          ExpressionAttributeValues: { ":u": "USER#", ":p": "PROFILE" },
          Select: "COUNT",
        })
      ),
      docClient.send(
        new ScanCommand({
          TableName: TABLE,
          FilterExpression: "begins_with(PK, :g) AND SK = :p AND #s = :pending",
          ExpressionAttributeNames: { "#s": "status" },
          ExpressionAttributeValues: {
            ":g": "GYM#",
            ":p": "PROFILE",
            ":pending": "PENDING_APPROVAL",
          },
          Select: "COUNT",
        })
      ),
      docClient.send(
        new ScanCommand({
          TableName: TABLE,
          FilterExpression: "begins_with(PK, :g) AND SK = :s AND #s = :active",
          ExpressionAttributeNames: { "#s": "status" },
          ExpressionAttributeValues: {
            ":g": "GYM#",
            ":s": "SUBSCRIPTION",
            ":active": "ACTIVE",
          },
          Select: "COUNT",
        })
      ),
    ]);
    return ok({
      totalGyms: g.Count || 0,
      totalUsers: u.Count || 0,
      pendingApprovals: pending.Count || 0,
      activeSubscriptions: activeSubs.Count || 0,
    });
  }

  // GET /admin/gyms
  if (path.endsWith("/admin/gyms") && method === "GET") {
    const res = await docClient.send(
      new ScanCommand({
        TableName: TABLE,
        FilterExpression: "begins_with(PK, :g) AND SK = :p",
        ExpressionAttributeValues: { ":g": "GYM#", ":p": "PROFILE" },
      })
    );
    return ok(
      ((res.Items || []) as Record<string, unknown>[]).map(gymFromItem)
    );
  }

  // POST /admin/gyms/:id/approve
  const approve = path.match(/\/admin\/gyms\/([^/]+)\/approve$/);
  if (approve && method === "POST") {
    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${approve[1]}`, SK: "PROFILE" },
        UpdateExpression: "SET #s = :s, updatedAt = :u",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: {
          ":s": "ACTIVE",
          ":u": new Date().toISOString(),
        },
      })
    );
    return ok({ message: "تم اعتماد النادي بنجاح" });
  }

  // POST /admin/gyms/:id/reject
  const reject = path.match(/\/admin\/gyms\/([^/]+)\/reject$/);
  if (reject && method === "POST") {
    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${reject[1]}`, SK: "PROFILE" },
        UpdateExpression: "SET #s = :s, updatedAt = :u",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: {
          ":s": "REJECTED",
          ":u": new Date().toISOString(),
        },
      })
    );
    return ok({ message: "تم رفض النادي" });
  }

  // ── GET /admin/subscriptions — studio platform subscriptions ─────────────
  if (path.endsWith("/admin/subscriptions") && method === "GET") {
    // Fetch all gym profiles
    const gymsRes = await docClient.send(
      new ScanCommand({
        TableName: TABLE,
        FilterExpression: "begins_with(PK, :g) AND SK = :p",
        ExpressionAttributeValues: { ":g": "GYM#", ":p": "PROFILE" },
      })
    );
    const gyms = (gymsRes.Items || []) as Record<string, unknown>[];

    // Fetch all SUBSCRIPTION SK items for gyms
    const subsRes = await docClient.send(
      new ScanCommand({
        TableName: TABLE,
        FilterExpression: "begins_with(PK, :g) AND SK = :s",
        ExpressionAttributeValues: { ":g": "GYM#", ":s": "SUBSCRIPTION" },
      })
    );
    const subMap: Record<string, Record<string, unknown>> = {};
    for (const s of (subsRes.Items || []) as Record<string, unknown>[]) {
      const gymId = String(s["PK"] || "").replace("GYM#", "");
      subMap[gymId] = s;
    }

    const now = Date.now();
    return ok(
      gyms.map((g) => {
        const gymId = String(g["PK"] || "").replace("GYM#", "");
        const sub = subMap[gymId];
        const expiresAt = sub ? String(sub["expiresAt"] || "") : "";
        const startsAt = sub ? String(sub["startsAt"] || "") : "";
        const isActive = sub
          ? sub["status"] === "ACTIVE" &&
            expiresAt &&
            new Date(expiresAt).getTime() > now
          : false;
        return {
          gymId,
          gymName: String(g["name"] || gymId),
          city: String(g["city"] || ""),
          ownerName: String(g["ownerName"] || ""),
          status: isActive ? "ACTIVE" : "INACTIVE",
          startsAt,
          expiresAt,
          durationMonths: sub ? Number(sub["durationMonths"] || 0) : 0,
          activatedBy: sub ? String(sub["activatedBy"] || "") : "",
          activatedAt: sub ? String(sub["activatedAt"] || "") : "",
        };
      })
    );
  }

  // ── POST /admin/subscriptions/:gymId/activate ─────────────────────────────
  const activateSub = path.match(/\/admin\/subscriptions\/([^/]+)\/activate$/);
  if (activateSub && method === "POST") {
    const gymId = activateSub[1];
    const body = JSON.parse(event.body || "{}");
    const durationMonths = Math.max(
      1,
      Math.min(12, Number(body.durationMonths) || 1)
    );

    // Verify gym exists
    const gymRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
      })
    );
    if (!gymRes.Item) {
      return {
        statusCode: 404,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: "النادي غير موجود" }),
      };
    }

    const now = new Date();
    // If there's an existing active subscription, extend from its expiry
    const existingSub = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "SUBSCRIPTION" },
      })
    );
    let startsAt = now.toISOString();
    if (existingSub.Item && existingSub.Item["status"] === "ACTIVE") {
      const existingExpiry = existingSub.Item["expiresAt"] as string;
      if (existingExpiry && new Date(existingExpiry) > now) {
        startsAt = existingExpiry; // extend from current expiry
      }
    }
    const expiryDate = new Date(startsAt);
    expiryDate.setMonth(expiryDate.getMonth() + durationMonths);
    const expiresAt = expiryDate.toISOString();

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: "SUBSCRIPTION",
          gymId,
          status: "ACTIVE",
          durationMonths,
          startsAt,
          expiresAt,
          activatedAt: now.toISOString(),
          activatedBy: "admin",
          updatedAt: now.toISOString(),
        },
      })
    );

    return ok({
      message: `تم تفعيل الاشتراك لمدة ${durationMonths} شهر`,
      gymId,
      expiresAt,
    });
  }

  // ── POST /admin/subscriptions/:gymId/deactivate ───────────────────────────
  const deactivateSub = path.match(
    /\/admin\/subscriptions\/([^/]+)\/deactivate$/
  );
  if (deactivateSub && method === "POST") {
    const gymId = deactivateSub[1];
    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "SUBSCRIPTION" },
        UpdateExpression: "SET #s = :s, updatedAt = :u",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: {
          ":s": "INACTIVE",
          ":u": new Date().toISOString(),
        },
      })
    );
    return ok({ message: "تم إلغاء اشتراك النادي" });
  }

  // ── Platform Subscription Plans (admin-managed) ─────────────────────────
  // GET /admin/subscription-plans
  if (path.endsWith("/admin/subscription-plans") && method === "GET") {
    const res = await docClient.send(
      new ScanCommand({
        TableName: TABLE,
        FilterExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: {
          ":pk": "PLATFORM",
          ":sk": "SUBSCRIPTION_PLAN#",
        },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    const plans = items
      .map((p) => ({
        planId: String(p["planId"] || ""),
        durationMonths: Number(p["durationMonths"] || 1),
        price: Number(p["price"] || 0),
        currency: String(p["currency"] || "IQD"),
        isActive: p["isActive"] !== false,
        createdAt: p["createdAt"] || null,
        updatedAt: p["updatedAt"] || null,
      }))
      .filter((p) => p.planId)
      .sort((a, b) => a.durationMonths - b.durationMonths);
    return ok({ plans });
  }

  // POST /admin/subscription-plans
  if (path.endsWith("/admin/subscription-plans") && method === "POST") {
    const body = JSON.parse(event.body || "{}");
    const durationMonths = Number(body.durationMonths || 0);
    const price = Number(body.price || 0);
    const currency = String(body.currency || "IQD").toUpperCase();
    if (!durationMonths || durationMonths < 1)
      return badRequest("durationMonths مطلوب");
    if (!price || price < 0) return badRequest("price مطلوب");

    const planId = randomBytes(6).toString("hex");
    const now = new Date().toISOString();

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: "PLATFORM",
          SK: `SUBSCRIPTION_PLAN#${planId}`,
          planId,
          durationMonths,
          price,
          currency,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        },
      })
    );

    return ok({ planId, message: "تم إنشاء خطة اشتراك المنصة" });
  }

  // PATCH /admin/subscription-plans/:planId
  const adminPlanPatch = path.match(/\/admin\/subscription-plans\/([^/]+)$/);
  if (adminPlanPatch && method === "PATCH") {
    const planId = adminPlanPatch[1];
    const body = JSON.parse(event.body || "{}");
    const now = new Date().toISOString();

    const updateParts: string[] = ["updatedAt = :now"];
    const exprValues: Record<string, unknown> = { ":now": now };

    if (body.durationMonths !== undefined) {
      updateParts.push("durationMonths = :d");
      exprValues[":d"] = Number(body.durationMonths);
    }
    if (body.price !== undefined) {
      updateParts.push("price = :p");
      exprValues[":p"] = Number(body.price);
    }
    if (body.currency !== undefined) {
      updateParts.push("currency = :c");
      exprValues[":c"] = String(body.currency || "IQD").toUpperCase();
    }
    if (body.isActive !== undefined) {
      updateParts.push("isActive = :a");
      exprValues[":a"] = body.isActive === true;
    }

    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: "PLATFORM", SK: `SUBSCRIPTION_PLAN#${planId}` },
        UpdateExpression: `SET ${updateParts.join(", ")}`,
        ExpressionAttributeValues: exprValues,
      })
    );

    return ok({ message: "تم تحديث خطة الاشتراك" });
  }

  // ── Gym Subscription Requests (admin review) ─────────────────────────────
  // GET /admin/subscription-requests?status=PENDING
  if (path.endsWith("/admin/subscription-requests") && method === "GET") {
    const statusFilter = (
      event.queryStringParameters?.status || "PENDING"
    ).toUpperCase();

    const res = await docClient.send(
      new ScanCommand({
        TableName: TABLE,
        FilterExpression: "GSI1PK = :pk",
        ExpressionAttributeValues: { ":pk": "SUBSCRIPTION_REQUESTS" },
      })
    );

    const items = (res.Items || []) as Record<string, unknown>[];
    const requests = items
      .map((r) => ({
        requestId: String(r["requestId"] || ""),
        gymId: String(r["gymId"] || ""),
        ownerId: String(r["ownerId"] || ""),
        ownerName: r["ownerName"] || "",
        status: String(r["status"] || "PENDING").toUpperCase(),
        planId: String(r["planId"] || ""),
        durationMonths: Number(r["durationMonths"] || 1),
        price: Number(r["price"] || 0),
        currency: String(r["currency"] || "IQD"),
        paymentMethod: String(r["paymentMethod"] || "ZAIN_CASH"),
        transferToPhone: String(r["transferToPhone"] || "07831367435"),
        screenshotUrl: String(r["screenshotUrl"] || ""),
        createdAt: String(r["createdAt"] || ""),
        reviewedAt: r["reviewedAt"] || null,
        reviewedBy: r["reviewedBy"] || null,
        note: r["note"] || null,
      }))
      .filter((r) => r.requestId && r.gymId)
      .filter((r) => !statusFilter || r.status === statusFilter)
      .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));

    return ok({ requests });
  }

  // GET /admin/subscription-requests/:gymId/:requestId/view-url
  const adminReqView = path.match(
    /\/admin\/subscription-requests\/([^/]+)\/([^/]+)\/view-url$/
  );
  if (adminReqView && method === "GET") {
    const gymId = adminReqView[1];
    const requestId = adminReqView[2];
    if (!SUBSCRIPTION_PROOFS_BUCKET)
      return badRequest("SUBSCRIPTION_PROOFS_BUCKET غير مضبوط");

    const reqRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `SUBSCRIPTION_REQUEST#${requestId}` },
        ProjectionExpression: "screenshotUrl, screenshotObjectKey",
      })
    );
    if (!reqRes.Item) return notFound();

    const item = reqRes.Item as Record<string, unknown>;
    const screenshotUrl = String(item["screenshotUrl"] || "");
    const screenshotObjectKey = String(item["screenshotObjectKey"] || "");
    const key = screenshotObjectKey || "";

    if (!key) {
      // If key isn't stored, fall back to URL
      return ok({ url: screenshotUrl, presigned: false, expiresIn: null });
    }

    const { GetObjectCommand, S3Client } = await import("@aws-sdk/client-s3");
    const { getSignedUrl } = await import("@aws-sdk/s3-request-presigner");
    const s3 = new S3Client({});

    const url = await getSignedUrl(
      s3,
      new GetObjectCommand({ Bucket: SUBSCRIPTION_PROOFS_BUCKET, Key: key }),
      { expiresIn: 60 * 10 }
    );

    return ok({ url, presigned: true, expiresIn: 60 * 10 });
  }

  // POST /admin/subscription-requests/:gymId/:requestId/approve
  const adminReqApprove = path.match(
    /\/admin\/subscription-requests\/([^/]+)\/([^/]+)\/approve$/
  );
  if (adminReqApprove && method === "POST") {
    const gymId = adminReqApprove[1];
    const requestId = adminReqApprove[2];

    // Load request
    const reqRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `SUBSCRIPTION_REQUEST#${requestId}` },
      })
    );
    if (!reqRes.Item) return notFound();

    const reqItem = reqRes.Item as Record<string, unknown>;
    const status = String(reqItem["status"] || "PENDING").toUpperCase();
    if (status !== "PENDING") {
      return badRequest("لا يمكن اعتماد هذا الطلب لأنه ليس PENDING");
    }

    const durationMonths = Number(reqItem["durationMonths"] || 1);

    // Activate subscription (reuse the same shape used by existing admin/subscriptions activate)
    const now = new Date();
    const nowIso = now.toISOString();
    const expires = new Date(now);
    expires.setMonth(expires.getMonth() + durationMonths);

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: "SUBSCRIPTION",
          gymId,
          status: "ACTIVE",
          startsAt: nowIso,
          expiresAt: expires.toISOString(),
          updatedAt: nowIso,
        },
      })
    );

    // Mark request approved
    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `SUBSCRIPTION_REQUEST#${requestId}` },
        UpdateExpression: "SET #st = :s, reviewedAt = :ra, reviewedBy = :rb",
        ExpressionAttributeNames: { "#st": "status" },
        ExpressionAttributeValues: {
          ":s": "APPROVED",
          ":ra": nowIso,
          ":rb": "ADMIN",
        },
      })
    );

    return ok({ message: "تم اعتماد الطلب وتفعيل الاشتراك" });
  }

  // POST /admin/subscription-requests/:gymId/:requestId/reject
  const adminReqReject = path.match(
    /\/admin\/subscription-requests\/([^/]+)\/([^/]+)\/reject$/
  );
  if (adminReqReject && method === "POST") {
    const gymId = adminReqReject[1];
    const requestId = adminReqReject[2];
    const body = JSON.parse(event.body || "{}");
    const note = body.note ? String(body.note) : null;
    const nowIso = new Date().toISOString();

    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `SUBSCRIPTION_REQUEST#${requestId}` },
        UpdateExpression:
          "SET #st = :s, reviewedAt = :ra, reviewedBy = :rb, note = :n",
        ExpressionAttributeNames: { "#st": "status" },
        ExpressionAttributeValues: {
          ":s": "REJECTED",
          ":ra": nowIso,
          ":rb": "ADMIN",
          ":n": note,
        },
      })
    );

    return ok({ message: "تم رفض الطلب" });
  }

  return notFound();
}
