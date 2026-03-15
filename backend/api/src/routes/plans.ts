import {
  DeleteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";
import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";
import { randomBytes } from "crypto";

const TABLE = process.env.DYNAMODB_TABLE_NAME || "wizgym-prod-core";

function ok(body: unknown): APIGatewayProxyResultV2 {
  return {
    statusCode: 200,
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

export async function handlePlans(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || "";
  const method = event.requestContext.http.method;

  // GET /plans/me — fetch my plans (trainee or trainer)
  if (path.endsWith("/plans/me") && method === "GET") {
    const uid = userId(event);
    const res = await docClient.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk AND begins_with(SK, :sk)",
        ExpressionAttributeValues: { ":pk": `USER#${uid}`, ":sk": "PLAN#" },
      })
    );
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({
      plans: items.map((i) => ({
        id: i["planId"] || i["SK"],
        type: i["type"] || "SELF",
        content: i["content"] || "",
        createdByRole: i["createdByRole"] || "USER",
        createdByName: i["createdByName"] || "",
        traineeName: i["traineeName"] || "",
        trainerName: i["trainerName"] || null,
        createdAt: i["createdAt"] || "",
      })),
    });
  }

  // POST /plans/me — trainee creates own plan
  if (path.endsWith("/plans/me") && method === "POST") {
    const uid = userId(event);
    const body = JSON.parse(event.body || "{}");
    const planId = randomBytes(8).toString("hex");
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `USER#${uid}`,
          SK: `PLAN#${planId}`,
          planId,
          userId: uid,
          type: "SELF",
          content: body.content || "",
          createdByRole: "USER",
          createdByName: "",
          traineeName: "",
          createdAt: new Date().toISOString(),
        },
      })
    );
    return ok({ id: planId, message: "تم إنشاء الخطة بنجاح" });
  }

  // POST /plans/trainer/send — trainer sends plan to trainee
  if (path.endsWith("/plans/trainer/send") && method === "POST") {
    const uid = userId(event);
    const body = JSON.parse(event.body || "{}");
    const { traineeUserId, content } = body;
    if (!traineeUserId || !content) {
      return err(400, "traineeUserId و content مطلوبان");
    }

    // ── Check that the trainee has an APPROVED subscription with this trainer ──
    const subscriptionRes = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `TRAINER#${uid}`, SK: `CLIENT#${traineeUserId}` },
      })
    );
    const subscription = subscriptionRes.Item as
      | Record<string, unknown>
      | undefined;
    if (!subscription || subscription["status"] !== "APPROVED") {
      return err(
        403,
        "لا يمكن إرسال الخطة — لا يوجد اشتراك فعال بينك وبين هذا المتدرب"
      );
    }

    const planId = randomBytes(8).toString("hex");
    await docClient.send(
      new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `USER#${traineeUserId}`,
          SK: `PLAN#${planId}`,
          planId,
          userId: traineeUserId,
          type: "TRAINER_TO_TRAINEE",
          content,
          createdByRole: "TRAINER",
          createdByName: "",
          traineeName: "",
          trainerName: "",
          trainerId: uid,
          createdAt: new Date().toISOString(),
        },
      })
    );
    return ok({ id: planId, message: "تم إرسال الخطة بنجاح" });
  }

  // DELETE /plans/me/{planId} — trainee deletes own plan
  if (path.includes("/plans/me/") && method === "DELETE") {
    const uid = userId(event);
    const planId = decodeURIComponent(path.split("/plans/me/")[1] || "").trim();
    if (!planId) return err(400, "planId مطلوب");

    const sk = planId.startsWith("PLAN#") ? planId : `PLAN#${planId}`;

    // Ensure it exists under this user (avoid deleting other users' plans)
    const existing = await docClient.send(
      new GetCommand({
        TableName: TABLE,
        Key: { PK: `USER#${uid}`, SK: sk },
      })
    );
    if (!existing.Item) return err(404, "الخطة غير موجودة");

    await docClient.send(
      new DeleteCommand({
        TableName: TABLE,
        Key: { PK: `USER#${uid}`, SK: sk },
      })
    );

    return ok({ message: "تم حذف الخطة" });
  }

  return err(404, "المسار غير موجود");
}
