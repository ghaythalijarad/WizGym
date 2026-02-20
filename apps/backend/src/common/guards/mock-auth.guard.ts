import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';

import { Role } from '../enums/role.enum';
import { RequestUser } from '../interfaces/request-user.interface';

@Injectable()
export class MockAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();

    const headerRole = String(request.headers['x-user-role'] ?? '').toUpperCase();
    const role = this.resolveRole(headerRole);

    const user: RequestUser = {
      id: String(request.headers['x-user-id'] ?? 'demo-user-id'),
      name: String(request.headers['x-user-name'] ?? 'Demo User'),
      role,
    };

    request.user = user;
    return true;
  }

  private resolveRole(raw: string): Role {
    if (raw === Role.ADMIN) {
      return Role.ADMIN;
    }

    if (raw === Role.OWNER) {
      return Role.OWNER;
    }

    if (raw === Role.TRAINER) {
      return Role.TRAINER;
    }

    return Role.USER;
  }
}
