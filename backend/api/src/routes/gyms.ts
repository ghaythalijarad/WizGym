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

const TABLE = process.env.DYNAMODB_TABLE_NAME || "wizgym-prod-core";

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
  };
}

export async function handleGyms(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || "";
  const method = event.requestContext.http.method;
  const params = event.queryStringParameters || {};

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

    return ok(items.map((i) => {
      const gId = String(i["gymId"] || i["PK"] || "").replace("GYM#", "");
      return { ...gymSummaryFromItem(i), subscriptionActive: subMap[gId] === true };
    }));
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
          ownerId: uid,
          ownerName: userName(event),
          status: "ACTIVE",
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

    // Fetch subscription plans, facilities, products in parallel
    const [plansRes, facRes, prodRes] = await Promise.all([
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

    return ok({
      id: gymId,
      name: profile["name"] || "",
      city: profile["city"] || "",
      description: profile["description"] || null,
      coverImageUrl: profile["coverImageUrl"] || null,
      audience: profile["audience"] || "MIXED",
      amenities: (profile["amenities"] as string[]) || [],
      ownerName: profile["ownerName"] || "",
      averageRating: Number(profile["averageRating"] || 0),
      facilities,
      products,
      subscriptionPlans: plans,
    });
  }

  // ─── PATCH /gyms/:gymId/profile — update gym profile ──────────────
  const profilePatch = path.match(/\/gyms\/([^/]+)\/profile$/);
  if (profilePatch && method === "PATCH") {
    const gymId = profilePatch[1];
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
