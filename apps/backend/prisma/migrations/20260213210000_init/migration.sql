-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "GymApprovalStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('ACTIVE', 'PAUSED', 'CANCELED');

-- CreateEnum
CREATE TYPE "PhoneOtpStatus" AS ENUM ('PENDING', 'VERIFIED', 'FAILED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "TrainerHireStatus" AS ENUM ('ACTIVE', 'COMPLETED', 'CANCELED');

-- CreateTable
CREATE TABLE "GymApplication" (
    "id" TEXT NOT NULL,
    "gymName" TEXT NOT NULL,
    "ownerName" TEXT NOT NULL,
    "ownerUserId" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "requestedAt" TIMESTAMP(3) NOT NULL,
    "status" "GymApprovalStatus" NOT NULL DEFAULT 'PENDING',
    "reviewNote" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GymApplication_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Gym" (
    "id" TEXT NOT NULL,
    "applicationId" TEXT,
    "name" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "ownerUserId" TEXT NOT NULL,
    "ownerName" TEXT NOT NULL,
    "description" TEXT,
    "coverImageUrl" TEXT,
    "status" "GymApprovalStatus" NOT NULL DEFAULT 'APPROVED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Gym_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GymMembership" (
    "id" TEXT NOT NULL,
    "gymId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GymMembership_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GymTrainerMembership" (
    "id" TEXT NOT NULL,
    "gymId" TEXT NOT NULL,
    "trainerId" TEXT NOT NULL,
    "joinedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "GymTrainerMembership_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TrainerHire" (
    "id" TEXT NOT NULL,
    "gymId" TEXT NOT NULL,
    "trainerId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "status" "TrainerHireStatus" NOT NULL DEFAULT 'ACTIVE',
    "hiredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMP(3),

    CONSTRAINT "TrainerHire_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GymRating" (
    "id" TEXT NOT NULL,
    "gymId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "rating" INTEGER NOT NULL,
    "comment" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GymRating_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TrainerRating" (
    "id" TEXT NOT NULL,
    "gymId" TEXT NOT NULL,
    "trainerId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "rating" INTEGER NOT NULL,
    "comment" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TrainerRating_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GymFacility" (
    "id" TEXT NOT NULL,
    "gymId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "imageUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GymFacility_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "GymProduct" (
    "id" TEXT NOT NULL,
    "gymId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "imageUrl" TEXT,
    "price" INTEGER,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GymProduct_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PlatformSubscription" (
    "id" TEXT NOT NULL,
    "gymId" TEXT NOT NULL,
    "gymName" TEXT NOT NULL,
    "planName" TEXT NOT NULL,
    "membersLimit" INTEGER NOT NULL,
    "monthlyPrice" INTEGER NOT NULL,
    "nextBillingDate" TIMESTAMP(3) NOT NULL,
    "status" "SubscriptionStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PlatformSubscription_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PhoneVerificationSession" (
    "id" TEXT NOT NULL,
    "phoneNumber" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "codeSalt" TEXT NOT NULL,
    "smsId" TEXT,
    "provider" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "verifiedAt" TIMESTAMP(3),
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "maxAttempts" INTEGER NOT NULL,
    "status" "PhoneOtpStatus" NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PhoneVerificationSession_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Gym_applicationId_key" ON "Gym"("applicationId");

-- CreateIndex
CREATE INDEX "Gym_status_city_idx" ON "Gym"("status", "city");

-- CreateIndex
CREATE INDEX "Gym_ownerUserId_idx" ON "Gym"("ownerUserId");

-- CreateIndex
CREATE INDEX "GymMembership_userId_idx" ON "GymMembership"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "GymMembership_gymId_userId_key" ON "GymMembership"("gymId", "userId");

-- CreateIndex
CREATE INDEX "GymTrainerMembership_trainerId_active_idx" ON "GymTrainerMembership"("trainerId", "active");

-- CreateIndex
CREATE UNIQUE INDEX "GymTrainerMembership_gymId_trainerId_key" ON "GymTrainerMembership"("gymId", "trainerId");

-- CreateIndex
CREATE INDEX "TrainerHire_userId_status_idx" ON "TrainerHire"("userId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "TrainerHire_gymId_trainerId_userId_key" ON "TrainerHire"("gymId", "trainerId", "userId");

-- CreateIndex
CREATE INDEX "GymRating_gymId_idx" ON "GymRating"("gymId");

-- CreateIndex
CREATE UNIQUE INDEX "GymRating_gymId_userId_key" ON "GymRating"("gymId", "userId");

-- CreateIndex
CREATE INDEX "TrainerRating_trainerId_idx" ON "TrainerRating"("trainerId");

-- CreateIndex
CREATE UNIQUE INDEX "TrainerRating_gymId_trainerId_userId_key" ON "TrainerRating"("gymId", "trainerId", "userId");

-- CreateIndex
CREATE INDEX "GymFacility_gymId_idx" ON "GymFacility"("gymId");

-- CreateIndex
CREATE INDEX "GymProduct_gymId_isActive_idx" ON "GymProduct"("gymId", "isActive");

-- CreateIndex
CREATE UNIQUE INDEX "PlatformSubscription_gymId_key" ON "PlatformSubscription"("gymId");

-- CreateIndex
CREATE INDEX "PlatformSubscription_status_idx" ON "PlatformSubscription"("status");

-- CreateIndex
CREATE INDEX "PhoneVerificationSession_phoneNumber_status_createdAt_idx" ON "PhoneVerificationSession"("phoneNumber", "status", "createdAt");

-- AddForeignKey
ALTER TABLE "Gym" ADD CONSTRAINT "Gym_applicationId_fkey" FOREIGN KEY ("applicationId") REFERENCES "GymApplication"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GymMembership" ADD CONSTRAINT "GymMembership_gymId_fkey" FOREIGN KEY ("gymId") REFERENCES "Gym"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GymTrainerMembership" ADD CONSTRAINT "GymTrainerMembership_gymId_fkey" FOREIGN KEY ("gymId") REFERENCES "Gym"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TrainerHire" ADD CONSTRAINT "TrainerHire_gymId_fkey" FOREIGN KEY ("gymId") REFERENCES "Gym"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TrainerHire" ADD CONSTRAINT "TrainerHire_gymId_trainerId_fkey" FOREIGN KEY ("gymId", "trainerId") REFERENCES "GymTrainerMembership"("gymId", "trainerId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GymRating" ADD CONSTRAINT "GymRating_gymId_fkey" FOREIGN KEY ("gymId") REFERENCES "Gym"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TrainerRating" ADD CONSTRAINT "TrainerRating_gymId_fkey" FOREIGN KEY ("gymId") REFERENCES "Gym"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TrainerRating" ADD CONSTRAINT "TrainerRating_gymId_trainerId_fkey" FOREIGN KEY ("gymId", "trainerId") REFERENCES "GymTrainerMembership"("gymId", "trainerId") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GymFacility" ADD CONSTRAINT "GymFacility_gymId_fkey" FOREIGN KEY ("gymId") REFERENCES "Gym"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "GymProduct" ADD CONSTRAINT "GymProduct_gymId_fkey" FOREIGN KEY ("gymId") REFERENCES "Gym"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PlatformSubscription" ADD CONSTRAINT "PlatformSubscription_gymId_fkey" FOREIGN KEY ("gymId") REFERENCES "GymApplication"("id") ON DELETE CASCADE ON UPDATE CASCADE;

