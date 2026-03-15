import {
  DeleteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  ScanCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";
import { randomBytes } from "crypto";
import { pushNotification } from "./notifications";

// NOTE: Keep aligned with gyms.ts S3 presign pattern.
import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const TABLE = process.env.DYNAMODB_TABLE_NAME || "wizgym-prod-core";
const TRAINER_CERTS_BUCKET = process.env.TRAINER_CERTS_BUCKET || "";
// Avatar images are stored in the same bucket under avatars/ prefix
const AVATARS_BUCKET = process.env.TRAINER_CERTS_BUCKET || "";
const s3 = new S3Client({});

function ok(body: unknown): APIGatewayProxyResultV2 {
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}
function created(body: unknown): APIGatewayProxyResultV2 {
  return {
    statusCode: 201,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}
function err(status: number, msg: string): APIGatewayProxyResultV2 {
  return {
    statusCode: status,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: msg }),
  };
}
function userId(event: APIGatewayProxyEventV2): string {
  return event.headers?.["x-user-id"] || event.headers?.["X-User-Id"] || "anon";
}
function userName(event: APIGatewayProxyEventV2): string {
  const raw =
    event.headers?.["x-user-name"] || event.headers?.["X-User-Name"] || "";
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

function guessExtFromContentType(contentType: string): string {
  const ct = contentType.toLowerCase();
  if (ct.includes("jpeg")) return "jpg";
  if (ct.includes("png")) return "png";
  if (ct.includes("webp")) return "webp";
  if (ct.includes("heic")) return "heic";
  return "jpg";
}

function parseS3ObjectKeyFromUrlForBucket(
  url: string,
  bucket: string
): string | null {
  try {
    const u = new URL(url);
    if (bucket && u.hostname.startsWith(`${bucket}.s3`)) {
      return decodeURIComponent(u.pathname.replace(/^\//, ""));
    }
    return null;
  } catch {
    return null;
  }
}

async function presignAvatarViewUrl(objectKey: string): Promise<string | null> {
  if (!AVATARS_BUCKET || !objectKey) return null;
  try {
    return await getSignedUrl(
      s3,
      new GetObjectCommand({ Bucket: AVATARS_BUCKET, Key: objectKey }),
      { expiresIn: 60 * 10 }
    );
  } catch {
    return null;
  }
}

async function isTrainerSubscriber(
  docClient: DynamoDBDocumentClient,
  trainerId: string,
  userIdValue: string
): Promise<boolean> {
  if (!trainerId || !userIdValue || userIdValue === "anon") return false;

  try {
    const res = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `USER#${userIdValue}`, SK: `SUBSCRIPTION#${trainerId}` },
        ProjectionExpression: "#st, expiresAt",
        ExpressionAttributeNames: { "#st": "status" },
      })
    );

    const item = res.Item as Record<string, unknown> | undefined;
    if (!item) return false;

    const status = String(item["status"] || "").toUpperCase();
    if (status !== "APPROVED" && status !== "ACTIVE") return false;

    const expiresAt = String(item["expiresAt"] || "");
    if (!expiresAt) return true;

    const expMs = new Date(expiresAt).getTime();
    if (Number.isNaN(expMs)) return true;

    return expMs > Date.now();
  } catch {
    return false;
  }
}

