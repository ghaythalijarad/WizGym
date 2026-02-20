import { IsString, Matches } from 'class-validator';

export class LoginDto {
  @IsString()
  @Matches(/^\+?[1-9]\d{8,14}$/, {
    message: 'phoneNumber must be a valid international number',
  })
  phoneNumber!: string;
}
