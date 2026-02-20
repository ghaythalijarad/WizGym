import { IsString, Length, Matches } from 'class-validator';

export class VerifyPhoneOtpDto {
  @IsString()
  @Matches(/^\+?[1-9]\d{8,14}$/, {
    message: 'phoneNumber must be a valid international number',
  })
  phoneNumber!: string;

  @IsString()
  @Length(4, 8)
  @Matches(/^\d+$/, { message: 'code must contain only digits' })
  code!: string;
}
