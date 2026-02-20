import { IsOptional, IsString, MaxLength } from 'class-validator';

export class RejectGymDto {
  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string;
}
