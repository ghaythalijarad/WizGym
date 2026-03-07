import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from 'aws-lambda';
import { DynamoDBDocumentClient, GetCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';

const TABLE = process.env.DYNAMODB_TABLE_NAME || 'wizgym-prod-core';

function ok(body: unknown): APIGatewayProxyResultV2 {
  return { statusCode: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}

function err(status: number, msg: string): APIGatewayProxyResultV2 {
  return { statusCode: status, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ message: msg }) };
}

function getUserId(event: APIGatewayProxyEventV2): string {
  return event.headers?.['x-user-id'] || event.headers?.['X-User-Id'] || '';
}

function getUserRole(event: APIGatewayProxyEventV2): string {
  return event.headers?.['x-user-role'] || event.headers?.['X-User-Role'] || 'USER';
}

function getUserName(event: APIGatewayProxyEventV2): string {
  return event.headers?.['x-user-name'] || event.headers?.['X-User-Name'] || '';
}

export async function handleUsers(
  event: APIGatewayProxyEventV2,
  docClient: DynamoDBDocumentClient,
): Promise<APIGatewayProxyResultV2> {
  const path = event.rawPath || '';
  const method = event.requestContext.http.method;

  // GET /users/me - Get current user profile
  if (path.endsWith('/users/me') && method === 'GET') {
    const userId = getUserId(event);
    const role = getUserRole(event);
    const displayName = getUserName(event);

    // If we have user ID, try to fetch from DB
    if (userId && userId !== 'anon' && !userId.startsWith('demo')) {
      try {
        const result = await docClient.send(
          new GetCommand({
            TableName: TABLE,
            Key: {
              PK: userId.startsWith('USER#') ? userId : `USER#${userId}`,
              SK: 'PROFILE',
            },
          })
        );

        if (result.Item) {
          return ok({
            id: result.Item.id || userId,
            phoneNumber: result.Item.phoneNumber || '',
            displayName: result.Item.displayName || displayName,
            role: result.Item.role || role,
            createdAt: result.Item.createdAt,
            lastLoginAt: result.Item.lastLoginAt || result.Item.updatedAt,
          });
        }
      } catch (e) {
        console.error('Error fetching user profile:', e);
      }
    }

    // Return profile from headers (demo/fallback mode)
    return ok({
      id: userId || 'demo-user',
      phoneNumber: '',
      displayName: displayName || role,
      role: role,
      createdAt: new Date().toISOString(),
      lastLoginAt: new Date().toISOString(),
    });
  }

  // DELETE /users/me - Delete current user account
  if (path.endsWith('/users/me') && method === 'DELETE') {
    const userId = getUserId(event);

    if (!userId || userId === 'anon' || userId.startsWith('demo')) {
      return err(400, 'لا يمكن حذف حساب تجريبي');
    }

    try {
      await docClient.send(
        new DeleteCommand({
          TableName: TABLE,
          Key: {
            PK: userId.startsWith('USER#') ? userId : `USER#${userId}`,
            SK: 'PROFILE',
          },
        })
      );

      return ok({ message: 'تم حذف الحساب بنجاح' });
    } catch (e) {
      console.error('Error deleting user:', e);
      return err(500, 'فشل في حذف الحساب');
    }
  }

  return err(404, 'المسار غير موجود');
}
