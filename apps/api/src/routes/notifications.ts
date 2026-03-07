import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';
import {
  DynamoDBDocumentClient,
  DeleteCommand,
  PutCommand,
  QueryCommand,
  UpdateCommand,
} from '@aws-sdk/lib-dynamodb';
import { randomBytes } from 'crypto';

const TABLE = process.env.DYNAMODB_TABLE_NAME || 'wizgym-prod-core';

function ok(body: unknown): APIGatewayProxyResultV2 {
  return { statusCode: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}
function created(body: unknown): APIGatewayProxyResultV2 {
  return { statusCode: 201, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}
function err(status: number, msg: string): APIGatewayProxyResultV2 {
  return { statusCode: status, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ message: msg }) };
}
function userId(event: APIGatewayProxyEventV2): string {
  return event.headers?.['x-user-id'] || event.headers?.['X-User-Id'] || 'anon';
}

/**
 * Notifications are stored as:
 *   PK = USER#<userId>
 *   SK = NOTIFICATION#<timestamp>#<notifId>   (sorted newest-first via reverse-timestamp trick)
 *
 * GSI3 is used for admin broadcasts:
 *   GSI3PK = BROADCAST
 *   GSI3SK = NOTIFICATION#<timestamp>#<notifId>
 */
export async function handleNotifications(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient,
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || '';
  const method = event.requestContext.http.method;

  // ─── GET /notifications — fetch user's notifications (max 50) ───
  if (path.endsWith('/notifications') && method === 'GET') {
    const uid = userId(event);
    if (!uid || uid === 'anon') return ok([]);

    const params = event.queryStringParameters || {};
    const limit = Math.min(Number(params['limit']) || 50, 100);
    const sinceParam = params['since']; // ISO timestamp to paginate

    // Fetch user-specific notifications
    const userRes = await docClient.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: sinceParam
        ? 'PK = :pk AND SK > :since'
        : 'PK = :pk AND begins_with(SK, :sk)',
      ExpressionAttributeValues: sinceParam
        ? { ':pk': `USER#${uid}`, ':since': `NOTIFICATION#${sinceParam}` }
        : { ':pk': `USER#${uid}`, ':sk': 'NOTIFICATION#' },
      ScanIndexForward: false, // newest first
      Limit: limit,
    }));

    // Fetch admin broadcasts (global) — stored with PK=BROADCAST, queried directly
    const broadcastRes = await docClient.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: 'PK = :bpk AND begins_with(SK, :sk)',
      ExpressionAttributeValues: { ':bpk': 'BROADCAST', ':sk': 'NOTIFICATION#' },
      ScanIndexForward: false,
      Limit: 10,
    }));

    const userNotifs = (userRes.Items || []) as Record<string, unknown>[];
    const broadcasts = (broadcastRes.Items || []) as Record<string, unknown>[];

    // Merge and sort by createdAt descending
    const all = [...userNotifs, ...broadcasts].map(notifFromItem);
    all.sort((a, b) => b.createdAt.localeCompare(a.createdAt));

    // Deduplicate by id
    const seen = new Set<string>();
    const deduped = all.filter(n => {
      if (seen.has(n.id)) return false;
      seen.add(n.id);
      return true;
    });

    return ok(deduped.slice(0, limit));
  }

  // ─── POST /notifications — create a notification (internal/admin use) ───
  if (path.endsWith('/notifications') && method === 'POST') {
    const body = JSON.parse(event.body || '{}');
    const targetUserId = body.targetUserId as string | undefined;
    const isBroadcast = body.broadcast === true;

    if (!targetUserId && !isBroadcast) {
      return err(400, 'targetUserId أو broadcast مطلوب');
    }

    const notifId = randomBytes(8).toString('hex');
    const now = new Date().toISOString();
    // Reverse-timestamp for newest-first ordering
    const reverseTs = String(9999999999999 - Date.now());

    const item: Record<string, unknown> = {
      notifId,
      eventType: body.eventType || 'generic',
      title: body.title || '',
      message: body.message || body.body || '',
      createdAt: now,
      isRead: false,
      payload: body.payload || null,
    };

    if (isBroadcast) {
      // Broadcast notification — visible to all users, queried by PK=BROADCAST
      await docClient.send(new PutCommand({
        TableName: TABLE,
        Item: {
          PK: 'BROADCAST',
          SK: `NOTIFICATION#${reverseTs}#${notifId}`,
          ...item,
        },
      }));
    } else {
      // User-specific notification
      await docClient.send(new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `USER#${targetUserId}`,
          SK: `NOTIFICATION#${reverseTs}#${notifId}`,
          ...item,
          targetUserId,
        },
      }));
    }

    return created({ id: notifId, message: 'تم إرسال الإشعار' });
  }

  // ─── PATCH /notifications/:notifId/read — mark as read ───
  const readMatch = path.match(/\/notifications\/([^/]+)\/read$/);
  if (readMatch && method === 'PATCH') {
    const notifId = readMatch[1];
    const uid = userId(event);

    // We need to find the full SK — query the user's notifications for the matching notifId
    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
      FilterExpression: 'notifId = :nid',
      ExpressionAttributeValues: { ':pk': `USER#${uid}`, ':sk': 'NOTIFICATION#', ':nid': notifId },
      Limit: 1,
    }));

    if (res.Items && res.Items.length > 0) {
      const sk = res.Items[0]['SK'] as string;
      await docClient.send(new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `USER#${uid}`, SK: sk },
        UpdateExpression: 'SET isRead = :r',
        ExpressionAttributeValues: { ':r': true },
      }));
    }

    return ok({ message: 'تم' });
  }

  // ─── POST /notifications/mark-all-read ───
  if (path.endsWith('/notifications/mark-all-read') && method === 'POST') {
    const uid = userId(event);
    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
      FilterExpression: 'isRead = :f',
      ExpressionAttributeValues: { ':pk': `USER#${uid}`, ':sk': 'NOTIFICATION#', ':f': false },
    }));

    const items = (res.Items || []) as Record<string, unknown>[];
    // Update all in parallel (max 25 at a time for safety)
    const batches = chunk(items, 25);
    for (const batch of batches) {
      await Promise.all(batch.map(item =>
        docClient.send(new UpdateCommand({
          TableName: TABLE,
          Key: { PK: `USER#${uid}`, SK: item['SK'] as string },
          UpdateExpression: 'SET isRead = :r',
          ExpressionAttributeValues: { ':r': true },
        })),
      ));
    }

    return ok({ message: 'تم تحديث جميع الإشعارات', count: items.length });
  }

  // ─── DELETE /notifications/:notifId — delete a notification ───
  const deleteMatch = path.match(/\/notifications\/([^/]+)$/);
  if (deleteMatch && method === 'DELETE') {
    const notifId = deleteMatch[1];
    const uid = userId(event);

    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
      FilterExpression: 'notifId = :nid',
      ExpressionAttributeValues: { ':pk': `USER#${uid}`, ':sk': 'NOTIFICATION#', ':nid': notifId },
      Limit: 1,
    }));

    if (res.Items && res.Items.length > 0) {
      await docClient.send(new DeleteCommand({
        TableName: TABLE,
        Key: { PK: `USER#${uid}`, SK: res.Items[0]['SK'] as string },
      }));
    }

    return ok({ message: 'تم حذف الإشعار' });
  }

  return err(404, 'المسار غير موجود');
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function notifFromItem(item: Record<string, unknown>) {
  return {
    id: (item['notifId'] || '').toString(),
    eventType: (item['eventType'] || 'generic').toString(),
    type: (item['eventType'] || 'generic').toString(),
    title: (item['title'] || '').toString(),
    message: (item['message'] || '').toString(),
    body: (item['message'] || '').toString(),
    createdAt: (item['createdAt'] || '').toString(),
    isRead: item['isRead'] === true,
    payload: item['payload'] || null,
  };
}

function chunk<T>(arr: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    result.push(arr.slice(i, i + size));
  }
  return result;
}

/**
 * Helper to create a notification item for another user.
 * Call this from other routes (e.g., when a member joins, trainer subscribes, etc.)
 */
export async function pushNotification(
  docClient: DynamoDBDocumentClient,
  params: {
    targetUserId: string;
    eventType: string;
    title: string;
    message: string;
    payload?: Record<string, unknown>;
  },
): Promise<void> {
  const notifId = randomBytes(8).toString('hex');
  const now = new Date().toISOString();
  const reverseTs = String(9999999999999 - Date.now());

  await docClient.send(new PutCommand({
    TableName: TABLE,
    Item: {
      PK: `USER#${params.targetUserId}`,
      SK: `NOTIFICATION#${reverseTs}#${notifId}`,
      notifId,
      targetUserId: params.targetUserId,
      eventType: params.eventType,
      title: params.title,
      message: params.message,
      createdAt: now,
      isRead: false,
      payload: params.payload || null,
    },
  }));
}
