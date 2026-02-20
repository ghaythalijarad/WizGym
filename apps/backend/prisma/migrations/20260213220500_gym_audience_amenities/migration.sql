-- CreateEnum
CREATE TYPE "GymAudience" AS ENUM ('MEN_ONLY', 'WOMEN_ONLY', 'MIXED');

-- AlterTable
ALTER TABLE "Gym"
ADD COLUMN "audience" "GymAudience" NOT NULL DEFAULT 'MIXED',
ADD COLUMN "amenities" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
