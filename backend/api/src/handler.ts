import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyResultV2,
} from "aws-lambda";
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

function notFound(path: string): APIGatewayProxyResultV2 {
  return {
    statusCode: 404,
    headers: CORS_HEADERS,
    body: JSON.stringify({ message: "Not Found", path }),
  };
}

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
