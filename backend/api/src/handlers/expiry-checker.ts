/**
 * expiry-checker.ts
 * EventBridge-scheduled Lambda — runs nightly at 01:00 UTC.
 * Scans all GYM SUBSCRIPTION items whose status is ACTIVE but whose
 * expiresAt has passed, and flips them to INACTIVE.
 */
import {
  DynamoDBClient,
  ScanCommand,
  UpdateItemCommand,
  type AttributeValue,
} from "@aws-sdk/client-dynamodb";
import { marshall } from "@aws-sdk/util-dynamodb";

const TABLE = process.env.DYNAMODB_TABLE_NAME || "wizgym-prod-core";
const client = new DynamoDBClient({ region: process.env.AWS_REGION || "us-east-1" });

export async function handler(): Promise<void> {
  const now = new Date().toISOString();
  console.log(`[ExpiryChecker] Starting scan at ${now}`);

  let expired = 0;
  let lastKey: Record<string, AttributeValue> | undefined;

  do {
    const res = await client.send(new ScanCommand({
      TableName: TABLE,
      FilterExpression: "begins_with(PK, :g) AND SK = :s AND #st = :active AND expiresAt < :now",
      ExpressionAttributeNames: { "#st": "status" },
      ExpressionAttributeValues: marshall({
        ":g": "GYM#",
        ":s": "SUBSCRIPTION",
        ":active": "ACTIVE",
        ":now": now,
      }),
      ExclusiveStartKey: lastKey,
    }));

    const items = res.Items || [];
    console.log(`[ExpiryChecker] Found ${items.length} expired subscription(s) in this page`);

    for (const item of items) {
      const pk = item["PK"]?.S;
      if (!pk) continue;

      try {
        await client.send(new UpdateItemCommand({
          TableName: TABLE,
          Key: marshall({ PK: pk, SK: "SUBSCRIPTION" }),
          UpdateExpression: "SET #st = :inactive, updatedAt = :ts, expiredAt = :ts",
          ConditionExpression: "#st = :active",
          ExpressionAttributeNames: { "#st": "status" },
          ExpressionAttributeValues: marshall({
            ":inactive": "INACTIVE",
            ":active": "ACTIVE",
            ":ts": now,
          }),
        }));
        console.log(`[ExpiryChecker] Deactivated ${pk}`);
        expired++;
      } catch (err: unknown) {
        // ConditionalCheckFailedException = already updated by another process, safe to ignore
        if (err instanceof Error && err.name === "ConditionalCheckFailedException") {
          console.log(`[ExpiryChecker] Skipped ${pk} (already updated)`);
        } else {
          console.error(`[ExpiryChecker] Failed to update ${pk}:`, err);
        }
      }
    }

    lastKey = res.LastEvaluatedKey as Record<string, AttributeValue> | undefined;
  } while (lastKey);

  console.log(`[ExpiryChecker] Done. Total deactivated: ${expired}`);
}
