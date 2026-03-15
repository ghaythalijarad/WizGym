import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import {
  DeleteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";
import { randomBytes } from "crypto";

const TABLE = process.env.DYNAMODB_TABLE_NAME || "wizgym-prod-core";
// Reuse the trainer certs bucket for avatar storage (avatars/ prefix)
const AVATARS_BUCKET = process.env.TRAINER_CERTS_BUCKET || "";
const s3 = new S3Client({});

function guessExtFromContentType(ct: string): string {
  const c = ct.toLowerCase();
  if (c.includes("jpeg")) return "jpg";
  if (c.includes("png")) return "png";
  if (c.includes("webp")) return "webp";
  if (c.includes("heic")) return "heic";
  return "jpg";
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

function getUserId(event: APIGatewayProxyEventV2): string {
  return event.headers?.["x-user-id"] || event.headers?.["X-User-Id"] || "";
}

function getUserRole(event: APIGatewayProxyEventV2): string {
  return (
    event.headers?.["x-user-role"] || event.headers?.["X-User-Role"] || "USER"
  );
}

function getUserName(event: APIGatewayProxyEventV2): string {
  const raw =
    event.headers?.["x-user-name"] || event.headers?.["X-User-Name"] || "";
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

export async function handleUsers(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || "";
  const method = event.requestContext.http.method;

  // GET /users/me - Get current user profile
  if (path.endsWith("/users/me") && method === "GET") {
    const userId = getUserId(event);
    const role = getUserRole(event);
    const displayName = getUserName(event);

    if (userId && userId !== "anon" && !userId.startsWith("demo")) {
      try {
        const result = await docClient.send(
          new GetCommand({
            TableName: TABLE,
            Key: {
              PK: userId.startsWith("USER#") ? userId : `USER#${userId}`,
              SK: "PROFILE",
            },
          })
        );

        if (result.Item) {
          const avatarObjectKey = String(result.Item.avatarObjectKey || "");
          const avatarViewUrl = avatarObjectKey
            ? await presignAvatarViewUrl(avatarObjectKey)
            : (result.Item.avatarUrl as string | null) || null;

          return ok({
            id: result.Item.id || userId,
            phoneNumber: result.Item.phoneNumber || "",
            displayName: result.Item.displayName || displayName,
            role: result.Item.role || role,
            bio: result.Item.bio || null,
            avatarUrl: avatarViewUrl,
            avatarObjectKey: avatarObjectKey || null,
            createdAt: result.Item.createdAt,
            lastLoginAt: result.Item.lastLoginAt || result.Item.updatedAt,
          });
        }
      } catch (e) {
        console.error("Error fetching user profile:", e);
      }
    }

    // Return profile from headers (demo/fallback mode)
    return ok({
      id: userId || "demo-user",
      phoneNumber: "",
      displayName: displayName || role,
      role: role,
      bio: null,
      avatarUrl: null,
      createdAt: new Date().toISOString(),
      lastLoginAt: new Date().toISOString(),
    });
  }

  // PATCH /users/me/profile — update bio and/or displayName
  if (path.endsWith("/users/me/profile") && method === "PATCH") {
    const userId = getUserId(event);
    if (!userId || userId === "anon") return err(401, "غير مصرح");

    const body = JSON.parse(event.body || "{}");
    const setParts: string[] = ["updatedAt = :now"];
    const exprValues: Record<string, unknown> = {
      ":now": new Date().toISOString(),
    };
    const exprNames: Record<string, string> = {};

    if (typeof body.bio === "string") {
      setParts.push("#bio = :bio");
      exprNames["#bio"] = "bio";
      exprValues[":bio"] = body.bio.trim().slice(0, 500);
    }
    if (typeof body.displayName === "string" && body.displayName.trim()) {
      setParts.push("#dn = :dn");
      exprNames["#dn"] = "displayName";
      exprValues[":dn"] = body.displayName.trim().slice(0, 100);
    }

    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: {
          PK: userId.startsWith("USER#") ? userId : `USER#${userId}`,
          SK: "PROFILE",
        },
        UpdateExpression: `SET ${setParts.join(", ")}`,
        ...(Object.keys(exprNames).length > 0
          ? { ExpressionAttributeNames: exprNames }
          : {}),
        ExpressionAttributeValues: exprValues,
      })
    );
    return ok({ message: "تم تحديث الملف الشخصي" });
  }

  // POST /users/me/avatar/presign — get a presigned PUT URL to upload avatar
  if (path.endsWith("/users/me/avatar/presign") && method === "POST") {
    const userId = getUserId(event);
    if (!userId || userId === "anon") return err(401, "غير مصرح");
    if (!AVATARS_BUCKET) return err(500, "AVATARS_BUCKET غير مضبوط");

    const body = JSON.parse(event.body || "{}");
    const contentType = String(body.contentType || "image/jpeg");
    if (!contentType.startsWith("image/"))
      return err(400, "contentType يجب أن يكون image/*");

    const ext = guessExtFromContentType(contentType);
    const objectKey = `avatars/${userId.replace(/[^a-zA-Z0-9_-]/g, "_")}/${randomBytes(8).toString("hex")}.${ext}`;

    const uploadUrl = await getSignedUrl(
      s3,
      new PutObjectCommand({
        Bucket: AVATARS_BUCKET,
        Key: objectKey,
        ContentType: contentType,
      }),
      { expiresIn: 60 }
    );

    return ok({ uploadUrl, objectKey, expiresIn: 60 });
  }

  // PATCH /users/me/avatar — confirm avatar after upload (save objectKey)
  if (path.endsWith("/users/me/avatar") && method === "PATCH") {
    const userId = getUserId(event);
    if (!userId || userId === "anon") return err(401, "غير مصرح");
    const body = JSON.parse(event.body || "{}");
    if (!body.objectKey) return err(400, "objectKey مطلوب");

    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: {
          PK: userId.startsWith("USER#") ? userId : `USER#${userId}`,
          SK: "PROFILE",
        },
        UpdateExpression: "SET avatarObjectKey = :key, updatedAt = :now",
        ExpressionAttributeValues: {
          ":key": body.objectKey,
          ":now": new Date().toISOString(),
        },
      })
    );

    // Return presigned view URL immediately
    const viewUrl = await presignAvatarViewUrl(body.objectKey);
    return ok({ message: "تم تحديث الصورة الشخصية", avatarUrl: viewUrl });
  }

  // DELETE /users/me - Delete current user account
  if (path.endsWith("/users/me") && method === "DELETE") {
    const userId = getUserId(event);

    if (!userId || userId === "anon" || userId.startsWith("demo")) {
      return err(400, "لا يمكن حذف حساب تجريبي");
    }

    try {
      await docClient.send(
        new DeleteCommand({
          TableName: TABLE,
          Key: {
            PK: userId.startsWith("USER#") ? userId : `USER#${userId}`,
            SK: "PROFILE",
          },
        })
      );

      return ok({ message: "تم حذف الحساب بنجاح" });
    } catch (e) {
      console.error("Error deleting user:", e);
      return err(500, "فشل في حذف الحساب");
    }
  }

  // PATCH /users/me/avatar — set or update profile photo (one only)
  if (path.endsWith("/users/me/avatar") && method === "PATCH") {
    const userId = getUserId(event);
    if (!userId || userId === "anon") return err(401, "غير مصرح");
    const body = JSON.parse(event.body || "{}");
    if (!body.avatarUrl) return err(400, "avatarUrl مطلوب");

    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: {
          PK: userId.startsWith("USER#") ? userId : `USER#${userId}`,
          SK: "PROFILE",
        },
        UpdateExpression: "SET avatarUrl = :url, updatedAt = :now",
        ExpressionAttributeValues: {
          ":url": body.avatarUrl,
          ":now": new Date().toISOString(),
        },
      })
    );
    return ok({
      message: "تم تحديث الصورة الشخصية",
      avatarUrl: body.avatarUrl,
    });
  }

  // DELETE /users/me/avatar — remove profile photo
  if (path.endsWith("/users/me/avatar") && method === "DELETE") {
    const userId = getUserId(event);
    if (!userId || userId === "anon") return err(401, "غير مصرح");

    await docClient.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: {
          PK: userId.startsWith("USER#") ? userId : `USER#${userId}`,
          SK: "PROFILE",
        },
        UpdateExpression: "REMOVE avatarObjectKey SET updatedAt = :now",
        ExpressionAttributeValues: { ":now": new Date().toISOString() },
      })
    );
    return ok({ message: "تم حذف الصورة الشخصية" });
  }

  return err(404, "المسار غير موجود");
}
