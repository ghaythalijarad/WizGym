import { IsArray, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

const gymAudiences = ['MEN_ONLY', 'WOMEN_ONLY', 'MIXED'] as const;

export class UpdateGymProfileDto {
  @IsOptional()
  @IsIn(gymAudiences)
  audience?: (typeof gymAudiences)[number];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  amenities?: string[];

  @IsOptional()
  @IsString()
  @MaxLength(600)
  description?: string;
}
