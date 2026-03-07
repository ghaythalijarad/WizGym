// filepath: /Users/ghaythallaheebi/WizGymProd/apps/api/src/routes/trainers.ts
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  ScanCommand,
  UpdateCommand,
} from '@aws-sdk/lib-dynamodb';
import { randomBytes } from 'crypto';
import { pushNotification } from './notifications';

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
function userName(event: APIGatewayProxyEventV2): string {
  return event.headers?.['x-user-name'] || event.headers?.['X-User-Name'] || '';
}

export async function handleTrainers(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient,
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || '';
  const method = event.requestContext.http.method;

  // GET /trainers/me/gyms
  if (path.endsWith('/trainers/me/gyms') && method === 'GET') {
    const uid = userId(event);
    const res = await docClient.send(new ScanCommand({
      TableName: TABLE,
      FilterExpression: 'begins_with(SK, :sk) AND trainerId = :tid',
      ExpressionAttributeValues: { ':sk': 'TRAINER#', ':tid': uid },
    }));
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(items.map(i => ({
      gymId: i['gymId'] || '',
      gymName: i['gymName'] || '',
      city: i['city'] || '',
      activeClients: Number(i['activeClients'] || 0),
      averageRating: Number(i['averageRating'] || 0),
    })));
  }

  // GET /trainers/me/clients — only APPROVED subscriptions
  if (path.endsWith('/trainers/me/clients') && method === 'GET') {
    const uid = userId(event);
    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      IndexName: 'GSI1',
      KeyConditionExpression: 'GSI1PK = :pk AND begins_with(GSI1SK, :skPrefix)',
      FilterExpression: '#st = :approved',
      ExpressionAttributeNames: { '#st': 'status' },
      ExpressionAttributeValues: { ':pk': `TRAINER_CLIENTS#${uid}`, ':approved': 'APPROVED', ':skPrefix': 'CLIENT#' },
    }));
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({ clients: items.map(i => ({ id: i['clientId'], name: i['displayName'] || '', gymId: i['gymId'] || '' })) });
  }

  // GET /trainers/me/subscription-requests — pending + approved + rejected
  if (path.endsWith('/trainers/me/subscription-requests') && method === 'GET') {
    const uid = userId(event);
    const statusFilter = (event.queryStringParameters || {})['status']; // optional: PENDING|APPROVED|REJECTED
    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      IndexName: 'GSI1',
      KeyConditionExpression: 'GSI1PK = :pk AND begins_with(GSI1SK, :skPrefix)',
      ...(statusFilter ? {
        FilterExpression: '#st = :sf',
        ExpressionAttributeNames: { '#st': 'status' },
        ExpressionAttributeValues: { ':pk': `TRAINER_CLIENTS#${uid}`, ':sf': statusFilter.toUpperCase(), ':skPrefix': 'REQUEST#' },
      } : {
        ExpressionAttributeValues: { ':pk': `TRAINER_CLIENTS#${uid}`, ':skPrefix': 'REQUEST#' },
      }),
    }));
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({
      requests: items.map(i => ({
        requestId: i['requestId'] || i['SK'],
        clientId: i['clientId'] || '',
        clientName: i['displayName'] || '',
        gymId: i['gymId'] || '',
        status: i['status'] || 'PENDING',
        requestedAt: i['requestedAt'] || i['createdAt'] || '',
        respondedAt: i['respondedAt'] || null,
      })),
    });
  }

  // PATCH /trainers/me/subscription-requests/:requestId — approve or reject
  const respondMatch = path.match(/\/trainers\/me\/subscription-requests\/([^/]+)$/);
  if (respondMatch && method === 'PATCH') {
    const requestId = respondMatch[1];
    const uid = userId(event);
    const body = JSON.parse(event.body || '{}');
    const action = (body.action || '').toUpperCase(); // APPROVE | REJECT

    if (action !== 'APPROVE' && action !== 'REJECT') {
      return err(400, 'action يجب أن يكون APPROVE أو REJECT');
    }

    // Fetch the request item first
    const reqRes = await docClient.send(new GetCommand({
      TableName: TABLE,
      Key: { PK: `TRAINER#${uid}`, SK: `SUBSCRIPTION_REQUEST#${requestId}` },
    }));
    if (!reqRes.Item) {
      return err(404, 'الطلب غير موجود');
    }

    const reqItem = reqRes.Item as Record<string, unknown>;
    const newStatus = action === 'APPROVE' ? 'APPROVED' : 'REJECTED';

    // Update the request status
    await docClient.send(new UpdateCommand({
      TableName: TABLE,
      Key: { PK: `TRAINER#${uid}`, SK: `SUBSCRIPTION_REQUEST#${requestId}` },
      UpdateExpression: 'SET #st = :s, respondedAt = :r',
      ExpressionAttributeNames: { '#st': 'status' },
      ExpressionAttributeValues: { ':s': newStatus, ':r': new Date().toISOString() },
    }));

    // Update the GSI1 projection item (for client-list queries)
    const clientId = reqItem['clientId'] as string;
    if (clientId) {
      await docClient.send(new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `TRAINER#${uid}`, SK: `CLIENT#${clientId}` },
        UpdateExpression: 'SET #st = :s, respondedAt = :r, GSI1PK = :gpk, GSI1SK = :gsk',
        ExpressionAttributeNames: { '#st': 'status' },
        ExpressionAttributeValues: {
          ':s': newStatus,
          ':r': new Date().toISOString(),
          ':gpk': `TRAINER_CLIENTS#${uid}`,
          ':gsk': `CLIENT#${clientId}`,
        },
      }));
    }

    // Update the trainee's own subscription record
    if (clientId) {
      await docClient.send(new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `USER#${clientId}`, SK: `SUBSCRIPTION#${uid}` },
        UpdateExpression: 'SET #st = :s, respondedAt = :r',
        ExpressionAttributeNames: { '#st': 'status' },
        ExpressionAttributeValues: { ':s': newStatus, ':r': new Date().toISOString() },
      }));
    }

    const msgMap: Record<string, string> = {
      APPROVED: 'تم قبول طلب الاشتراك',
      REJECTED: 'تم رفض طلب الاشتراك',
    };

    // Notify the trainee about trainer's decision
    if (clientId) {
      await pushNotification(docClient, {
        targetUserId: clientId,
        eventType: action === 'APPROVE' ? 'SUBSCRIPTION_APPROVED' : 'SUBSCRIPTION_REJECTED',
        title: action === 'APPROVE' ? 'تم قبول اشتراكك! 🎉' : 'تم رفض طلب الاشتراك',
        message: action === 'APPROVE'
          ? 'قبل المدرب طلب اشتراكك — يمكنك البدء بالتمرين!'
          : 'رفض المدرب طلب اشتراكك. يمكنك البحث عن مدرب آخر.',
        payload: { trainerId: uid, requestId, action },
      }).catch(() => { /* silent */ });
    }

    return ok({ message: msgMap[newStatus] });
  }

  // POST /trainers/:trainerId/subscribe — trainee sends subscription request
  const subscribeMatch = path.match(/\/trainers\/([^/]+)\/subscribe$/);
  if (subscribeMatch && method === 'POST') {
    const trainerId = subscribeMatch[1];
    const uid = userId(event);
    const uName = userName(event);
    const body = JSON.parse(event.body || '{}');
    const gymId = body.gymId || '';

    if (trainerId === uid) {
      return err(400, 'لا يمكنك الاشتراك مع نفسك');
    }

    // Check for duplicate pending request
    const existing = await docClient.send(new GetCommand({
      TableName: TABLE,
      Key: { PK: `TRAINER#${trainerId}`, SK: `CLIENT#${uid}` },
    }));
    if (existing.Item && (existing.Item as Record<string, unknown>)['status'] === 'PENDING') {
      return err(409, 'لديك طلب اشتراك معلق بالفعل لدى هذا المدرب');
    }
    if (existing.Item && (existing.Item as Record<string, unknown>)['status'] === 'APPROVED') {
      return err(409, 'أنت مشترك بالفعل لدى هذا المدرب');
    }

    const requestId = randomBytes(8).toString('hex');
    const now = new Date().toISOString();

    // Main subscription request item (queried by trainer)
    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `TRAINER#${trainerId}`,
        SK: `SUBSCRIPTION_REQUEST#${requestId}`,
        requestId,
        trainerId,
        clientId: uid,
        displayName: uName,
        gymId,
        status: 'PENDING',
        requestedAt: now,
        // GSI1 for listing by trainer
        GSI1PK: `TRAINER_CLIENTS#${trainerId}`,
        GSI1SK: `REQUEST#${requestId}`,
      },
    }));

    // CLIENT# projection for duplicate-check & status tracking
    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `TRAINER#${trainerId}`,
        SK: `CLIENT#${uid}`,
        requestId,
        trainerId,
        clientId: uid,
        displayName: uName,
        gymId,
        status: 'PENDING',
        requestedAt: now,
        GSI1PK: `TRAINER_CLIENTS#${trainerId}`,
        GSI1SK: `CLIENT#${uid}`,
      },
    }));

    // Trainee's own record: which trainers they've subscribed to
    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `USER#${uid}`,
        SK: `SUBSCRIPTION#${trainerId}`,
        trainerId,
        clientId: uid,
        requestId,
        status: 'PENDING',
        requestedAt: now,
      },
    }));

    // Notify the trainer about new subscription request
    await pushNotification(docClient, {
      targetUserId: trainerId,
      eventType: 'NEW_SUBSCRIPTION_REQUEST',
      title: 'طلب اشتراك جديد',
      message: `${uName || 'متدرب'} يريد الاشتراك معك`,
      payload: { requestId, clientId: uid, gymId },
    }).catch(() => { /* silent */ });

    return created({ requestId, message: 'تم إرسال طلب الاشتراك بنجاح' });
  }

  // GET /trainers/me/my-subscriptions — trainee checks their own subscriptions
  if (path.endsWith('/trainers/me/my-subscriptions') && method === 'GET') {
    const uid = userId(event);
    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
      ExpressionAttributeValues: { ':pk': `USER#${uid}`, ':sk': 'SUBSCRIPTION#' },
    }));
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok({
      subscriptions: items.map(i => ({
        trainerId: i['trainerId'] || '',
        status: i['status'] || 'PENDING',
        requestedAt: i['requestedAt'] || '',
      })),
    });
  }

  // POST /trainers/:trainerId/ratings
  const ratingMatch = path.match(/\/trainers\/([^/]+)\/ratings$/);
  if (ratingMatch && method === 'POST') {
    const trainerId = ratingMatch[1];
    const uid = userId(event);
    const body = JSON.parse(event.body || '{}');
    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `TRAINER#${trainerId}`,
        SK: `RATING#${uid}`,
        userId: uid,
        trainerId,
        gymId: body.gymId || '',
        rating: Number(body.rating) || 5,
        comment: body.comment || '',
        createdAt: new Date().toISOString(),
      },
    }));
    return ok({ message: 'تم تقييم المدرب بنجاح' });
  }

  return err(404, 'المسار غير موجود');
}
