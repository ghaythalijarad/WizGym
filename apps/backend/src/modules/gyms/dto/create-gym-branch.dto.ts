import { IsNumber, IsOptional, IsString, MaxLength } from 'class-validator';

export class CreateGymBranchDto {
  @IsString()
  @MaxLength(100)
  name!: string;

  @IsString()
  @MaxLength(80)
  city!: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  address?: string;

  @IsOptional()
  @IsString()
  @MaxLength(15)
  phoneNumber?: string;

  @IsOptional()
  @IsNumber()
  lat?: number;

  @IsOptional()
  @IsNumber()
  lng?: number;
}

