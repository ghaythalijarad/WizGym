import { IsEnum, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';

import { Role } from '../../../common/enums/role.enum';

export class SignupDto {
  @IsString()
  @Matches(/^\+?[1-9]\d{8,14}$/, {
    message: 'phoneNumber must be a valid international number',
  })
  phoneNumber!: string;

  @IsEnum(Role)
  role!: Role;

  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  displayName?: string;
}
