import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import {
  DeleteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  ScanCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";
import { randomBytes } from "crypto";
import { pushNotification } from "./notifications";

const TABLE = process.env.DYNAMODB_TABLE_NAME || "wizgym-prod-core";
const GYM_PHOTOS_BUCKET = process.env.GYM_PHOTOS_BUCKET || "";
const SUBSCRIPTION_PROOFS_BUCKET = process.env.SUBSCRIPTION_PROOFS_BUCKET || "";
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
function err(
  status: number,
  msg: string,
  additionalData?: Record<string, unknown>
): APIGatewayProxyResultV2 {
  return {
    statusCode: status,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message: msg, ...additionalData }),
  };
}

function userId(event: APIGatewayProxyEventV2): string {
  return event.headers?.["x-user-id"] || event.headers?.["X-User-Id"] || "anon";
}
function userRole(event: APIGatewayProxyEventV2): string {
  return (
    event.headers?.["x-user-role"] ||
    event.headers?.["X-User-Role"] ||
    "USER"
  ).toUpperCase();
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

async function assertGymOwnerOrAdmin(
  docClient: DynamoDBDocumentClient,
  event: APIGatewayProxyEventV2,
  gymId: string
): Promise<APIGatewayProxyResultV2 | null> {
  const role = userRole(event);
  if (role === "ADMIN") return null;
  if (role !== "OWNER") return err(403, "غير مصرح");

  const uid = userId(event);
  if (!uid || uid === "anon") return err(401, "غير مصرح");

  const profileRes = await docClient.send(
    new GetCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
      ProjectionExpression: "ownerId",
    })
  );

  const ownerId = String((profileRes.Item as any)?.ownerId || "");
  if (!ownerId) return err(404, "النادي غير موجود");
  if (ownerId !== uid)
    return err(403, "فقط مالك النادي يمكنه تنفيذ هذا الإجراء");

  return null;
}

function guessExtFromContentType(contentType: string): string {
  const ct = contentType.toLowerCase();
  if (ct.includes("jpeg")) return "jpg";
  if (ct.includes("png")) return "png";
  if (ct.includes("webp")) return "webp";
  if (ct.includes("heic")) return "heic";
  return "jpg";
}