export async function handleTrainers(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || "";
  const method = event.requestContext.http.method;

  // GET /trainers/me/gyms
  if (path.endsWith("/trainers/me/gyms") && method === "GET") {
    const uid = userId(event);
    const res = await docClient.send(
      new ScanCommand({
        TableName: TABLE,
        FilterExpression: "begins_with(SK, :sk) AND trainerId = :tid",
        ExpressionAttributeValues: { ":sk": "TRAINER#", ":tid": uid },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];

    // Enrich each trainer record with gym name/city from the gym profile
    const enriched = await Promise.all(
      items.map(async (i) => {
        const gId = String(i["gymId"] || "");
        let gymName = String(i["gymName"] || "");
        let city = String(i["city"] || "");
        let averageRating = Number(i["averageRating"] || 0);

        // Fetch gym profile if gymName or city is missing
        if (gId && (!gymName || !city)) {
          try {
            const gymRes = await docClient.send(
              new GetCommand({
                TableName: TABLE,
                Key: { PK: `GYM#${gId}`, SK: "PROFILE" },
                ProjectionExpression: "#n, city, averageRating",
                ExpressionAttributeNames: { "#n": "name" },
              })
            );
            const gym = gymRes.Item as Record<string, unknown> | undefined;
            if (gym) {
              gymName = gymName || String(gym["name"] || "");
              city = city || String(gym["city"] || "");
              averageRating =
                averageRating || Number(gym["averageRating"] || 0);
            }
          } catch {
            /* fallback to stored values */
          }
        }

        return {
          gymId: gId,
          gymName,
          city,
          activeClients: Number(i["activeClients"] || 0),
          averageRating,
        };
      })
    );

    return ok(enriched);
  }

  // GET /trainers/me/clients — only APPROVED subscriptions
  if (path.endsWith("/trainers/me/clients") && method === "GET") {
    const uid = userId(event);
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        IndexName: "GSI1",
        KeyConditionExpression:
          "GSI1PK = :pk AND begins_with(GSI1SK, :skPrefix)",
        FilterExpression: "#st = :approved",
        ExpressionAttributeNames: { "#st": "status" },
        ExpressionAttributeValues: {
          ":pk": `TRAINER_CLIENTS#${uid}`,
          ":approved": "APPROVED",
          ":skPrefix": "CLIENT#",
        },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({
      clients: items.map((i) => ({
        id: i["clientId"],
        name: i["displayName"] || "",
        gymId: i["gymId"] || "",
      })),
    });
  }

  // GET /trainers/me/subscription-requests — pending + approved + rejected
  if (path.endsWith("/trainers/me/subscription-requests") && method === "GET") {
    const uid = userId(event);
    const statusFilter = (event.queryStringParameters || {})["status"]; // optional: PENDING|APPROVED|REJECTED
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        IndexName: "GSI1",
        KeyConditionExpression:
          "GSI1PK = :pk AND begins_with(GSI1SK, :skPrefix)",
        ...(statusFilter
          ? {
              FilterExpression: "#st = :sf",
              ExpressionAttributeNames: { "#st": "status" },
              ExpressionAttributeValues: {
                ":pk": `TRAINER_CLIENTS#${uid}`,
                ":sf": statusFilter.toUpperCase(),
                ":skPrefix": "REQUEST#",
              },
            }
          : {
              ExpressionAttributeValues: {
                ":pk": `TRAINER_CLIENTS#${uid}`,
                ":skPrefix": "REQUEST#",
              },
            }),
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({
      requests: items.map((i) => ({
        requestId: i["requestId"] || i["SK"],
        clientId: i["clientId"] || "",
        clientName: i["displayName"] || "",
        gymId: i["gymId"] || "",
        status: i["status"] || "PENDING",
        requestedAt: i["requestedAt"] || i["createdAt"] || "",
        respondedAt: i["respondedAt"] || null,
        planId: i["planId"] || null,
        planName: i["planName"] || null,
        planPrice: i["planPrice"] ?? null,
        durationMonths: i["durationMonths"] ?? null,
        expiresAt: i["expiresAt"] || null,
      })),
    });
  }

  // PATCH /trainers/me/subscription-requests/:requestId — approve or reject
  const respondMatch = path.match(
    /\/trainers\/me\/subscription-requests\/([^/]+)$/
  );
  if (respondMatch && method === "PATCH") {
    const requestId = respondMatch[1];
    const uid = userId(event);
    const body = JSON.parse(event.body || "{}");
    const action = (body.action || "").toUpperCase(); // APPROVE | REJECT

    if (action !== "APPROVE" && action !== "REJECT") {
      return err(400, "action يجب أن يكون APPROVE أو REJECT");
    }

    // Fetch the request item first
    const reqRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `TRAINER#${uid}`, SK: `SUBSCRIPTION_REQUEST#${requestId}` },
      })
    );
    if (!reqRes.Item) {
      return err(404, "الطلب غير موجود");
    }

    const reqItem = reqRes.Item as Record<string, unknown>;
    const newStatus = action === "APPROVE" ? "APPROVED" : "REJECTED";

    // Compute expiresAt when approving (use plan durationMonths if present, default 1 month)
    const approvedAt = new Date();
    let expiresAt: string | undefined;
    if (action === "APPROVE") {
      const months = Number(reqItem["durationMonths"]) || 1;
      const exp = new Date(approvedAt);
      exp.setMonth(exp.getMonth() + months);
      expiresAt = exp.toISOString();
    }

    // Update the request status
    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `TRAINER#${uid}`, SK: `SUBSCRIPTION_REQUEST#${requestId}` },
        UpdateExpression: expiresAt
          ? "SET #st = :s, respondedAt = :r, expiresAt = :exp"
          : "SET #st = :s, respondedAt = :r",
        ExpressionAttributeNames: { "#st": "status" },
        ExpressionAttributeValues: {
          ":s": newStatus,
          ":r": approvedAt.toISOString(),
          ...(expiresAt ? { ":exp": expiresAt } : {}),
        },
      })
    );

    // Update the GSI1 projection item (for client-list queries)
    const clientId = reqItem["clientId"] as string;
    if (clientId) {
      await docClient.send(
        new UpdateCommand({
          TableName: TABLE,
          Key: { PK: `TRAINER#${uid}`, SK: `CLIENT#${clientId}` },
          UpdateExpression: expiresAt
            ? "SET #st = :s, respondedAt = :r, GSI1PK = :gpk, GSI1SK = :gsk, expiresAt = :exp"
            : "SET #st = :s, respondedAt = :r, GSI1PK = :gpk, GSI1SK = :gsk",
          ExpressionAttributeNames: { "#st": "status" },
          ExpressionAttributeValues: {
            ":s": newStatus,
            ":r": approvedAt.toISOString(),
            ":gpk": `TRAINER_CLIENTS#${uid}`,
            ":gsk": `CLIENT#${clientId}`,
            ...(expiresAt ? { ":exp": expiresAt } : {}),
          },
        })
      );
    }

    // Update the trainee's own subscription record
    if (clientId) {
      await docClient.send(
        new UpdateCommand({
          TableName: TABLE,
          Key: { PK: `USER#${clientId}`, SK: `SUBSCRIPTION#${uid}` },
          UpdateExpression: expiresAt
            ? "SET #st = :s, respondedAt = :r, expiresAt = :exp"
            : "SET #st = :s, respondedAt = :r",
          ExpressionAttributeNames: { "#st": "status" },
          ExpressionAttributeValues: {
            ":s": newStatus,
            ":r": approvedAt.toISOString(),
            ...(expiresAt ? { ":exp": expiresAt } : {}),
          },
        })
      );
    }

    const msgMap: Record<string, string> = {
      APPROVED: "تم قبول طلب الاشتراك",
      REJECTED: "تم رفض طلب الاشتراك",
    };

    // Notify the trainee about trainer's decision
    if (clientId) {
      await pushNotification(docClient, {
        targetUserId: clientId,
        eventType:
          action === "APPROVE"
            ? "SUBSCRIPTION_APPROVED"
            : "SUBSCRIPTION_REJECTED",
        title:
          action === "APPROVE" ? "تم قبول اشتراكك! 🎉" : "تم رفض طلب الاشتراك",
        message:
          action === "APPROVE"
            ? "قبل المدرب طلب اشتراكك — يمكنك البدء بالتمرين!"
            : "رفض المدرب طلب اشتراكك. يمكنك البحث عن مدرب آخر.",
        payload: { trainerId: uid, requestId, action },
      }).catch(() => {
        /* silent */
      });
    }

    return ok({ message: msgMap[newStatus] });
  }

  // ── GET /trainers/me/subscription-plans — list trainer's own plans ──────────
  if (path.endsWith("/trainers/me/subscription-plans") && method === "GET") {
    const uid = userId(event);
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: {
          ":pk": `TRAINER#${uid}`,
          ":sk": "SUBSCRIPTION_PLAN#",
        },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];

    return ok({
      plans: items.map((p) => ({
        planId: String(p["planId"] || ""),
        // Unified naming with gyms plans
        title: p["title"] || p["name"] || "",
        durationMonths: Number(p["durationMonths"] || 1),
        price: Number(p["price"] || 0),
        currency: String(p["currency"] || "IQD"),
        description: p["description"] || null,
        isActive: p["isActive"] !== false,
        createdAt: p["createdAt"] || null,
        updatedAt: p["updatedAt"] || null,

        // Back-compat for older clients
        name: p["title"] || p["name"] || "",
      })),
    });
  }

  // ── POST /trainers/me/subscription-plans — create a plan (unified with gym plan schema) ──
  if (path.endsWith("/trainers/me/subscription-plans") && method === "POST") {
    const uid = userId(event);
    const body = JSON.parse(event.body || "{}");

    // Accept both "title" (new unified) and "name" (old) payloads
    const title = String(body.title ?? body.name ?? "").trim();
    const durationMonths = Number(body.durationMonths) || 1;
    const price = Number(body.price);
    const currency = String(body.currency || "IQD").trim() || "IQD";
    const description =
      body.description === undefined || body.description === null
        ? null
        : String(body.description);
    const isActive = body.isActive !== false;

    if (!title) return err(400, "title مطلوب");
    if (isNaN(price) || price < 0)
      return err(400, "price يجب أن يكون رقماً موجباً");

    const planId = randomBytes(8).toString("hex");
    const now = new Date().toISOString();
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `TRAINER#${uid}`,
          SK: `SUBSCRIPTION_PLAN#${planId}`,
          planId,
          trainerId: uid,
          // Unified fields (same as gym plans)
          title,
          durationMonths,
          price,
          currency,
          description,
          isActive,
          createdAt: now,
          updatedAt: now,
          // Back-compat: keep "name" in sync for old data readers
          name: title,
        },
      })
    );
    return created({ planId, message: "تم إنشاء خطة الاشتراك" });
  }

  // ── DELETE /trainers/me/subscription-plans/:planId ──────────────────────────
  const deletePlanMatch = path.match(
    /\/trainers\/me\/subscription-plans\/([^/]+)$/
  );
  if (deletePlanMatch && method === "DELETE") {
    const uid = userId(event);
    const planId = deletePlanMatch[1];
    await docClient.send(
      new DeleteCommand({
        TableName: TABLE,
        Key: { PK: `TRAINER#${uid}`, SK: `SUBSCRIPTION_PLAN#${planId}` },
      })
    );
    return ok({ message: "تم حذف الخطة" });
  }

  // ── GET /trainers/:trainerId/subscription-plans — public, trainee reads (unified) ──
  const publicPlansMatch = path.match(
    /\/trainers\/([^/]+)\/subscription-plans$/
  );
  if (publicPlansMatch && method === "GET") {
    const trainerId = decodeURIComponent(publicPlansMatch[1]);
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: {
          ":pk": `TRAINER#${trainerId}`,
          ":sk": "SUBSCRIPTION_PLAN#",
        },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({
      plans: items
        .map((p) => ({
          planId: String(p["planId"] || ""),
          title: p["title"] || p["name"] || "",
          durationMonths: Number(p["durationMonths"] || 1),
          price: Number(p["price"] || 0),
          currency: String(p["currency"] || "IQD"),
          description: p["description"] || null,
          isActive: p["isActive"] !== false,
          // Back-compat
          name: p["title"] || p["name"] || "",
        }))
        .filter((p) => p.planId && p.isActive),
    });
  }

  // POST /trainers/:trainerId/subscribe — trainee sends subscription request
  const subscribeMatch = path.match(/\/trainers\/([^/]+)\/subscribe$/);
  if (subscribeMatch && method === "POST") {
    const trainerId = decodeURIComponent(subscribeMatch[1]);
    const uid = userId(event);
    const uName = userName(event);
    const body = JSON.parse(event.body || "{}");
    const gymId = body.gymId || "";
    const planId = String(body.planId || "").trim();

    if (trainerId === uid) {
      return err(400, "لا يمكنك الاشتراك مع نفسك");
    }

    // Check for duplicate pending request
    const existing = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `TRAINER#${trainerId}`, SK: `CLIENT#${uid}` },
      })
    );
    if (
      existing.Item &&
      (existing.Item as Record<string, unknown>)["status"] === "PENDING"
    ) {
      return err(409, "لديك طلب اشتراك معلق بالفعل لدى هذا المدرب");
    }
    if (
      existing.Item &&
      (existing.Item as Record<string, unknown>)["status"] === "APPROVED"
    ) {
      return err(409, "أنت مشترك بالفعل لدى هذا المدرب");
    }

    // Fetch plan details if planId provided
    let planName = "";
    let planPrice: number | undefined;
    let durationMonths = 1;
    if (planId) {
      try {
        const planRes = await docClient.send(
          new GetCommand({
            TableName: TABLE,
            Key: {
              PK: `TRAINER#${trainerId}`,
              SK: `SUBSCRIPTION_PLAN#${planId}`,
            },
          })
        );
        if (planRes.Item) {
          const p = planRes.Item as Record<string, unknown>;
          planName = String(p["title"] || p["name"] || "");
          planPrice = Number(p["price"]);
          durationMonths = Number(p["durationMonths"]) || 1;
        }
      } catch {
        /* ignore */
      }
    }

    const requestId = randomBytes(8).toString("hex");
    const now = new Date().toISOString();

    const planFields = planId
      ? { planId, planName, planPrice, durationMonths }
      : {};

    // Main subscription request item (queried by trainer)
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `TRAINER#${trainerId}`,
          SK: `SUBSCRIPTION_REQUEST#${requestId}`,
          requestId,
          trainerId,
          clientId: uid,
          displayName: uName,
          gymId,
          status: "PENDING",
          requestedAt: now,
          ...planFields,
          // GSI1 for listing by trainer
          GSI1PK: `TRAINER_CLIENTS#${trainerId}`,
          GSI1SK: `REQUEST#${requestId}`,
        },
      })
    );

    // CLIENT# projection for duplicate-check & status tracking
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `TRAINER#${trainerId}`,
          SK: `CLIENT#${uid}`,
          requestId,
          trainerId,
          clientId: uid,
          displayName: uName,
          gymId,
          status: "PENDING",
          requestedAt: now,
          ...planFields,
          GSI1PK: `TRAINER_CLIENTS#${trainerId}`,
          GSI1SK: `CLIENT#${uid}`,
        },
      })
    );

    // Trainee's own record: which trainers they've subscribed to
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `USER#${uid}`,
          SK: `SUBSCRIPTION#${trainerId}`,
          trainerId,
          clientId: uid,
          requestId,
          status: "PENDING",
          requestedAt: now,
          ...planFields,
        },
      })
    );

    // Notify the trainer about new subscription request
    await pushNotification(docClient, {
      targetUserId: trainerId,
      eventType: "NEW_SUBSCRIPTION_REQUEST",
      title: "طلب اشتراك جديد",
      message: `${uName || "متدرب"} يريد الاشتراك معك`,
      payload: { requestId, clientId: uid, gymId },
    }).catch(() => {
      /* silent */
    });

    return created({ requestId, message: "تم إرسال طلب الاشتراك بنجاح" });
  }

  // DELETE /trainers/:trainerId/subscribe — trainee cancels/withdraws their request
  // Allowed for PENDING requests only (cannot un-approve an active subscription).
  const cancelSubscribeMatch = path.match(/\/trainers\/([^/]+)\/subscribe$/);
  if (cancelSubscribeMatch && method === "DELETE") {
    const trainerId = decodeURIComponent(cancelSubscribeMatch[1]);
    const uid = userId(event);

    // Fetch the trainee's own record to get the requestId and current status
    const ownRecord = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `USER#${uid}`, SK: `SUBSCRIPTION#${trainerId}` },
      })
    );

    if (!ownRecord.Item) {
      return err(404, "لا يوجد طلب اشتراك لدى هذا المدرب");
    }

    const item = ownRecord.Item as Record<string, unknown>;
    const status = String(item["status"] || "");
    const requestId = String(item["requestId"] || "");

    if (status === "APPROVED") {
      return err(400, "لا يمكن إلغاء اشتراك مفعّل — تواصل مع المدرب");
    }

    // Delete all 3 related records in parallel
    await Promise.all([
      // 1. Trainee's own record
      docClient.send(
        new DeleteCommand({
          TableName: TABLE,
          Key: { PK: `USER#${uid}`, SK: `SUBSCRIPTION#${trainerId}` },
        })
      ),
      // 2. Duplicate-check projection on trainer side
      docClient.send(
        new DeleteCommand({
          TableName: TABLE,
          Key: { PK: `TRAINER#${trainerId}`, SK: `CLIENT#${uid}` },
        })
      ),
      // 3. Main request item (only if we have a requestId)
      ...(requestId
        ? [
            docClient.send(
              new DeleteCommand({
                TableName: TABLE,
                Key: {
                  PK: `TRAINER#${trainerId}`,
                  SK: `SUBSCRIPTION_REQUEST#${requestId}`,
                },
              })
            ),
          ]
        : []),
    ]);

    return ok({ message: "تم إلغاء طلب الاشتراك" });
  }

  // GET /trainers/me/my-subscriptions — trainee checks their own subscriptions
  if (path.endsWith("/trainers/me/my-subscriptions") && method === "GET") {
    const uid = userId(event);
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: {
          ":pk": `USER#${uid}`,
          ":sk": "SUBSCRIPTION#",
        },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({
      subscriptions: items.map((i) => ({
        trainerId: i["trainerId"] || "",
        status: i["status"] || "PENDING",
        requestedAt: i["requestedAt"] || "",
        planId: i["planId"] || null,
        planName: i["planName"] || null,
        planPrice: i["planPrice"] ?? null,
        durationMonths: i["durationMonths"] ?? null,
        expiresAt: i["expiresAt"] || null,
      })),
    });
  }

  // POST /trainers/:trainerId/ratings
  const ratingMatch = path.match(/\/trainers\/([^/]+)\/ratings$/);
  if (ratingMatch && method === "POST") {
    const trainerId = decodeURIComponent(ratingMatch[1]);
    const uid = userId(event);
    const body = JSON.parse(event.body || "{}");
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `TRAINER#${trainerId}`,
          SK: `RATING#${uid}`,
          userId: uid,
          trainerId,
          gymId: body.gymId || "",
          rating: Number(body.rating) || 5,
          comment: body.comment || "",
          createdAt: new Date().toISOString(),
        },
      })
    );
    return ok({ message: "تم تقييم المدرب بنجاح" });
  }

  // ── GET /trainers/me/photos — list trainer's photo gallery ──────────
  if (path.endsWith("/trainers/me/photos") && method === "GET") {
    const uid = userId(event);
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `TRAINER#${uid}`, ":sk": "PHOTO#" },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({
      photos: items.map((p) => ({
        photoId: p["photoId"],
        url: p["url"],
        uploadedAt: p["uploadedAt"],
      })),
    });
  }

  // ── POST /trainers/me/photos — add photo to trainer gallery (max 6) ─
  if (path.endsWith("/trainers/me/photos") && method === "POST") {
    const uid = userId(event);
    const body = JSON.parse(event.body || "{}");
    if (!body.url) return err(400, "url مطلوب");

    const existingRes = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `TRAINER#${uid}`, ":sk": "PHOTO#" },
        Select: "COUNT",
      })
    );
    if ((existingRes.Count || 0) >= 6) {
      return err(400, "وصلت للحد الأقصى لمعرض الصور (6 صور فقط)");
    }

    const photoId = randomBytes(6).toString("hex");
    const now = new Date().toISOString();
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `TRAINER#${uid}`,
          SK: `PHOTO#${photoId}`,
          photoId,
          trainerId: uid,
          url: body.url,
          uploadedAt: now,
        },
      })
    );
    return created({ photoId, message: "تم رفع الصورة بنجاح" });
  }

  // ── DELETE /trainers/me/photos/:photoId — delete from trainer gallery ─
  const trainerPhotoDeleteMatch = path.match(
    /\/trainers\/me\/photos\/([^/]+)$/
  );
  if (trainerPhotoDeleteMatch && method === "DELETE") {
    const uid = userId(event);
    const photoId = trainerPhotoDeleteMatch[1];
    await docClient.send(
      new DeleteCommand({
        TableName: TABLE,
        Key: { PK: `TRAINER#${uid}`, SK: `PHOTO#${photoId}` },
      })
    );
    return ok({ message: "تم حذف الصورة" });
  }

  // ── GET /trainers/:trainerId/photos — public view of trainer gallery ─
  const trainerPublicPhotosMatch = path.match(/\/trainers\/([^/]+)\/photos$/);
  if (trainerPublicPhotosMatch && method === "GET") {
    const trainerId = decodeURIComponent(trainerPublicPhotosMatch[1]);
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: {
          ":pk": `TRAINER#${trainerId}`,
          ":sk": "PHOTO#",
        },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({
      photos: items.map((p) => ({
        photoId: p["photoId"],
        url: p["url"],
        uploadedAt: p["uploadedAt"],
      })),
    });
  }

  // ─── POST /trainers/me/certificates/presign — pre-signed S3 PUT (max 5) ───
  if (path.endsWith("/trainers/me/certificates/presign") && method === "POST") {
    const uid = userId(event);

    if (!TRAINER_CERTS_BUCKET) {
      return err(500, "TRAINER_CERTS_BUCKET غير مضبوط");
    }

    // Enforce max 5 at presign time
    const countRes = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `TRAINER#${uid}`, ":sk": "CERT#" },
        Select: "COUNT",
      })
    );
    if ((countRes.Count || 0) >= 5) {
      return err(400, "وصلت للحد الأقصى للشهادات/الأوسمة (5 فقط)");
    }

    const body = JSON.parse(event.body || "{}");
    const contentType = String(body.contentType || "image/jpeg");
    if (!contentType.startsWith("image/")) {
      return err(400, "contentType يجب أن يكون image/*");
    }

    const ext = guessExtFromContentType(contentType);
    const objectKey = `trainers/${uid}/certificates/${randomBytes(16).toString(
      "hex"
    )}.${ext}`;

    const cmd = new PutObjectCommand({
      Bucket: TRAINER_CERTS_BUCKET,
      Key: objectKey,
      ContentType: contentType,
    });

    const uploadUrl = await getSignedUrl(s3, cmd, { expiresIn: 60 });
    const url = `https://${TRAINER_CERTS_BUCKET}.s3.amazonaws.com/${objectKey}`;

    return ok({ uploadUrl, objectKey, url, expiresIn: 60 });
  }

  // ─── GET /trainers/me/certificates — trainer's own list ─────────────
  if (path.endsWith("/trainers/me/certificates") && method === "GET") {
    const uid = userId(event);
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `TRAINER#${uid}`, ":sk": "CERT#" },
      })
    );

    const items = (res.Items || []) as Record<string, unknown>[];
    const certificates = items
      .map((c) => ({
        id: String(c["certificateId"] || ""),
        name: String(c["name"] || ""),
        year: Number(c["year"] || 0) || null,
        description: c["description"] ? String(c["description"]) : "",
        imageUrl: String(c["imageUrl"] || c["url"] || ""),
        objectKey: c["objectKey"] ? String(c["objectKey"]) : null,
        createdAt: String(c["createdAt"] || ""),
      }))
      .filter((c) => c.id.length > 0);

    return ok({ certificates });
  }

  // ─── POST /trainers/me/certificates — create/attach certificate (max 5) ───
  if (path.endsWith("/trainers/me/certificates") && method === "POST") {
    const uid = userId(event);
    const body = JSON.parse(event.body || "{}");

    const name = String(body.name || "").trim();
    const yearRaw = body.year;
    const year = yearRaw == null ? null : Number(yearRaw);
    const description = String(body.description || "").trim();
    const imageUrl = String(body.imageUrl || body.url || "").trim();

    if (!name) return err(400, "name مطلوب");
    if (!imageUrl) return err(400, "imageUrl مطلوب");
    if (year != null && (Number.isNaN(year) || year < 1900 || year > 2100)) {
      return err(400, "year غير صالح");
    }

    // Count existing certs
    const countRes = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `TRAINER#${uid}`, ":sk": "CERT#" },
        Select: "COUNT",
      })
    );
    if ((countRes.Count || 0) >= 5) {
      return err(400, "وصلت للحد الأقصى للشهادات/الأوسمة (5 فقط)");
    }

    const certificateId = randomBytes(6).toString("hex");
    const now = new Date().toISOString();

    const objectKey =
      typeof body.objectKey === "string" && body.objectKey.trim().length > 0
        ? body.objectKey.trim()
        : parseS3ObjectKeyFromUrlForBucket(imageUrl, TRAINER_CERTS_BUCKET);

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `TRAINER#${uid}`,
          SK: `CERT#${certificateId}`,
          certificateId,
          trainerId: uid,
          name,
          year,
          description,
          imageUrl,
          objectKey: objectKey || null,
          createdAt: now,
        },
      })
    );

    return created({ id: certificateId, message: "تمت إضافة الشهادة/الوسام" });
  }

  // ─── DELETE /trainers/me/certificates/:id — delete ─────────────────
  const delCertMatch = path.match(/\/trainers\/me\/certificates\/([^/]+)$/);
  if (delCertMatch && method === "DELETE") {
    const uid = userId(event);
    const certId = delCertMatch[1];

    await docClient.send(
      new DeleteCommand({
        TableName: TABLE,
        Key: { PK: `TRAINER#${uid}`, SK: `CERT#${certId}` },
      })
    );

    return ok({ message: "تم حذف الشهادة/الوسام" });
  }

  // ─── GET /trainers/:trainerId/public — public trainer profile ───────────
  const publicProfileMatch = path.match(/\/trainers\/([^/]+)\/public$/);
  if (publicProfileMatch && method === "GET") {
    const trainerId = decodeURIComponent(publicProfileMatch[1]);

    // Fetch the user PROFILE record for this trainer
    const profileRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: {
          PK: trainerId.startsWith("USER#") ? trainerId : `USER#${trainerId}`,
          SK: "PROFILE",
        },
      })
    );

    if (!profileRes.Item) {
      return err(404, "المدرب غير موجود");
    }

    const item = profileRes.Item as Record<string, unknown>;
    const avatarObjectKey = String(item["avatarObjectKey"] || "");
    const avatarUrl = avatarObjectKey
      ? await presignAvatarViewUrl(avatarObjectKey)
      : null;

    return ok({
      trainerId,
      displayName: String(item["displayName"] || ""),
      bio: item["bio"] ? String(item["bio"]) : null,
      avatarUrl,
    });
  }

  // ─── GET /trainers/:trainerId/certificates — subscriber-only (max 5) ─────
  const publicCertMatch = path.match(/\/trainers\/([^/]+)\/certificates$/);
  if (publicCertMatch && method === "GET") {
    const trainerId = decodeURIComponent(publicCertMatch[1]);
    const uid = userId(event);

    const allowed = await isTrainerSubscriber(docClient, trainerId, uid);
    if (!allowed) {
      return err(403, "هذه البيانات متاحة فقط للمشتركين");
    }

    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: {
          ":pk": `TRAINER#${trainerId}`,
          ":sk": "CERT#",
        },
      })
    );

    const items = (res.Items || []) as Record<string, unknown>[];

    const signViewUrl = async (item: Record<string, unknown>) => {
      const storedUrl = String(item["imageUrl"] || item["url"] || "");
      const objectKey = String(item["objectKey"] || "");

      if (!TRAINER_CERTS_BUCKET) {
        return { url: storedUrl, presigned: false, expiresIn: null };
      }

      const resolvedKey =
        objectKey ||
        parseS3ObjectKeyFromUrlForBucket(storedUrl, TRAINER_CERTS_BUCKET);
      if (!resolvedKey) {
        return { url: storedUrl, presigned: false, expiresIn: null };
      }

      const viewUrl = await getSignedUrl(
        s3,
        new GetObjectCommand({
          Bucket: TRAINER_CERTS_BUCKET,
          Key: resolvedKey,
        }),
        { expiresIn: 60 * 10 }
      );

      return { url: viewUrl, presigned: true, expiresIn: 60 * 10 };
    };

    const certificates = await Promise.all(
      items.slice(0, 5).map(async (c) => ({
        id: String(c["certificateId"] || ""),
        name: String(c["name"] || ""),
        year: Number(c["year"] || 0) || null,
        description: c["description"] ? String(c["description"]) : "",
        image: await signViewUrl(c),
      }))
    );

    return ok({ certificates });
  }

  return err(404, "المسار غير موجود");
}