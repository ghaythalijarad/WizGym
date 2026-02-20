import { Role } from '../enums/role.enum';

export interface RequestUser {
  id: string;
  role: Role;
  name: string;
}
