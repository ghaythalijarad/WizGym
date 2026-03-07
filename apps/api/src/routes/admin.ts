import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';
import { DynamoDBDocumentClient, QueryCommand, ScanCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';

const TABLE = process.env.DYNAMODB_TABLE_NAME || 'wizgym-prod-core';

function ok(body: unknown): APIGatewayProxyResultV2 {
  return { statusCode: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}
function notFound(): APIGatewayProxyResultV2 {
  return { statusCode: 404, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ message: 'المسار غير موجود' }) };
}

function gymFromItem(i: Record<string, unknown>) {
  return {
    id: String(i['gymId'] || i['PK'] || '').replace('GYM#', ''),
    gymName: i['name'] || '', name: i['name'] || '', city: i['city'] || '', audience: i['audience'] || 'MIXED',
    status: i['status'] || 'ACTIVE', membersCount: Number(i['membersCount'] || 0),
    trainersCount: Number(i['trainersCount'] || 0), averageRating: Number(i['averageRating'] || 0),
    ownerName: i['ownerName'] || '', amenities: (i['amenities'] as string[]) || [],
    description: i['description'] || null, coverImageUrl: i['coverImageUrl'] || null,
    requestedAt: i['createdAt'] || i['updatedAt'] || '',
    reviewNote: i['reviewNote'] || null,
  };
}

export async function handleAdmin(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient,
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || '';
  const method = event.requestContext.http.method;

  // GET /admin/dashboard
  if (path.endsWith('/admin/dashboard') && method === 'GET') {
    const [g, u, pending] = await Promise.all([
      docClient.send(new ScanCommand({ TableName: TABLE, FilterExpression: 'begins_with(PK, :g) AND SK = :p', ExpressionAttributeValues: { ':g': 'GYM#', ':p': 'PROFILE' }, Select: 'COUNT' })),
      docClient.send(new ScanCommand({ TableName: TABLE, FilterExpression: 'begins_with(PK, :u) AND SK = :p', ExpressionAttributeValues: { ':u': 'USER#', ':p': 'PROFILE' }, Select: 'COUNT' })),
      docClient.send(new ScanCommand({ TableName: TABLE, FilterExpression: 'begins_with(PK, :g) AND SK = :p AND #s = :pending', ExpressionAttributeNames: { '#s': 'status' }, ExpressionAttributeValues: { ':g': 'GYM#', ':p': 'PROFILE', ':pending': 'PENDING_APPROVAL' }, Select: 'COUNT' })),
    ]);
    return ok({ totalGyms: g.Count || 0, totalUsers: u.Count || 0, pendingApprovals: pending.Count || 0, activeSubscriptions: 0 });
  }

  // GET /admin/gyms
  if (path.endsWith('/admin/gyms') && method === 'GET') {
    const res = await docClient.send(new ScanCommand({ TableName: TABLE, FilterExpression: 'begins_with(PK, :g) AND SK = :p', ExpressionAttributeValues: { ':g': 'GYM#', ':p': 'PROFILE' } }));
    return ok(((res.Items || []) as Record<string, unknown>[]).map(gymFromItem));
  }

  // POST /admin/gyms/:id/approve
  const approve = path.match(/\/admin\/gyms\/([^/]+)\/approve$/);
  if (approve && method === 'POST') {
    await docClient.send(new UpdateCommand({ TableName: TABLE, Key: { PK: `GYM#${approve[1]}`, SK: 'PROFILE' }, UpdateExpression: 'SET #s = :s, updatedAt = :u', ExpressionAttributeNames: { '#s': 'status' }, ExpressionAttributeValues: { ':s': 'ACTIVE', ':u': new Date().toISOString() } }));
    return ok({ message: 'تم اعتماد النادي بنجاح' });
  }

  // POST /admin/gyms/:id/reject
  const reject = path.match(/\/admin\/gyms\/([^/]+)\/reject$/);
  if (reject && method === 'POST') {
    await docClient.send(new UpdateCommand({ TableName: TABLE, Key: { PK: `GYM#${reject[1]}`, SK: 'PROFILE' }, UpdateExpression: 'SET #s = :s, updatedAt = :u', ExpressionAttributeNames: { '#s': 'status' }, ExpressionAttributeValues: { ':s': 'REJECTED', ':u': new Date().toISOString() } }));
    return ok({ message: 'تم رفض النادي' });
  }

  // GET /admin/subscriptions
  if (path.endsWith('/admin/subscriptions') && method === 'GET') {
    const res = await docClient.send(new ScanCommand({ TableName: TABLE, FilterExpression: 'begins_with(SK, :sk)', ExpressionAttributeValues: { ':sk': 'SUBSCRIPTION#' } }));
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(items.map(i => ({ id: i['subscriptionId'] || i['SK'], gymId: i['gymId'] || '', gymName: i['gymName'] || '', userId: i['userId'] || '', userName: i['userName'] || '', status: i['status'] || 'ACTIVE', startDate: i['startDate'] || '', endDate: i['endDate'] || '' })));
  }

  // PATCH /admin/subscriptions/:id/status
  const subStatus = path.match(/\/admin\/subscriptions\/([^/]+)\/status$/);
  if (subStatus && method === 'PATCH') {
    const body = JSON.parse(event.body || '{}');
    return ok({ message: 'تم تحديث حالة الاشتراك', status: body.status });
  }

  return notFound();
}