function parseS3ObjectKeyFromUrl(url: string): string | null {
  try {
    const u = new URL(url);
    // Support virtual-hosted style: https://bucket.s3.amazonaws.com/key
    if (u.hostname.startsWith(`${GYM_PHOTOS_BUCKET}.s3`)) {
      return decodeURIComponent(u.pathname.replace(/^\//, ""));
    }
    return null;
  } catch {
    return null;
  }
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

function gymSummaryFromItem(i: Record<string, unknown>) {
  return {
    id: String(i["gymId"] || i["PK"] || "").replace("GYM#", ""),
    name: i["name"] || "",
    city: i["city"] || "",
    description: i["description"] || null,
    coverImageUrl: i["coverImageUrl"] || null,
    audience: i["audience"] || "MIXED",
    amenities: (i["amenities"] as string[]) || [],
    membersCount: Number(i["membersCount"] || 0),
    trainersCount: Number(i["trainersCount"] || 0),
    averageRating: Number(i["averageRating"] || 0),
    status: i["status"] || "ACTIVE",
    openingHours: i["openingHours"] || null,
  };
}

export async function handleGyms(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || "";
  const method = event.requestContext.http.method;
  const params = event.queryStringParameters || {};

  // ─── GET /subscriptions/plans — platform subscription plans (for owners) ───
  if (path.endsWith("/subscriptions/plans") && method === "GET") {
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
      }))
      .filter((p) => p.planId && p.isActive)
      .sort((a, b) => a.durationMonths - b.durationMonths);

    return ok({ plans });
  }

  // ─── GET /gyms/public — public listing ─────────────────────────────
  if (path.endsWith("/gyms/public") && method === "GET") {
    const filterExps: string[] = [
      "begins_with(PK, :g)",
      "SK = :p",
      "#st = :active",
    ];
    const exprNames: Record<string, string> = { "#st": "status" };
    const exprValues: Record<string, unknown> = {
      ":g": "GYM#",
      ":p": "PROFILE",
      ":active": "ACTIVE",
    };

    if (params["city"]) {
      filterExps.push("city = :city");
      exprValues[":city"] = params["city"];
    }
    if (params["audience"]) {
      filterExps.push("audience = :aud");
      exprValues[":aud"] = params["audience"];
    }

    const res = await docClient.send(
      new ScanCommand({
        TableName: TABLE,
        FilterExpression: filterExps.join(" AND "),
        ExpressionAttributeNames: exprNames,
        ExpressionAttributeValues: exprValues,
      })
    );

    let items = (res.Items || []) as Record<string, unknown>[];

    // Client-side name filter (case-insensitive contains)
    if (params["name"]) {
      const needle = params["name"].toLowerCase();
      items = items.filter((i) => {
        const n = String(i["name"] || "").toLowerCase();
        return n.includes(needle);
      });
    }

    // Fetch all studio subscriptions to enrich with subscriptionActive flag
    const subsRes = await docClient.send(
      new ScanCommand({
        TableName: TABLE,
        FilterExpression: "begins_with(PK, :g) AND SK = :s",
        ExpressionAttributeValues: { ":g": "GYM#", ":s": "SUBSCRIPTION" },
      })
    );
    const subMap: Record<string, boolean> = {};
    const nowMs = Date.now();
    for (const s of (subsRes.Items || []) as Record<string, unknown>[]) {
      const gId = String(s["PK"] || "").replace("GYM#", "");
      subMap[gId] =
        s["status"] === "ACTIVE" &&
        !!s["expiresAt"] &&
        new Date(s["expiresAt"] as string).getTime() > nowMs;
    }

    // Fetch all gym photos
    const photosRes = await docClient.send(
      new ScanCommand({
        TableName: TABLE,
        FilterExpression: "begins_with(PK, :g) AND begins_with(SK, :ph)",
        ExpressionAttributeValues: { ":g": "GYM#", ":ph": "PHOTO#" },
      })
    );

    const photoMap: Record<
      string,
      { photoId: string; url: string; objectKey: string }[]
    > = {};
    for (const p of (photosRes.Items || []) as Record<string, unknown>[]) {
      const gId = String(p["PK"] || "").replace("GYM#", "");
      if (!photoMap[gId]) photoMap[gId] = [];
      photoMap[gId].push({
        photoId: String(p["photoId"] || ""),
        url: String(p["url"] || ""),
        objectKey: String(p["objectKey"] || ""),
      });
    }

    const signPhoto = async (
      gymId: string,
      photo: { photoId: string; url: string; objectKey: string }
    ) => {
      if (!GYM_PHOTOS_BUCKET) {
        return {
          photoId: photo.photoId,
          url: photo.url,
          expiresIn: null,
          presigned: false,
        };
      }

      const resolvedKey = photo.objectKey || parseS3ObjectKeyFromUrl(photo.url);
      if (!resolvedKey) {
        return {
          photoId: photo.photoId,
          url: photo.url,
          expiresIn: null,
          presigned: false,
        };
      }

      const signed = await getSignedUrl(
        s3,
        new GetObjectCommand({ Bucket: GYM_PHOTOS_BUCKET, Key: resolvedKey }),
        { expiresIn: 60 * 10 }
      );

      return {
        photoId: photo.photoId,
        url: signed,
        expiresIn: 60 * 10,
        presigned: true,
      };
    };

    return ok(
      await Promise.all(
        items.map(async (i) => {
          const gId = String(i["gymId"] || i["PK"] || "").replace("GYM#", "");
          const photos = photoMap[gId] || [];
          const photoViewUrls = await Promise.all(
            photos.map((p) => signPhoto(gId, p))
          );

          return {
            ...gymSummaryFromItem(i),
            subscriptionActive: subMap[gId] === true,
            // Back-compat: keep raw urls/keys list for older clients
            photos: photos
              .map((p) => p.url)
              .filter((u) => u && u.trim().length > 0),
            // Preferred for clients: presigned (works with private S3)
            photoViewUrls,
          };
        })
      )
    );
  }

  // ─── GET /gyms/owner/mine — owner's gyms ──────────────────────────
  if (path.endsWith("/gyms/owner/mine") && method === "GET") {
    const uid = userId(event);
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        IndexName: "GSI1",
        KeyConditionExpression: "GSI1PK = :pk",
        ExpressionAttributeValues: { ":pk": `OWNER#${uid}` },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(items.map(gymSummaryFromItem));
  }

  // ─── GET /gyms/my-memberships — all gyms the current user belongs to ─
  if (path.endsWith("/gyms/my-memberships") && method === "GET") {
    const uid = userId(event);

    // Query GSI2 where GSI2PK = USER_GYMS#<userId>
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        IndexName: "GSI2",
        KeyConditionExpression: "GSI2PK = :pk",
        ExpressionAttributeValues: { ":pk": `USER_GYMS#${uid}` },
      })
    );

    const memberships = (res.Items || []) as Record<string, unknown>[];

    // For each membership, fetch the gym profile to get gym name/city
    const enriched = await Promise.all(
      memberships.map(async (m) => {
        const gId = String(m["gymId"] || "");
        let gymName = "";
        let gymCity = "";
        if (gId) {
          const gymRes = await docClient.send(
            new GetCommand({
              TableName: TABLE,
              Key: { PK: `GYM#${gId}`, SK: "PROFILE" },
              ProjectionExpression: "#n, city",
              ExpressionAttributeNames: { "#n": "name" },
            })
          );
          const gymItem = gymRes.Item as Record<string, unknown> | undefined;
          gymName = String(gymItem?.["name"] || "");
          gymCity = String(gymItem?.["city"] || "");
        }

        return {
          gymId: gId,
          gymName,
          gymCity,
          status: m["status"] || "PENDING",
          joinedAt: m["joinedAt"] || null,
          selectedPlanId: m["selectedPlanId"] || null,
          selectedPlanTitle: m["selectedPlanTitle"] || null,
          selectedPlanDurationMonths: m["selectedPlanDurationMonths"] ?? null,
          subscriptionStartsAt: m["subscriptionStartsAt"] || null,
          subscriptionExpiresAt: m["subscriptionExpiresAt"] || null,
          nextPlanId: m["nextPlanId"] || null,
          nextPlanTitle: m["nextPlanTitle"] || null,
          nextPlanStartsAt: m["nextPlanStartsAt"] || null,
          nextPlanExpiresAt: m["nextPlanExpiresAt"] || null,
        };
      })
    );

    return ok({ memberships: enriched });
  }

  // ─── POST /gyms — create gym ──────────────────────────────────────
  if (path.endsWith("/gyms") && method === "POST") {
    const uid = userId(event);
    const role = userRole(event);
    if (role !== "OWNER" && role !== "ADMIN") {
      return err(403, "فقط أصحاب النوادي يمكنهم إنشاء نادي");
    }

    const body = JSON.parse(event.body || "{}");
    const gymId = randomBytes(8).toString("hex");
    const now = new Date().toISOString();

    // Create gym profile
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: "PROFILE",
          gymId,
          name: body.name || "",
          city: body.city || "",
          description: body.description || null,
          coverImageUrl: body.coverImageUrl || null,
          audience: body.audience || "MIXED",
          amenities: body.amenities || [],
          openingHours: body.openingHours || null,
          ownerId: uid,
          ownerName: userName(event),
          status: "PENDING_APPROVAL",
          membersCount: 0,
          trainersCount: 0,
          averageRating: 0,
          createdAt: now,
          updatedAt: now,
          // GSI1 for owner lookup
          GSI1PK: `OWNER#${uid}`,
          GSI1SK: `GYM#${gymId}`,
        },
      })
    );

    // Create subscription plans if provided
    const plans = Array.isArray(body.subscriptionPlans)
      ? body.subscriptionPlans
      : [];
    for (const plan of plans) {
      const planId = randomBytes(6).toString("hex");
      await docClient.send(
        new PutCommand({
          TableName: TABLE,
          Item: {
            PK: `GYM#${gymId}`,
            SK: `PLAN#${planId}`,
            planId,
            gymId,
            title: plan.title || "",
            durationMonths: Number(plan.durationMonths) || 1,
            price: Number(plan.price) || 0,
            currency: plan.currency || "IQD",
            description: plan.description || null,
            isActive: true,
            createdAt: now,
          },
        })
      );
    }

    return created({ id: gymId, message: "تم إنشاء النادي بنجاح" });
  }

  // ─── Parameterized gym routes (/gyms/:gymId/...) ───────────────────

  // GET /gyms/:gymId/public — gym detail
  const detailMatch = path.match(/\/gyms\/([^/]+)\/public$/);
  if (detailMatch && method === "GET") {
    const gymId = detailMatch[1];
    const profileRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
      })
    );
    if (!profileRes.Item) return err(404, "النادي غير موجود");

    const profile = profileRes.Item as Record<string, unknown>;

    // Fetch subscription plans, facilities, products, photos in parallel
    const [plansRes, facRes, prodRes, gymPhotosRes] = await Promise.all([
      docClient.send(
        new QueryCommand({
          TableName: TABLE,
          KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
          ExpressionAttributeValues: { ":pk": `GYM#${gymId}`, ":sk": "PLAN#" },
        })
      ),
      docClient.send(
        new QueryCommand({
          TableName: TABLE,
          KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
          ExpressionAttributeValues: {
            ":pk": `GYM#${gymId}`,
            ":sk": "FACILITY#",
          },
        })
      ),
      docClient.send(
        new QueryCommand({
          TableName: TABLE,
          KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
          ExpressionAttributeValues: {
            ":pk": `GYM#${gymId}`,
            ":sk": "PRODUCT#",
          },
        })
      ),
      docClient.send(
        new QueryCommand({
          TableName: TABLE,
          KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
          ExpressionAttributeValues: {
            ":pk": `GYM#${gymId}`,
            ":sk": "PHOTO#",
          },
        })
      ),
    ]);

    const plans = ((plansRes.Items || []) as Record<string, unknown>[]).map(
      (p) => ({
        planId: p["planId"] || "",
        title: p["title"] || "",
        durationMonths: Number(p["durationMonths"] || 1),
        price: Number(p["price"] || 0),
        currency: p["currency"] || "IQD",
        description: p["description"] || null,
        isActive: p["isActive"] !== false,
      })
    );

    const facilities = ((facRes.Items || []) as Record<string, unknown>[]).map(
      (f) => ({
        id: f["facilityId"] || "",
        name: f["name"] || "",
        description: f["description"] || null,
      })
    );

    const products = ((prodRes.Items || []) as Record<string, unknown>[]).map(
      (p) => ({
        id: p["productId"] || "",
        title: p["title"] || "",
        description: p["description"] || null,
        price: p["price"] != null ? Number(p["price"]) : null,
      })
    );

    const gymPhotosRaw = (
      (gymPhotosRes.Items || []) as Record<string, unknown>[]
    ).map((p) => ({
      photoId: String(p["photoId"] || ""),
      url: String(p["url"] || ""),
      objectKey: String(p["objectKey"] || ""),
      uploadedAt: String(p["uploadedAt"] || ""),
    }));

    // Generate presigned URLs for private S3 photos (same logic as listing endpoint)
    const gymPhotos = await Promise.all(
      gymPhotosRaw.map(async (p) => {
        if (!GYM_PHOTOS_BUCKET)
          return { photoId: p.photoId, url: p.url, uploadedAt: p.uploadedAt };
        const resolvedKey = p.objectKey || parseS3ObjectKeyFromUrl(p.url);
        if (!resolvedKey)
          return { photoId: p.photoId, url: p.url, uploadedAt: p.uploadedAt };
        try {
          const signed = await getSignedUrl(
            s3,
            new GetObjectCommand({
              Bucket: GYM_PHOTOS_BUCKET,
              Key: resolvedKey,
            }),
            { expiresIn: 60 * 10 }
          );
          return { photoId: p.photoId, url: signed, uploadedAt: p.uploadedAt };
        } catch {
          return { photoId: p.photoId, url: p.url, uploadedAt: p.uploadedAt };
        }
      })
    );

    const rawOwnerName = String(profile["ownerName"] || "");
    let decodedOwnerName = rawOwnerName;
    try {
      decodedOwnerName = decodeURIComponent(rawOwnerName);
    } catch {
      /* keep raw */
    }

    return ok({
      id: gymId,
      name: profile["name"] || "",
      city: profile["city"] || "",
      description: profile["description"] || null,
      coverImageUrl: profile["coverImageUrl"] || null,
      audience: profile["audience"] || "MIXED",
      amenities: (profile["amenities"] as string[]) || [],
      ownerName: decodedOwnerName,
      averageRating: Number(profile["averageRating"] || 0),
      status: profile["status"] || "",
      openingHours: profile["openingHours"] || null,
      photos: gymPhotos,
      photoViewUrls: gymPhotos.map((p) => ({ url: p.url })),
      facilities,
      products,
      subscriptionPlans: plans,
    });
  }

  // ─── PATCH /gyms/:gymId/profile — update gym profile ──────────────
  const profilePatch = path.match(/\/gyms\/([^/]+)\/profile$/);
  if (profilePatch && method === "PATCH") {
    const gymId = profilePatch[1];

    const authErr = await assertGymOwnerOrAdmin(docClient, event, gymId);
    if (authErr) return authErr;

    const body = JSON.parse(event.body || "{}");
    const now = new Date().toISOString();

    const updateParts: string[] = ["updatedAt = :now"];
    const exprValues: Record<string, unknown> = { ":now": now };
    const exprNames: Record<string, string> = {};

    if (body.audience !== undefined) {
      updateParts.push("audience = :aud");
      exprValues[":aud"] = body.audience;
    }
    if (body.amenities !== undefined) {
      updateParts.push("amenities = :am");
      exprValues[":am"] = body.amenities;
    }
    if (body.description !== undefined) {
      updateParts.push("#desc = :desc");
      exprNames["#desc"] = "description";
      exprValues[":desc"] = body.description;
    }
    if (body.name !== undefined) {
      updateParts.push("#nm = :nm");
      exprNames["#nm"] = "name";
      exprValues[":nm"] = body.name;
    }
    if (body.city !== undefined) {
      updateParts.push("city = :city");
      exprValues[":city"] = body.city;
    }
    if (body.coverImageUrl !== undefined) {
      updateParts.push("coverImageUrl = :img");
      exprValues[":img"] = body.coverImageUrl;
    }

    if (body.openingHours !== undefined) {
      updateParts.push("openingHours = :oh");
      exprValues[":oh"] = body.openingHours;
    }

    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
        UpdateExpression: `SET ${updateParts.join(", ")}`,
        ...(Object.keys(exprNames).length > 0
          ? { ExpressionAttributeNames: exprNames }
          : {}),
        ExpressionAttributeValues: exprValues,
      })
    );

    return ok({ message: "تم تحديث ملف النادي" });
  }

  // ─── GET /gyms/:gymId/trainers — list gym trainers ─────────────────
  const trainersMatch = path.match(/\/gyms\/([^/]+)\/trainers$/);
  if (trainersMatch && method === "GET") {
    const gymId = trainersMatch[1];
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `GYM#${gymId}`, ":sk": "TRAINER#" },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(
      items.map((t) => ({
        trainerId: t["trainerId"] || "",
        displayName: t["displayName"] || "",
        activeClients: Number(t["activeClients"] || 0),
        averageRating: Number(t["averageRating"] || 0),
        hiredByRequester: false,
      }))
    );
  }

  // ─── POST /gyms/:gymId/trainers/join — trainer joins a gym ─────────
  const trainerJoinMatch = path.match(/\/gyms\/([^/]+)\/trainers\/join$/);
  if (trainerJoinMatch && method === "POST") {
    const gymId = trainerJoinMatch[1];
    const uid = userId(event);
    const uName = userName(event);
    const now = new Date().toISOString();

    // ── Check gym is approved (ACTIVE) ──────────────────────────────
    const gymCheck = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
        ProjectionExpression: "#st, ownerId",
        ExpressionAttributeNames: { "#st": "status" },
      })
    );
    const gymCheckItem = gymCheck.Item as Record<string, unknown> | undefined;
    if (!gymCheckItem || gymCheckItem["status"] !== "ACTIVE") {
      return err(403, "هذا النادي غير معتمد ولا يقبل مدربين جدد");
    }

    // ── Check studio platform subscription is active ─────────────────
    const trainerSubRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "SUBSCRIPTION" },
      })
    );
    const trainerSub = trainerSubRes.Item as
      | Record<string, unknown>
      | undefined;
    const trainerSubActive =
      trainerSub &&
      trainerSub["status"] === "ACTIVE" &&
      trainerSub["expiresAt"] &&
      new Date(trainerSub["expiresAt"] as string).getTime() > Date.now();
    if (!trainerSubActive) {
      return err(403, "هذا النادي غير مفعّل حالياً ولا يقبل مدربين جدد");
    }

    // Store trainer in gym
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: `TRAINER#${uid}`,
          trainerId: uid,
          gymId,
          displayName: uName,
          activeClients: 0,
          averageRating: 0,
          joinedAt: now,
        },
      })
    );

    // Increment trainersCount
    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
        UpdateExpression:
          "SET trainersCount = if_not_exists(trainersCount, :zero) + :one, updatedAt = :now",
        ExpressionAttributeValues: { ":zero": 0, ":one": 1, ":now": now },
      })
    );

    // Notify gym owner
    const gymProfile = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
      })
    );
    const ownerId = (gymProfile.Item as Record<string, unknown> | undefined)?.[
      "ownerId"
    ] as string | undefined;
    if (ownerId) {
      await pushNotification(docClient, {
        targetUserId: ownerId,
        eventType: "TRAINER_JOINED",
        title: "مدرب جديد انضم للنادي 🏋️",
        message: `${uName || "مدرب"} انضم إلى ناديك`,
        payload: { gymId, trainerId: uid },
      }).catch(() => {
        /* silent */
      });
    }

    return created({ message: "تم انضمام المدرب للنادي بنجاح" });
  }

  // ─── DELETE /gyms/:gymId/trainers/me — trainer leaves a gym ────────
  const trainerLeaveMatch = path.match(/\/gyms\/([^/]+)\/trainers\/me$/);
  if (trainerLeaveMatch && method === "DELETE") {
    const gymId = trainerLeaveMatch[1];
    const uid = userId(event);
    const now = new Date().toISOString();

    // Remove trainer from gym
    await docClient.send(
      new DeleteCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `TRAINER#${uid}` },
      })
    );

    // Decrement trainersCount (best effort)
    await docClient
      .send(
        new UpdateCommand({
          TableName: TABLE,
          Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
          UpdateExpression:
            "SET trainersCount = if_not_exists(trainersCount, :zero) - :one, updatedAt = :now",
          ConditionExpression:
            "attribute_not_exists(trainersCount) OR trainersCount >= :one",
          ExpressionAttributeValues: { ":zero": 0, ":one": 1, ":now": now },
        })
      )
      .catch(() => {
        /* ignore */
      });

    return ok({ message: "تم إلغاء الانضمام للنادي" });
  }

  // ─── POST /gyms/:gymId/trainers/:trainerId/hire — hire trainer ─────
  const hireMatch = path.match(/\/gyms\/([^/]+)\/trainers\/([^/]+)\/hire$/);
  if (hireMatch && method === "POST") {
    const gymId = hireMatch[1];
    const trainerId = decodeURIComponent(hireMatch[2]);
    const now = new Date().toISOString();

    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `TRAINER#${trainerId}` },
        UpdateExpression: "SET hiredAt = :now",
        ExpressionAttributeValues: { ":now": now },
      })
    );

    return ok({ message: "تم توظيف المدرب بنجاح" });
  }

  // ─── POST /gyms/:gymId/join — user joins gym ──────────────────────
  const joinMatch = path.match(/\/gyms\/([^/]+)\/join$/);
  if (joinMatch && method === "POST") {
    const gymId = joinMatch[1];
    const uid = userId(event);
    const uName = userName(event);
    const body = JSON.parse(event.body || "{}");
    const now = new Date().toISOString();

    // ── Check gym is approved (ACTIVE status) ───────────────────────
    const gymProfileCheck = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
        ProjectionExpression: "#st",
        ExpressionAttributeNames: { "#st": "status" },
      })
    );
    const gymStatus = (
      gymProfileCheck.Item as Record<string, unknown> | undefined
    )?.["status"];
    if (gymStatus !== "ACTIVE") {
      return err(403, "هذا النادي غير معتمد ولا يقبل أعضاء جدد");
    }

    // ── Check studio platform subscription is active ─────────────────
    const studioSubRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "SUBSCRIPTION" },
      })
    );
    const studioSub = studioSubRes.Item as Record<string, unknown> | undefined;
    const subIsActive =
      studioSub &&
      studioSub["status"] === "ACTIVE" &&
      studioSub["expiresAt"] &&
      new Date(studioSub["expiresAt"] as string).getTime() > Date.now();
    if (!subIsActive) {
      return err(403, "هذا النادي غير مفعّل حالياً ولا يقبل أعضاء جدد");
    }

    // ── Check existing membership ────────────────────────────────────
    const existingRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${uid}` },
      })
    );
    const existing = existingRes.Item as Record<string, unknown> | undefined;

    // ── Guard: max 2 concurrent ACTIVE gym memberships (across gyms) ─
    // Only applies when creating a NEW join request (i.e., not already active in this gym).
    // We count ACTIVE memberships where subscription is still valid (if expiry exists).
    // NOTE: Pending requests are allowed; approval will re-check.
    if (
      !existing ||
      String(existing["status"] || "").toUpperCase() !== "ACTIVE"
    ) {
      const activeRes = await docClient.send(
        new QueryCommand({
          TableName: TABLE,
          IndexName: "GSI2",
          KeyConditionExpression: "GSI2PK = :pk AND begins_with(GSI2SK, :sk)",
          ExpressionAttributeValues: {
            ":pk": `USER_GYMS#${uid}`,
            ":sk": "GYM#",
          },
        })
      );

      const nowDate = new Date();
      const activeOtherGyms = (
        (activeRes.Items || []) as Record<string, unknown>[]
      )
        .filter((m) => String(m["status"] || "").toUpperCase() === "ACTIVE")
        .filter((m) => {
          const exp = m["subscriptionExpiresAt"] as string | undefined | null;
          // If expiry is missing, treat as active.
          if (!exp) return true;
          return new Date(exp) > nowDate;
        })
        .map((m) => String(m["gymId"] || ""))
        // exclude current gym if present
        .filter((gid) => gid && gid !== gymId);

      if (activeOtherGyms.length >= 2) {
        return err(
          409,
          "لديك اشتراك فعّال في الحد الأقصى من النوادي (2) ولا يمكن إرسال طلب جديد"
        ) as any;
      }

      // If user has at least one active membership elsewhere, return a warning-like error.
      // Client should show a confirm dialog and allow the user to proceed by resending
      // with `forceJoin: true`.
      if (activeOtherGyms.length >= 1 && body.forceJoin !== true) {
        return err(409, "لديك اشتراك فعّال في نادي آخر. هل تريد الاستمرار؟", {
          code: "HAS_ACTIVE_MEMBERSHIP",
          activeGymsCount: activeOtherGyms.length,
          limit: 2,
        });
      }
    }

    // Look up plan details if planId provided
    let selectedPlanTitle: string | null = null;
    let selectedPlanDurationMonths: number | null = null;
    if (body.planId) {
      const planRes = await docClient.send(
        new GetCommand({
          TableName: TABLE,
          Key: { PK: `GYM#${gymId}`, SK: `PLAN#${body.planId}` },
        })
      );
      if (planRes.Item) {
        selectedPlanTitle = (planRes.Item["title"] as string) || null;
        selectedPlanDurationMonths =
          Number(planRes.Item["durationMonths"]) || null;
      }
    }

    // ── Case 1: Active member with unexpired plan → queue next plan ──
    if (existing) {
      const existingStatus = String(existing["status"] || "").toUpperCase();
      const existingExpiry = existing["subscriptionExpiresAt"] as
        | string
        | undefined;

      // Reject if already PENDING
      if (existingStatus === "PENDING") {
        return err(409, "لديك طلب انضمام معلّق بالفعل لهذا النادي");
      }

      // Active member — allow renewal / next plan
      if (existingStatus === "ACTIVE") {
        // If current plan is still valid, queue the new plan after it
        if (existingExpiry && new Date(existingExpiry) > new Date()) {
          if (!body.planId) {
            return err(
              400,
              "لديك اشتراك فعّال. اختر خطة جديدة للتجديد بعد انتهاء الخطة الحالية."
            );
          }

          // Calculate next plan start = current expiry, next plan end = start + duration
          const nextStartsAt = existingExpiry;
          let nextExpiresAt: string | null = null;
          if (selectedPlanDurationMonths) {
            const nextExpiry = new Date(nextStartsAt);
            nextExpiry.setMonth(
              nextExpiry.getMonth() + selectedPlanDurationMonths
            );
            nextExpiresAt = nextExpiry.toISOString();
          }

          await docClient.send(
            new UpdateCommand({
              TableName: TABLE,
              Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${uid}` },
              UpdateExpression:
                "SET nextPlanId = :npId, nextPlanTitle = :npTitle, nextPlanDurationMonths = :npDur, nextPlanStartsAt = :npStart, nextPlanExpiresAt = :npExp, updatedAt = :now",
              ExpressionAttributeValues: {
                ":npId": body.planId,
                ":npTitle": selectedPlanTitle,
                ":npDur": selectedPlanDurationMonths,
                ":npStart": nextStartsAt,
                ":npExp": nextExpiresAt,
                ":now": now,
              },
            })
          );

          return ok({
            message: `تم حجز خطة "${selectedPlanTitle || "جديدة"}" — تبدأ بعد انتهاء خطتك الحالية`,
            nextPlanStartsAt: nextStartsAt,
            nextPlanExpiresAt: nextExpiresAt,
          });
        }

        // Current plan expired — allow switching to new plan immediately
        if (body.planId) {
          const subscriptionStartsAt = now;
          let subscriptionExpiresAt: string | null = null;
          if (selectedPlanDurationMonths) {
            const expiry = new Date();
            expiry.setMonth(expiry.getMonth() + selectedPlanDurationMonths);
            subscriptionExpiresAt = expiry.toISOString();
          }

          await docClient.send(
            new UpdateCommand({
              TableName: TABLE,
              Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${uid}` },
              UpdateExpression:
                "SET selectedPlanId = :pId, selectedPlanTitle = :pTitle, selectedPlanDurationMonths = :pDur, subscriptionStartsAt = :sStart, subscriptionExpiresAt = :sExp, nextPlanId = :null, nextPlanTitle = :null, nextPlanDurationMonths = :null, nextPlanStartsAt = :null, nextPlanExpiresAt = :null, updatedAt = :now",
              ExpressionAttributeValues: {
                ":pId": body.planId,
                ":pTitle": selectedPlanTitle,
                ":pDur": selectedPlanDurationMonths,
                ":sStart": subscriptionStartsAt,
                ":sExp": subscriptionExpiresAt,
                ":null": null,
                ":now": now,
              },
            })
          );

          return ok({
            message: "تم تجديد الاشتراك بنجاح",
            subscriptionStartsAt,
            subscriptionExpiresAt,
          });
        }

        return err(409, "أنت عضو بالفعل في هذا النادي");
      }
    }

    // ── Case 2: New member (or rejected) — create fresh membership ────
    let subscriptionStartsAt: string | null = null;
    let subscriptionExpiresAt: string | null = null;
    if (selectedPlanDurationMonths) {
      subscriptionStartsAt = now;
      const expiry = new Date();
      expiry.setMonth(expiry.getMonth() + selectedPlanDurationMonths);
      subscriptionExpiresAt = expiry.toISOString();
    }

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: `MEMBER#${uid}`,
          userId: uid,
          userName: uName,
          gymId,
          selectedPlanId: body.planId || null,
          selectedPlanTitle,
          selectedPlanDurationMonths,
          subscriptionStartsAt,
          subscriptionExpiresAt,
          nextPlanId: null,
          nextPlanTitle: null,
          nextPlanDurationMonths: null,
          nextPlanStartsAt: null,
          nextPlanExpiresAt: null,
          status: "PENDING",
          joinedAt: now,
          // GSI2 for user's own gym-memberships lookup
          GSI2PK: `USER_GYMS#${uid}`,
          GSI2SK: `GYM#${gymId}`,
        },
      })
    );

    // Notify gym owner
    const gymProfile = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
      })
    );
    const ownerId = (gymProfile.Item as Record<string, unknown> | undefined)?.[
      "ownerId"
    ] as string | undefined;
    if (ownerId) {
      await pushNotification(docClient, {
        targetUserId: ownerId,
        eventType: "MEMBER_JOIN_REQUEST",
        title: "طلب انضمام جديد 🆕",
        message: `${uName || "عضو"} يريد الانضمام إلى ناديك`,
        payload: { gymId, userId: uid },
      }).catch(() => {
        /* silent */
      });
    }

    return created({ message: "تم إرسال طلب الانضمام", status: "PENDING" });
  }

  // ─── GET /gyms/:gymId/members — list gym members ───────────────────
  const membersListMatch = path.match(/\/gyms\/([^/]+)\/members$/);
  if (membersListMatch && method === "GET") {
    const gymId = membersListMatch[1];
    const statusFilter = params["status"];

    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        ConsistentRead: true,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ...(statusFilter
          ? {
              FilterExpression: "#st = :sf",
              ExpressionAttributeNames: { "#st": "status" },
              ExpressionAttributeValues: {
                ":pk": `GYM#${gymId}`,
                ":sk": "MEMBER#",
                ":sf": statusFilter.toUpperCase(),
              },
            }
          : {
              ExpressionAttributeValues: {
                ":pk": `GYM#${gymId}`,
                ":sk": "MEMBER#",
              },
            }),
      })
    );

    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(
      items.map((m) => {
        // Prefer the stored userId; fall back to extracting from SK (MEMBER#<userId>)
        const sk = String(m["SK"] || "");
        const extractedUserId = sk.startsWith("MEMBER#")
          ? sk.slice("MEMBER#".length)
          : "";
        return {
          userId: m["userId"] || extractedUserId || "",
          userName: m["userName"] || "",
          gymId: m["gymId"] || gymId,
          status: m["status"] || "PENDING",
          joinedAt: m["joinedAt"] || "",
          selectedPlanId: m["selectedPlanId"] || null,
          selectedPlanTitle: m["selectedPlanTitle"] || null,
          selectedPlanDurationMonths: m["selectedPlanDurationMonths"] || null,
          subscriptionStartsAt: m["subscriptionStartsAt"] || null,
          subscriptionExpiresAt: m["subscriptionExpiresAt"] || null,
          nextPlanId: m["nextPlanId"] || null,
          nextPlanTitle: m["nextPlanTitle"] || null,
          nextPlanDurationMonths: m["nextPlanDurationMonths"] || null,
          nextPlanStartsAt: m["nextPlanStartsAt"] || null,
          nextPlanExpiresAt: m["nextPlanExpiresAt"] || null,
        };
      })
    );
  }

  // ─── PATCH /gyms/:gymId/members/:memberId — approve/reject member ─
  const memberActionMatch = path.match(/\/gyms\/([^/]+)\/members\/([^/]+)$/);
  if (memberActionMatch && method === "PATCH") {
    const gymId = memberActionMatch[1];
    const memberId = decodeURIComponent(memberActionMatch[2]);
    const body = JSON.parse(event.body || "{}");
    const action = (body.action || "").toUpperCase();

    if (action !== "APPROVE" && action !== "REJECT") {
      return err(400, "action يجب أن يكون APPROVE أو REJECT");
    }

    // Authorization: only the gym owner or an admin can approve/reject members
    const role = userRole(event);
    const requesterId = userId(event);
    if (role !== "OWNER" && role !== "ADMIN") {
      return err(403, "غير مصرح");
    }

    const gymProfileRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
        ProjectionExpression: "ownerId",
      })
    );
    const ownerId = (
      gymProfileRes.Item as Record<string, unknown> | undefined
    )?.["ownerId"] as string | undefined;
    if (role !== "ADMIN" && ownerId && ownerId !== requesterId) {
      return err(403, "غير مصرح");
    }

    const newStatus = action === "APPROVE" ? "ACTIVE" : "REJECTED";
    const now = new Date().toISOString();

    // Get current member status
    const currentMember = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${memberId}` },
      })
    );

    if (!currentMember.Item) {
      return err(404, "العضو غير موجود");
    }

    const oldStatus = String(
      (currentMember.Item as Record<string, unknown>)["status"] || "PENDING"
    ).toUpperCase();

    // Idempotent behavior: if it's already in the target status, return OK
    if (oldStatus === newStatus) {
      return ok({
        message: action === "APPROVE" ? "تم قبول العضو" : "تم رفض العضو",
      });
    }

    // If approving: enforce max 2 concurrent ACTIVE gym memberships for that member.
    if (newStatus === "ACTIVE") {
      const activeRes = await docClient.send(
        new QueryCommand({
          TableName: TABLE,
          IndexName: "GSI2",
          KeyConditionExpression: "GSI2PK = :pk AND begins_with(GSI2SK, :sk)",
          ExpressionAttributeValues: {
            ":pk": `USER_GYMS#${memberId}`,
            ":sk": "GYM#",
          },
        })
      );

      const nowDate = new Date();
      const activeCount = ((activeRes.Items || []) as Record<string, unknown>[])
        .filter((m) => String(m["status"] || "").toUpperCase() === "ACTIVE")
        .filter((m) => {
          const exp = m["subscriptionExpiresAt"] as string | undefined | null;
          if (!exp) return true;
          return new Date(exp) > nowDate;
        })
        .map((m) => String(m["gymId"] || ""))
        .filter((gid) => gid)
        // exclude this gym (we're about to approve it)
        .filter((gid) => gid !== gymId).length;

      if (activeCount >= 2) {
        return err(
          409,
          "لا يمكن قبول العضو لأنه يملك اشتراكاً فعّالاً في ناديين بالفعل (الحد الأقصى 2)"
        );
      }
    }

    // Update member status
    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${memberId}` },
        UpdateExpression: "SET #st = :s, updatedAt = :now",
        ExpressionAttributeNames: { "#st": "status" },
        ExpressionAttributeValues: { ":s": newStatus, ":now": now },
      })
    );

    // Update membersCount based on status change
    if (newStatus === "ACTIVE" && oldStatus !== "ACTIVE") {
      // Becoming active from pending/rejected: increment
      await docClient.send(
        new UpdateCommand({
          TableName: TABLE,
          Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
          UpdateExpression:
            "SET membersCount = if_not_exists(membersCount, :zero) + :one, updatedAt = :now",
          ExpressionAttributeValues: { ":zero": 0, ":one": 1, ":now": now },
        })
      );
    } else if (newStatus === "REJECTED" && oldStatus === "ACTIVE") {
      // Becoming rejected from active: decrement (best-effort, never below 0)
      await docClient
        .send(
          new UpdateCommand({
            TableName: TABLE,
            Key: { PK: `GYM#${gymId}`, SK: "PROFILE" },
            UpdateExpression:
              "SET membersCount = if_not_exists(membersCount, :zero) - :one, updatedAt = :now",
            ConditionExpression:
              "attribute_not_exists(membersCount) OR membersCount >= :one",
            ExpressionAttributeValues: { ":zero": 0, ":one": 1, ":now": now },
          })
        )
        .catch(() => {
          /* ignore */
        });
    }

    // Notify the member
    await pushNotification(docClient, {
      targetUserId: memberId,
      eventType:
        action === "APPROVE" ? "MEMBERSHIP_APPROVED" : "MEMBERSHIP_REJECTED",
      title:
        action === "APPROVE"
          ? "تم قبول طلب الانضمام! 🎉"
          : "تم رفض طلب الانضمام",
      message:
        action === "APPROVE"
          ? "تم قبولك في النادي — مرحباً بك!"
          : "للأسف تم رفض طلب انضمامك. يمكنك المحاولة لاحقاً.",
      payload: { gymId, action },
    }).catch(() => {
      /* silent */
    });

    return ok({
      message: action === "APPROVE" ? "تم قبول العضو" : "تم رفض العضو",
    });
  }

  // ─── Subscription plans routes ─────────────────────────────────────

  // PATCH /gyms/:gymId/subscription-plans/:planId — update plan (match BEFORE the list/create)
  const planUpdateMatch = path.match(
    /\/gyms\/([^/]+)\/subscription-plans\/([^/]+)$/
  );
  if (planUpdateMatch && method === "PATCH") {
    const gymId = planUpdateMatch[1];
    const planId = planUpdateMatch[2];
    const body = JSON.parse(event.body || "{}");
    const now = new Date().toISOString();

    const updateParts: string[] = ["updatedAt = :now"];
    const exprValues: Record<string, unknown> = { ":now": now };
    const exprNames: Record<string, string> = {};

    if (body.title !== undefined) {
      updateParts.push("title = :t");
      exprValues[":t"] = body.title;
    }
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
      exprValues[":c"] = body.currency;
    }
    if (body.description !== undefined) {
      updateParts.push("#desc = :desc");
      exprNames["#desc"] = "description";
      exprValues[":desc"] = body.description;
    }
    if (body.isActive !== undefined) {
      updateParts.push("isActive = :a");
      exprValues[":a"] = body.isActive === true;
    }

    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `PLAN#${planId}` },
        UpdateExpression: `SET ${updateParts.join(", ")}`,
        ...(Object.keys(exprNames).length > 0
          ? { ExpressionAttributeNames: exprNames }
          : {}),
        ExpressionAttributeValues: exprValues,
      })
    );

    return ok({ message: "تم تحديث خطة الاشتراك" });
  }

  // DELETE /gyms/:gymId/subscription-plans/:planId — delete plan
  if (planUpdateMatch && method === "DELETE") {
    const gymId = planUpdateMatch[1];
    const planId = planUpdateMatch[2];

    await docClient.send(
      new DeleteCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `PLAN#${planId}` },
      })
    );

    return ok({ message: "تم حذف خطة الاشتراك" });
  }

  // POST /gyms/:gymId/subscription-plans — create plan
  const planListMatch = path.match(/\/gyms\/([^/]+)\/subscription-plans$/);
  if (planListMatch && method === "POST") {
    const gymId = planListMatch[1];
    const body = JSON.parse(event.body || "{}");
    const planId = randomBytes(6).toString("hex");
    const now = new Date().toISOString();

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: `PLAN#${planId}`,
          planId,
          gymId,
          title: body.title || "",
          durationMonths: Number(body.durationMonths) || 1,
          price: Number(body.price) || 0,
          currency: body.currency || "IQD",
          description: body.description || null,
          isActive: true,
          createdAt: now,
        },
      })
    );

    return created({ planId, message: "تم إنشاء خطة الاشتراك" });
  }

  // GET /gyms/:gymId/subscription-plans — list plans
  if (planListMatch && method === "GET") {
    const gymId = planListMatch[1];
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `GYM#${gymId}`, ":sk": "PLAN#" },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(
      items.map((p) => ({
        planId: p["planId"] || "",
        title: p["title"] || "",
        durationMonths: Number(p["durationMonths"] || 1),
        price: Number(p["price"] || 0),
        currency: p["currency"] || "IQD",
        description: p["description"] || null,
        isActive: p["isActive"] !== false,
      }))
    );
  }

  // ─── POST /gyms/:gymId/ratings — rate a gym ────────────────────────
  const ratingMatch = path.match(/\/gyms\/([^/]+)\/ratings$/);
  if (ratingMatch && method === "POST") {
    const gymId = ratingMatch[1];
    const uid = userId(event);
    const body = JSON.parse(event.body || "{}");
    const now = new Date().toISOString();

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: `RATING#${uid}`,
          userId: uid,
          gymId,
          rating: Number(body.rating) || 5,
          comment: body.comment || "",
          createdAt: now,
        },
      })
    );

    return ok({ message: "تم تقييم النادي بنجاح" });
  }

  // ─── POST /gyms/:gymId/facilities — create facility ────────────────
  const facilityMatch = path.match(/\/gyms\/([^/]+)\/facilities$/);
  if (facilityMatch && method === "POST") {
    const gymId = facilityMatch[1];
    const body = JSON.parse(event.body || "{}");
    const facilityId = randomBytes(6).toString("hex");
    const now = new Date().toISOString();

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: `FACILITY#${facilityId}`,
          facilityId,
          gymId,
          name: body.name || "",
          description: body.description || null,
          createdAt: now,
        },
      })
    );

    return created({ id: facilityId, message: "تم إضافة المرفق" });
  }

  // ─── POST /gyms/:gymId/products — create product ───────────────────
  const productMatch = path.match(/\/gyms\/([^/]+)\/products$/);
  if (productMatch && method === "POST") {
    const gymId = productMatch[1];
    const body = JSON.parse(event.body || "{}");
    const productId = randomBytes(6).toString("hex");
    const now = new Date().toISOString();

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: `PRODUCT#${productId}`,
          productId,
          gymId,
          title: body.title || "",
          description: body.description || null,
          price: body.price != null ? Number(body.price) : null,
          isActive: body.isActive !== false,
          createdAt: now,
        },
      })
    );

    return created({ id: productId, message: "تم إضافة المنتج" });
  }

  // ─── GET /gyms/:gymId/photos — list gym photos ──────────────────────
  const gymPhotosMatch = path.match(/\/gyms\/([^/]+)\/photos$/);
  if (gymPhotosMatch && method === "GET") {
    const gymId = gymPhotosMatch[1];
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `GYM#${gymId}`, ":sk": "PHOTO#" },
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

  // ─── POST /gyms/:gymId/photos/upload-url — removed (use /photos/presign) ─
  // NOTE: Kept intentionally disabled to avoid duplicate/conflicting presign APIs.

  // ─── POST /gyms/:gymId/photos/presign — get pre-signed S3 upload URL ─
  const gymPhotosPresignMatch = path.match(/\/gyms\/([^/]+)\/photos\/presign$/);
  if (gymPhotosPresignMatch && method === "POST") {
    const gymId = gymPhotosPresignMatch[1];

    const authErr = await assertGymOwnerOrAdmin(docClient, event, gymId);
    if (authErr) return authErr;

    if (!GYM_PHOTOS_BUCKET) {
      return err(500, "GYM_PHOTOS_BUCKET غير مضبوط");
    }

    // Enforce max 5 photos at presign time too (avoid wasted uploads)
    const existingRes = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `GYM#${gymId}`, ":sk": "PHOTO#" },
        Select: "COUNT",
      })
    );
    if ((existingRes.Count || 0) >= 5) {
      return err(400, "وصلت للحد الأقصى للصور (5 صور فقط)");
    }

    const body = JSON.parse(event.body || "{}");
    const contentType = String(body.contentType || "image/jpeg");
    if (!contentType.startsWith("image/")) {
      return err(400, "contentType يجب أن يكون image/*");
    }

    const ext = guessExtFromContentType(contentType);
    const objectKey = `gyms/${gymId}/photos/${randomBytes(16).toString(
      "hex"
    )}.${ext}`;

    const cmd = new PutObjectCommand({
      Bucket: GYM_PHOTOS_BUCKET,
      Key: objectKey,
      ContentType: contentType,
    });

    const uploadUrl = await getSignedUrl(s3, cmd, { expiresIn: 60 });
    const publicUrl = `https://${GYM_PHOTOS_BUCKET}.s3.amazonaws.com/${objectKey}`;

    return ok({ uploadUrl, objectKey, url: publicUrl, expiresIn: 60 });
  }

  // ─── POST /gyms/:gymId/photos — upload gym photo (max 5) ────────────
  if (gymPhotosMatch && method === "POST") {
    const gymId = gymPhotosMatch[1];

    const authErr = await assertGymOwnerOrAdmin(docClient, event, gymId);
    if (authErr) return authErr;

    const body = JSON.parse(event.body || "{}");
    if (!body.url) return err(400, "url مطلوب");

    const objectKey =
      typeof body.objectKey === "string" && body.objectKey.trim().length > 0
        ? body.objectKey.trim()
        : parseS3ObjectKeyFromUrl(String(body.url));

    // Count existing photos
    const existingRes = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `GYM#${gymId}`, ":sk": "PHOTO#" },
        Select: "COUNT",
      })
    );
    if ((existingRes.Count || 0) >= 5) {
      return err(400, "وصلت للحد الأقصى للصور (5 صور فقط)");
    }

    const photoId = randomBytes(6).toString("hex");
    const now = new Date().toISOString();
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: `PHOTO#${photoId}`,
          photoId,
          gymId,
          url: body.url,
          objectKey: objectKey || null,
          uploadedAt: now,
        },
      })
    );
    return created({ photoId, message: "تم رفع الصورة بنجاح" });
  }

  // ─── GET /gyms/:gymId/photos/:photoId/view-url — presigned GET URL ─
  const gymPhotoViewUrlMatch = path.match(
    /\/gyms\/([^/]+)\/photos\/([^/]+)\/view-url$/
  );
  if (gymPhotoViewUrlMatch && method === "GET") {
    const gymId = gymPhotoViewUrlMatch[1];
    const photoId = gymPhotoViewUrlMatch[2];

    // Public viewing is allowed (no auth) since these are gym gallery photos,
    // but the bucket/object can remain private.
    if (!GYM_PHOTOS_BUCKET) return err(500, "GYM_PHOTOS_BUCKET غير مضبوط");

    const photoRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `PHOTO#${photoId}` },
        ProjectionExpression: "#u, objectKey",
        ExpressionAttributeNames: { "#u": "url" },
      })
    );

    if (!photoRes.Item) return err(404, "الصورة غير موجودة");

    const item = photoRes.Item as Record<string, unknown>;
    const objectKey = String(item["objectKey"] || "");
    const storedUrl = String(item["url"] || "");

    const resolvedKey = objectKey || parseS3ObjectKeyFromUrl(storedUrl);
    if (!resolvedKey) {
      // If it isn't in our bucket, fall back to the stored URL.
      return ok({ url: storedUrl, expiresIn: null, presigned: false });
    }

    const viewUrl = await getSignedUrl(
      s3,
      new GetObjectCommand({
        Bucket: GYM_PHOTOS_BUCKET,
        Key: resolvedKey,
      }),
      { expiresIn: 60 * 10 }
    );

    return ok({ url: viewUrl, expiresIn: 60 * 10, presigned: true });
  }

  // ─── DELETE /gyms/:gymId/photos/:photoId — delete gym photo ─────────
  const gymPhotoDeleteMatch = path.match(/\/gyms\/([^/]+)\/photos\/([^/]+)$/);
  if (gymPhotoDeleteMatch && method === "DELETE") {
    const gymId = gymPhotoDeleteMatch[1];
    const photoId = gymPhotoDeleteMatch[2];

    const authErr = await assertGymOwnerOrAdmin(docClient, event, gymId);
    if (authErr) return authErr;

    await docClient.send(
      new DeleteCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `PHOTO#${photoId}` },
      })
    );
    return ok({ message: "تم حذف الصورة" });
  }

  // ─── POST /gyms/:gymId/subscription-requests/presign — presign PUT for payment proof ─
  const subReqPresignMatch = path.match(
    /\/gyms\/([^/]+)\/subscription-requests\/presign$/
  );
  if (subReqPresignMatch && method === "POST") {
    const gymId = subReqPresignMatch[1];

    const authErr = await assertGymOwnerOrAdmin(docClient, event, gymId);
    if (authErr) return authErr;

    if (!SUBSCRIPTION_PROOFS_BUCKET) {
      return err(500, "SUBSCRIPTION_PROOFS_BUCKET غير مضبوط");
    }

    const body = JSON.parse(event.body || "{}");
    const contentType = String(body.contentType || "image/jpeg");
    if (!contentType.startsWith("image/")) {
      return err(400, "contentType يجب أن يكون image/*");
    }

    const ext = guessExtFromContentType(contentType);
    const objectKey = `payments/subscription-proofs/gyms/${gymId}/${randomBytes(
      16
    ).toString("hex")}.${ext}`;

    const cmd = new PutObjectCommand({
      Bucket: SUBSCRIPTION_PROOFS_BUCKET,
      Key: objectKey,
      ContentType: contentType,
    });

    const uploadUrl = await getSignedUrl(s3, cmd, { expiresIn: 60 });
    const url = `https://${SUBSCRIPTION_PROOFS_BUCKET}.s3.amazonaws.com/${objectKey}`;

    return ok({ uploadUrl, objectKey, url, expiresIn: 60 });
  }

  // ─── POST /gyms/:gymId/subscription-requests — owner submits activation request ─
  const subReqCreateMatch = path.match(
    /\/gyms\/([^/]+)\/subscription-requests$/
  );
  if (subReqCreateMatch && method === "POST") {
    const gymId = subReqCreateMatch[1];

    const authErr = await assertGymOwnerOrAdmin(docClient, event, gymId);
    if (authErr) return authErr;

    const body = JSON.parse(event.body || "{}");
    const planId = String(body.planId || "").trim();
    const screenshotUrl = String(body.screenshotUrl || "").trim();
    if (!planId) return err(400, "planId مطلوب");
    if (!screenshotUrl) return err(400, "screenshotUrl مطلوب");

    // Plan must exist and be active
    const planRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: "PLATFORM", SK: `SUBSCRIPTION_PLAN#${planId}` },
      })
    );
    if (!planRes.Item) return err(400, "الخطة غير موجودة");
    const plan = planRes.Item as Record<string, unknown>;
    if (plan["isActive"] === false) return err(400, "الخطة غير متاحة حالياً");

    const durationMonths = Number(plan["durationMonths"] || 1);
    const price = Number(plan["price"] || 0);
    const currency = String(plan["currency"] || "IQD");

    const screenshotObjectKey =
      typeof body.screenshotObjectKey === "string" &&
      body.screenshotObjectKey.trim().length > 0
        ? body.screenshotObjectKey.trim()
        : parseS3ObjectKeyFromUrlForBucket(
            screenshotUrl,
            SUBSCRIPTION_PROOFS_BUCKET
          );

    // Prevent duplicate PENDING request
    const pendingRes = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: {
          ":pk": `GYM#${gymId}`,
          ":sk": "SUBSCRIPTION_REQUEST#",
        },
      })
    );
    const existingPending = (
      (pendingRes.Items || []) as Record<string, unknown>[]
    ).some((i) => String(i["status"] || "").toUpperCase() === "PENDING");
    if (existingPending) {
      return err(409, "لديك طلب اشتراك معلّق بالفعل");
    }

    const requestId = randomBytes(8).toString("hex");
    const now = new Date().toISOString();

    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: `SUBSCRIPTION_REQUEST#${requestId}`,
          requestId,
          gymId,
          ownerId: userId(event),
          ownerName: userName(event),
          status: "PENDING",
          planId,
          durationMonths,
          price,
          currency,
          paymentMethod: "ZAIN_CASH",
          transferToPhone: "07831367435",
          screenshotUrl,
          screenshotObjectKey: screenshotObjectKey || null,
          createdAt: now,
          // GSI1 for admin listing
          GSI1PK: "SUBSCRIPTION_REQUESTS",
          GSI1SK: `PENDING#${now}#${gymId}#${requestId}`,
        },
      })
    );

    // Notify admins (best-effort). Using ownerId 'platform-admin-1' already used elsewhere.
    await pushNotification(docClient, {
      targetUserId: "platform-admin-1",
      eventType: "GYM_SUBSCRIPTION_REQUEST",
      title: "طلب تفعيل اشتراك استوديو",
      message: `${userName(event) || "مالك"} أرسل طلب تفعيل اشتراك`,
      payload: { gymId, requestId, planId },
    }).catch(() => {
      /* silent */
    });

    return created({ requestId, status: "PENDING" });
  }

  // ─── GET /gyms/:gymId/subscription-requests/mine — owner sees their requests ─
  const subReqMineMatch = path.match(
    /\/gyms\/([^/]+)\/subscription-requests\/mine$/
  );
  if (subReqMineMatch && method === "GET") {
    const gymId = subReqMineMatch[1];

    const authErr = await assertGymOwnerOrAdmin(docClient, event, gymId);
    if (authErr) return authErr;

    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: {
          ":pk": `GYM#${gymId}`,
          ":sk": "SUBSCRIPTION_REQUEST#",
        },
      })
    );

    const items = (res.Items || []) as Record<string, unknown>[];
    const requests = items
      .map((r) => ({
        requestId: r["requestId"] || "",
        status: r["status"] || "PENDING",
        planId: r["planId"] || "",
        durationMonths: Number(r["durationMonths"] || 1),
        price: Number(r["price"] || 0),
        currency: r["currency"] || "IQD",
        paymentMethod: r["paymentMethod"] || "ZAIN_CASH",
        transferToPhone: r["transferToPhone"] || "07831367435",
        screenshotUrl: r["screenshotUrl"] || "",
        createdAt: r["createdAt"] || "",
        reviewedAt: r["reviewedAt"] || null,
        note: r["note"] || null,
      }))
      .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));

    return ok({ requests });
  }

  // ─── GET /gyms/:gymId/my-membership — current user's membership ────
  const myMembershipMatch = path.match(/\/gyms\/([^/]+)\/my-membership$/);
  if (myMembershipMatch && method === "GET") {
    const gymId = myMembershipMatch[1];
    const uid = userId(event);

    const res = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${uid}` },
      })
    );

    if (!res.Item) {
      return ok({ membership: null });
    }

    const m = res.Item as Record<string, unknown>;
    return ok({
      membership: {
        userId: m["userId"] || "",
        userName: m["userName"] || "",
        gymId: m["gymId"] || gymId,
        status: m["status"] || "PENDING",
        joinedAt: m["joinedAt"] || "",
        selectedPlanId: m["selectedPlanId"] || null,
        selectedPlanTitle: m["selectedPlanTitle"] || null,
        selectedPlanDurationMonths: m["selectedPlanDurationMonths"] || null,
        subscriptionStartsAt: m["subscriptionStartsAt"] || null,
        subscriptionExpiresAt: m["subscriptionExpiresAt"] || null,
        nextPlanId: m["nextPlanId"] || null,
        nextPlanTitle: m["nextPlanTitle"] || null,
        nextPlanDurationMonths: m["nextPlanDurationMonths"] || null,
        nextPlanStartsAt: m["nextPlanStartsAt"] || null,
        nextPlanExpiresAt: m["nextPlanExpiresAt"] || null,
      },
    });
  }

  // ─── DELETE /gyms/:gymId/my-subscription — cancel subscription ─────
  // Cancels a plan whose start date has NOT yet arrived:
  //   • If nextPlan exists and hasn't started → clear nextPlan fields
  //   • If current plan hasn't started yet (PENDING) → delete membership
  //   • Otherwise → 400 (plan already started, cannot cancel)
  if (myMembershipMatch && method === "DELETE") {
    const gymId = myMembershipMatch[1];
    const uid = userId(event);
    const now = new Date();
    const nowIso = now.toISOString();
    const body = JSON.parse(event.body || "{}");
    const target = (body.target || "").toUpperCase(); // 'NEXT' | 'CURRENT' | ''

    const res = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${uid}` },
      })
    );

    if (!res.Item) {
      return err(404, "لست عضواً في هذا النادي");
    }

    const m = res.Item as Record<string, unknown>;
    const status = String(m["status"] || "").toUpperCase();
    const nextPlanId = m["nextPlanId"] as string | undefined;
    const nextPlanStartsAt = m["nextPlanStartsAt"] as string | undefined;
    const subscriptionStartsAt = m["subscriptionStartsAt"] as
      | string
      | undefined;

    // ── Cancel queued next plan ──────────────────────────────────────
    if (target === "NEXT" || (!target && nextPlanId)) {
      if (!nextPlanId) {
        return err(400, "لا توجد خطة تالية لإلغائها");
      }
      // Check if the next plan has already started
      if (nextPlanStartsAt && new Date(nextPlanStartsAt) <= now) {
        return err(400, "لا يمكن إلغاء الخطة التالية — بدأت بالفعل");
      }

      await docClient.send(
        new UpdateCommand({
          TableName: TABLE,
          Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${uid}` },
          UpdateExpression:
            "SET nextPlanId = :null, nextPlanTitle = :null, nextPlanDurationMonths = :null, nextPlanStartsAt = :null, nextPlanExpiresAt = :null, updatedAt = :now",
          ExpressionAttributeValues: { ":null": null, ":now": nowIso },
        })
      );

      return ok({ message: "تم إلغاء الخطة التالية بنجاح", cancelled: "NEXT" });
    }

    // ── Cancel current plan (only if PENDING or not yet started) ─────
    if (target === "CURRENT" || !target) {
      // PENDING membership — haven't been approved yet → delete entirely
      if (status === "PENDING") {
        await docClient.send(
          new DeleteCommand({
            TableName: TABLE,
            Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${uid}` },
          })
        );
        return ok({ message: "تم إلغاء طلب الانضمام", cancelled: "PENDING" });
      }

      // ACTIVE — only cancel if the current plan hasn't started yet
      if (status === "ACTIVE") {
        if (subscriptionStartsAt && new Date(subscriptionStartsAt) <= now) {
          return err(
            400,
            "لا يمكن إلغاء الاشتراك — الخطة الحالية بدأت بالفعل. يمكنك إلغاء الخطة التالية فقط."
          );
        }

        // Plan not started → clear plan fields (keep membership ACTIVE with no plan)
        await docClient.send(
          new UpdateCommand({
            TableName: TABLE,
            Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${uid}` },
            UpdateExpression:
              "SET selectedPlanId = :null, selectedPlanTitle = :null, selectedPlanDurationMonths = :null, subscriptionStartsAt = :null, subscriptionExpiresAt = :null, nextPlanId = :null, nextPlanTitle = :null, nextPlanDurationMonths = :null, nextPlanStartsAt = :null, nextPlanExpiresAt = :null, updatedAt = :now",
            ExpressionAttributeValues: { ":null": null, ":now": nowIso },
          })
        );

        return ok({ message: "تم إلغاء الاشتراك بنجاح", cancelled: "CURRENT" });
      }

      return err(400, "لا يمكن إلغاء الاشتراك في الحالة الحالية");
    }

    return err(400, "يرجى تحديد target: NEXT أو CURRENT");
  }

  return err(404, "المسار غير موجود");
}
