import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';
import {
  DynamoDBDocumentClient,
  DeleteCommand,
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
function userRole(event: APIGatewayProxyEventV2): string {
  return (event.headers?.['x-user-role'] || event.headers?.['X-User-Role'] || 'USER').toUpperCase();
}
function userName(event: APIGatewayProxyEventV2): string {
  return event.headers?.['x-user-name'] || event.headers?.['X-User-Name'] || '';
}

function gymSummaryFromItem(i: Record<string, unknown>) {
  return {
    id: String(i['gymId'] || i['PK'] || '').replace('GYM#', ''),
    name: i['name'] || '',
    city: i['city'] || '',
    description: i['description'] || null,
    coverImageUrl: i['coverImageUrl'] || null,
    audience: i['audience'] || 'MIXED',
    amenities: (i['amenities'] as string[]) || [],
    membersCount: Number(i['membersCount'] || 0),
    trainersCount: Number(i['trainersCount'] || 0),
    averageRating: Number(i['averageRating'] || 0),
    status: i['status'] || 'ACTIVE',
  };
}

export async function handleGyms(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient,
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || '';
  const method = event.requestContext.http.method;
  const params = event.queryStringParameters || {};

  // GET /gyms/public
  if (path.endsWith('/gyms/public') && method === 'GET') {
    const filterExps: string[] = ['begins_with(PK, :g)', 'SK = :p', '#st = :active'];
    const exprNames: Record<string, string> = { '#st': 'status' };
    const exprValues: Record<string, unknown> = { ':g': 'GYM#', ':p': 'PROFILE', ':active': 'ACTIVE' };

    if (params['city']) {
      filterExps.push('city = :city');
      exprValues[':city'] = params['city'];
    }
    if (params['audience']) {
      filterExps.push('audience = :aud');
      exprValues[':aud'] = params['audience'];
    }

    const res = await docClient.send(new ScanCommand({
      TableName: TABLE,
      FilterExpression: filterExps.join(' AND '),
      ExpressionAttributeNames: exprNames,
      ExpressionAttributeValues: exprValues,
    }));

    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(items.map(gymSummaryFromItem));
  }

  // GET /gyms/owner/mine
  if (path.endsWith('/gyms/owner/mine') && method === 'GET') {
    const uid = userId(event);
    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      IndexName: 'GSI1',
      KeyConditionExpression: 'GSI1PK = :pk',
      ExpressionAttributeValues: { ':pk': `OWNER#${uid}` },
    }));
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(items.map(gymSummaryFromItem));
  }

  // POST /gyms
  if (path.endsWith('/gyms') && method === 'POST') {
    const uid = userId(event);
    const role = userRole(event);
    if (role !== 'OWNER' && role !== 'ADMIN') {
      return err(403, 'فقط أصحاب النوادي يمكنهم إنشاء نادي');
    }

    const body = JSON.parse(event.body || '{}');
    const gymId = randomBytes(8).toString('hex');
    const now = new Date().toISOString();

    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `GYM#${gymId}`,
        SK: 'PROFILE',
        gymId,
        name: body.name || '',
        city: body.city || '',
        description: body.description || null,
        coverImageUrl: body.coverImageUrl || null,
        audience: body.audience || 'MIXED',
        amenities: body.amenities || [],
        ownerId: uid,
        ownerName: userName(event),
        status: 'ACTIVE',
        membersCount: 0,
        trainersCount: 0,
        averageRating: 0,
        createdAt: now,
        updatedAt: now,
        GSI1PK: `OWNER#${uid}`,
        GSI1SK: `GYM#${gymId}`,
      },
    }));

    const plans = Array.isArray(body.subscriptionPlans) ? body.subscriptionPlans : [];
    for (const plan of plans) {
      const planId = randomBytes(6).toString('hex');
      await docClient.send(new PutCommand({
        TableName: TABLE,
        Item: {
          PK: `GYM#${gymId}`,
          SK: `PLAN#${planId}`,
          planId,
          gymId,
          title: plan.title || '',
          durationMonths: Number(plan.durationMonths) || 1,
          price: Number(plan.price) || 0,
          currency: plan.currency || 'IQD',
          description: plan.description || null,
          isActive: true,
          createdAt: now,
        },
      }));
    }

    return created({ id: gymId, message: 'تم إنشاء النادي بنجاح' });
  }

  // GET /gyms/:gymId/public
  const detailMatch = path.match(/\/gyms\/([^/]+)\/public$/);
  if (detailMatch && method === 'GET') {
    const gymId = detailMatch[1];
    const profileRes = await docClient.send(new GetCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: 'PROFILE' },
    }));
    if (!profileRes.Item) return err(404, 'النادي غير موجود');

    const profile = profileRes.Item as Record<string, unknown>;

    const [plansRes, facRes, prodRes] = await Promise.all([
      docClient.send(new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
        ExpressionAttributeValues: { ':pk': `GYM#${gymId}`, ':sk': 'PLAN#' },
      })),
      docClient.send(new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
        ExpressionAttributeValues: { ':pk': `GYM#${gymId}`, ':sk': 'FACILITY#' },
      })),
      docClient.send(new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
        ExpressionAttributeValues: { ':pk': `GYM#${gymId}`, ':sk': 'PRODUCT#' },
      })),
    ]);

    const plans = ((plansRes.Items || []) as Record<string, unknown>[]).map(p => ({
      planId: p['planId'] || '',
      title: p['title'] || '',
      durationMonths: Number(p['durationMonths'] || 1),
      price: Number(p['price'] || 0),
      currency: p['currency'] || 'IQD',
      description: p['description'] || null,
      isActive: p['isActive'] !== false,
    }));

    const facilities = ((facRes.Items || []) as Record<string, unknown>[]).map(f => ({
      id: f['facilityId'] || '',
      name: f['name'] || '',
      description: f['description'] || null,
    }));

    const products = ((prodRes.Items || []) as Record<string, unknown>[]).map(p => ({
      id: p['productId'] || '',
      title: p['title'] || '',
      description: p['description'] || null,
      price: p['price'] != null ? Number(p['price']) : null,
    }));

    return ok({
      id: gymId,
      name: profile['name'] || '',
      city: profile['city'] || '',
      description: profile['description'] || null,
      coverImageUrl: profile['coverImageUrl'] || null,
      audience: profile['audience'] || 'MIXED',
      amenities: (profile['amenities'] as string[]) || [],
      ownerName: profile['ownerName'] || '',
      averageRating: Number(profile['averageRating'] || 0),
      facilities,
      products,
      subscriptionPlans: plans,
    });
  }

  // PATCH /gyms/:gymId/profile
  const profilePatch = path.match(/\/gyms\/([^/]+)\/profile$/);
  if (profilePatch && method === 'PATCH') {
    const gymId = profilePatch[1];
    const body = JSON.parse(event.body || '{}');
    const now = new Date().toISOString();

    const updateParts: string[] = ['updatedAt = :now'];
    const exprValues: Record<string, unknown> = { ':now': now };
    const exprNames: Record<string, string> = {};

    if (body.audience !== undefined) {
      updateParts.push('audience = :aud');
      exprValues[':aud'] = body.audience;
    }
    if (body.amenities !== undefined) {
      updateParts.push('amenities = :am');
      exprValues[':am'] = body.amenities;
    }
    if (body.description !== undefined) {
      updateParts.push('#desc = :desc');
      exprNames['#desc'] = 'description';
      exprValues[':desc'] = body.description;
    }
    if (body.name !== undefined) {
      updateParts.push('#nm = :nm');
      exprNames['#nm'] = 'name';
      exprValues[':nm'] = body.name;
    }
    if (body.city !== undefined) {
      updateParts.push('city = :city');
      exprValues[':city'] = body.city;
    }
    if (body.coverImageUrl !== undefined) {
      updateParts.push('coverImageUrl = :img');
      exprValues[':img'] = body.coverImageUrl;
    }

    await docClient.send(new UpdateCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: 'PROFILE' },
      UpdateExpression: `SET ${updateParts.join(', ')}`,
      ...(Object.keys(exprNames).length > 0 ? { ExpressionAttributeNames: exprNames } : {}),
      ExpressionAttributeValues: exprValues,
    }));

    return ok({ message: 'تم تحديث ملف النادي' });
  }

  // GET /gyms/:gymId/trainers
  const trainersMatch = path.match(/\/gyms\/([^/]+)\/trainers$/);
  if (trainersMatch && method === 'GET') {
    const gymId = trainersMatch[1];
    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
      ExpressionAttributeValues: { ':pk': `GYM#${gymId}`, ':sk': 'TRAINER#' },
    }));
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(items.map(t => ({
      trainerId: t['trainerId'] || '',
      displayName: t['displayName'] || '',
      activeClients: Number(t['activeClients'] || 0),
      averageRating: Number(t['averageRating'] || 0),
      hiredByRequester: false,
    })));
  }

  // POST /gyms/:gymId/trainers/join
  const trainerJoinMatch = path.match(/\/gyms\/([^/]+)\/trainers\/join$/);
  if (trainerJoinMatch && method === 'POST') {
    const gymId = trainerJoinMatch[1];
    const uid = userId(event);
    const uName = userName(event);
    const now = new Date().toISOString();

    await docClient.send(new PutCommand({
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
    }));

    await docClient.send(new UpdateCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: 'PROFILE' },
      UpdateExpression: 'SET trainersCount = if_not_exists(trainersCount, :zero) + :one, updatedAt = :now',
      ExpressionAttributeValues: { ':zero': 0, ':one': 1, ':now': now },
    }));

    const gymProfile = await docClient.send(new GetCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: 'PROFILE' },
    }));
    const ownerId = (gymProfile.Item as Record<string, unknown> | undefined)?.['ownerId'] as string | undefined;
    if (ownerId) {
      await pushNotification(docClient, {
        targetUserId: ownerId,
        eventType: 'TRAINER_JOINED',
        title: 'مدرب جديد انضم للنادي',
        message: `${uName || 'مدرب'} انضم إلى ناديك`,
        payload: { gymId, trainerId: uid },
      }).catch(() => { /* silent */ });
    }

    return created({ message: 'تم انضمام المدرب للنادي بنجاح' });
  }

  // POST /gyms/:gymId/trainers/:trainerId/hire
  const hireMatch = path.match(/\/gyms\/([^/]+)\/trainers\/([^/]+)\/hire$/);
  if (hireMatch && method === 'POST') {
    const gymId = hireMatch[1];
    const trainerId = hireMatch[2];
    const now = new Date().toISOString();

    await docClient.send(new UpdateCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: `TRAINER#${trainerId}` },
      UpdateExpression: 'SET hiredAt = :now',
      ExpressionAttributeValues: { ':now': now },
    }));

    return ok({ message: 'تم توظيف المدرب بنجاح' });
  }

  // POST /gyms/:gymId/join
  const joinMatch = path.match(/\/gyms\/([^/]+)\/join$/);
  if (joinMatch && method === 'POST') {
    const gymId = joinMatch[1];
    const uid = userId(event);
    const uName = userName(event);
    const body = JSON.parse(event.body || '{}');
    const now = new Date().toISOString();

    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `GYM#${gymId}`,
        SK: `MEMBER#${uid}`,
        userId: uid,
        userName: uName,
        gymId,
        selectedPlanId: body.planId || null,
        status: 'PENDING',
        joinedAt: now,
        GSI2PK: `USER_GYMS#${uid}`,
        GSI2SK: `GYM#${gymId}`,
      },
    }));

    const gymProfile = await docClient.send(new GetCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: 'PROFILE' },
    }));
    const ownerId = (gymProfile.Item as Record<string, unknown> | undefined)?.['ownerId'] as string | undefined;
    if (ownerId) {
      await pushNotification(docClient, {
        targetUserId: ownerId,
        eventType: 'MEMBER_JOIN_REQUEST',
        title: 'طلب انضمام جديد',
        message: `${uName || 'عضو'} يريد الانضمام إلى ناديك`,
        payload: { gymId, userId: uid },
      }).catch(() => { /* silent */ });
    }

    return created({ message: 'تم إرسال طلب الانضمام' });
  }

  // GET /gyms/:gymId/members
  const membersListMatch = path.match(/\/gyms\/([^/]+)\/members$/);
  if (membersListMatch && method === 'GET') {
    const gymId = membersListMatch[1];
    const statusFilter = params['status'];

    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
      ...(statusFilter ? {
        FilterExpression: '#st = :sf',
        ExpressionAttributeNames: { '#st': 'status' },
        ExpressionAttributeValues: { ':pk': `GYM#${gymId}`, ':sk': 'MEMBER#', ':sf': statusFilter.toUpperCase() },
      } : {
        ExpressionAttributeValues: { ':pk': `GYM#${gymId}`, ':sk': 'MEMBER#' },
      }),
    }));

    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(items.map(m => ({
      userId: m['userId'] || '',
      userName: m['userName'] || '',
      gymId: m['gymId'] || gymId,
      status: m['status'] || 'PENDING',
      joinedAt: m['joinedAt'] || '',
      selectedPlanId: m['selectedPlanId'] || null,
    })));
  }

  // PATCH /gyms/:gymId/members/:memberId
  const memberActionMatch = path.match(/\/gyms\/([^/]+)\/members\/([^/]+)$/);
  if (memberActionMatch && method === 'PATCH') {
    const gymId = memberActionMatch[1];
    const memberId = memberActionMatch[2];
    const body = JSON.parse(event.body || '{}');
    const action = (body.action || '').toUpperCase();

    if (action !== 'APPROVE' && action !== 'REJECT') {
      return err(400, 'action يجب أن يكون APPROVE أو REJECT');
    }

    const newStatus = action === 'APPROVE' ? 'ACTIVE' : 'REJECTED';
    const now = new Date().toISOString();

    await docClient.send(new UpdateCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: `MEMBER#${memberId}` },
      UpdateExpression: 'SET #st = :s, updatedAt = :now',
      ExpressionAttributeNames: { '#st': 'status' },
      ExpressionAttributeValues: { ':s': newStatus, ':now': now },
    }));

    if (action === 'APPROVE') {
      await docClient.send(new UpdateCommand({
        TableName: TABLE,
        Key: { PK: `GYM#${gymId}`, SK: 'PROFILE' },
        UpdateExpression: 'SET membersCount = if_not_exists(membersCount, :zero) + :one, updatedAt = :now',
        ExpressionAttributeValues: { ':zero': 0, ':one': 1, ':now': now },
      }));
    }

    await pushNotification(docClient, {
      targetUserId: memberId,
      eventType: action === 'APPROVE' ? 'MEMBERSHIP_APPROVED' : 'MEMBERSHIP_REJECTED',
      title: action === 'APPROVE' ? 'تم قبول طلب الانضمام!' : 'تم رفض طلب الانضمام',
      message: action === 'APPROVE'
        ? 'تم قبولك في النادي — مرحباً بك!'
        : 'للأسف تم رفض طلب انضمامك. يمكنك المحاولة لاحقاً.',
      payload: { gymId, action },
    }).catch(() => { /* silent */ });

    return ok({ message: action === 'APPROVE' ? 'تم قبول العضو' : 'تم رفض العضو' });
  }

  // PATCH /gyms/:gymId/subscription-plans/:planId
  const planUpdateMatch = path.match(/\/gyms\/([^/]+)\/subscription-plans\/([^/]+)$/);
  if (planUpdateMatch && method === 'PATCH') {
    const gymId = planUpdateMatch[1];
    const planId = planUpdateMatch[2];
    const body = JSON.parse(event.body || '{}');
    const now = new Date().toISOString();

    const updateParts: string[] = ['updatedAt = :now'];
    const exprValues: Record<string, unknown> = { ':now': now };
    const exprNames: Record<string, string> = {};

    if (body.title !== undefined) {
      updateParts.push('title = :t');
      exprValues[':t'] = body.title;
    }
    if (body.durationMonths !== undefined) {
      updateParts.push('durationMonths = :d');
      exprValues[':d'] = Number(body.durationMonths);
    }
    if (body.price !== undefined) {
      updateParts.push('price = :p');
      exprValues[':p'] = Number(body.price);
    }
    if (body.currency !== undefined) {
      updateParts.push('currency = :c');
      exprValues[':c'] = body.currency;
    }
    if (body.description !== undefined) {
      updateParts.push('#desc = :desc');
      exprNames['#desc'] = 'description';
      exprValues[':desc'] = body.description;
    }
    if (body.isActive !== undefined) {
      updateParts.push('isActive = :a');
      exprValues[':a'] = body.isActive === true;
    }

    await docClient.send(new UpdateCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: `PLAN#${planId}` },
      UpdateExpression: `SET ${updateParts.join(', ')}`,
      ...(Object.keys(exprNames).length > 0 ? { ExpressionAttributeNames: exprNames } : {}),
      ExpressionAttributeValues: exprValues,
    }));

    return ok({ message: 'تم تحديث خطة الاشتراك' });
  }

  // DELETE /gyms/:gymId/subscription-plans/:planId
  if (planUpdateMatch && method === 'DELETE') {
    const gymId = planUpdateMatch[1];
    const planId = planUpdateMatch[2];

    await docClient.send(new DeleteCommand({
      TableName: TABLE,
      Key: { PK: `GYM#${gymId}`, SK: `PLAN#${planId}` },
    }));

    return ok({ message: 'تم حذف خطة الاشتراك' });
  }

  // POST /gyms/:gymId/subscription-plans
  const planListMatch = path.match(/\/gyms\/([^/]+)\/subscription-plans$/);
  if (planListMatch && method === 'POST') {
    const gymId = planListMatch[1];
    const body = JSON.parse(event.body || '{}');
    const planId = randomBytes(6).toString('hex');
    const now = new Date().toISOString();

    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `GYM#${gymId}`,
        SK: `PLAN#${planId}`,
        planId,
        gymId,
        title: body.title || '',
        durationMonths: Number(body.durationMonths) || 1,
        price: Number(body.price) || 0,
        currency: body.currency || 'IQD',
        description: body.description || null,
        isActive: true,
        createdAt: now,
      },
    }));

    return created({ planId, message: 'تم إنشاء خطة الاشتراك' });
  }

  // GET /gyms/:gymId/subscription-plans
  if (planListMatch && method === 'GET') {
    const gymId = planListMatch[1];
    const res = await docClient.send(new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
      ExpressionAttributeValues: { ':pk': `GYM#${gymId}`, ':sk': 'PLAN#' },
    }));
    const items = (res.Items || []) as Record<string, unknown>[];
    return ok(items.map(p => ({
      planId: p['planId'] || '',
      title: p['title'] || '',
      durationMonths: Number(p['durationMonths'] || 1),
      price: Number(p['price'] || 0),
      currency: p['currency'] || 'IQD',
      description: p['description'] || null,
      isActive: p['isActive'] !== false,
    })));
  }

  // POST /gyms/:gymId/ratings
  const ratingMatch = path.match(/\/gyms\/([^/]+)\/ratings$/);
  if (ratingMatch && method === 'POST') {
    const gymId = ratingMatch[1];
    const uid = userId(event);
    const body = JSON.parse(event.body || '{}');
    const now = new Date().toISOString();

    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `GYM#${gymId}`,
        SK: `RATING#${uid}`,
        userId: uid,
        gymId,
        rating: Number(body.rating) || 5,
        comment: body.comment || '',
        createdAt: now,
      },
    }));

    return ok({ message: 'تم تقييم النادي بنجاح' });
  }

  // POST /gyms/:gymId/facilities
  const facilityMatch = path.match(/\/gyms\/([^/]+)\/facilities$/);
  if (facilityMatch && method === 'POST') {
    const gymId = facilityMatch[1];
    const body = JSON.parse(event.body || '{}');
    const facilityId = randomBytes(6).toString('hex');
    const now = new Date().toISOString();

    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `GYM#${gymId}`,
        SK: `FACILITY#${facilityId}`,
        facilityId,
        gymId,
        name: body.name || '',
        description: body.description || null,
        createdAt: now,
      },
    }));

    return created({ id: facilityId, message: 'تم إضافة المرفق' });
  }

  // POST /gyms/:gymId/products
  const productMatch = path.match(/\/gyms\/([^/]+)\/products$/);
  if (productMatch && method === 'POST') {
    const gymId = productMatch[1];
    const body = JSON.parse(event.body || '{}');
    const productId = randomBytes(6).toString('hex');
    const now = new Date().toISOString();

    await docClient.send(new PutCommand({
      TableName: TABLE,
      Item: {
        PK: `GYM#${gymId}`,
        SK: `PRODUCT#${productId}`,
        productId,
        gymId,
        title: body.title || '',
        description: body.description || null,
        price: body.price != null ? Number(body.price) : null,
        isActive: body.isActive !== false,
        createdAt: now,
      },
    }));

    return created({ id: productId, message: 'تم إضافة المنتج' });
  }

  return err(404, 'المسار غير موجود');
}
