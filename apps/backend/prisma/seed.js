const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
  await prisma.userAccount.deleteMany();
  await prisma.phoneVerificationSession.deleteMany();
  await prisma.trainerRating.deleteMany();
  await prisma.gymRating.deleteMany();
  await prisma.trainerHire.deleteMany();
  await prisma.gymProduct.deleteMany();
  await prisma.gymFacility.deleteMany();
  await prisma.gymTrainerMembership.deleteMany();
  await prisma.gymMembership.deleteMany();
  await prisma.gym.deleteMany();
  await prisma.platformSubscription.deleteMany();
  await prisma.gymApplication.deleteMany();

  await prisma.userAccount.createMany({
    data: [
      {
        id: 'acc-admin-1',
        phoneNumber: '9647700000001',
        displayName: 'Platform Admin',
        role: 'ADMIN',
      },
      {
        id: 'acc-owner-1',
        phoneNumber: '9647700000002',
        displayName: 'Demo Owner',
        role: 'OWNER',
      },
      {
        id: 'acc-trainer-1',
        phoneNumber: '9647700000003',
        displayName: 'Demo Trainer',
        role: 'TRAINER',
      },
      {
        id: 'acc-user-1',
        phoneNumber: '9647700000004',
        displayName: 'Demo User',
        role: 'USER',
      },
    ],
  });

  await prisma.gymApplication.createMany({
    data: [
      {
        id: 'gym-1001',
        gymName: 'Power Zone Fitness',
        ownerName: 'Khaled Alotaibi',
        ownerUserId: 'owner-1001',
        city: 'Riyadh',
        requestedAt: new Date('2026-02-09T09:20:00.000Z'),
        status: 'PENDING',
      },
      {
        id: 'gym-1002',
        gymName: 'Elite Ladies Gym',
        ownerName: 'Nora Alharbi',
        ownerUserId: 'owner-1002',
        city: 'Jeddah',
        requestedAt: new Date('2026-02-10T14:05:00.000Z'),
        status: 'PENDING',
      },
      {
        id: 'gym-1003',
        gymName: 'Iron Core Club',
        ownerName: 'Faisal Alrashid',
        ownerUserId: 'owner-1003',
        city: 'Dammam',
        requestedAt: new Date('2026-02-07T11:45:00.000Z'),
        status: 'APPROVED',
        reviewNote: 'All compliance documents verified.',
        reviewedAt: new Date('2026-02-08T10:00:00.000Z'),
      },
    ],
  });

  await prisma.platformSubscription.createMany({
    data: [
      {
        id: 'sub-501',
        gymId: 'gym-1003',
        gymName: 'Iron Core Club',
        planName: 'Business Pro',
        membersLimit: 1500,
        monthlyPrice: 1299,
        nextBillingDate: new Date('2026-03-01T00:00:00.000Z'),
        status: 'ACTIVE',
      },
      {
        id: 'sub-502',
        gymId: 'gym-1002',
        gymName: 'Elite Ladies Gym',
        planName: 'Starter',
        membersLimit: 400,
        monthlyPrice: 499,
        nextBillingDate: new Date('2026-03-03T00:00:00.000Z'),
        status: 'PAUSED',
      },
      {
        id: 'sub-503',
        gymId: 'gym-1001',
        gymName: 'Power Zone Fitness',
        planName: 'Growth',
        membersLimit: 900,
        monthlyPrice: 799,
        nextBillingDate: new Date('2026-02-27T00:00:00.000Z'),
        status: 'ACTIVE',
      },
    ],
  });

  await prisma.gym.createMany({
    data: [
      {
        id: 'gym-1003',
        applicationId: 'gym-1003',
        name: 'Iron Core Club',
        city: 'Dammam',
        ownerUserId: 'owner-1003',
        ownerName: 'Faisal Alrashid',
        description: 'Strength and functional training hub with premium studio zones.',
        coverImageUrl: 'https://images.example.com/iron-core.jpg',
        audience: 'MEN_ONLY',
        amenities: ['Sauna', 'Food Bar', 'Parking'],
        status: 'APPROVED',
      },
      {
        id: 'gym-2001',
        name: 'WizGym Downtown',
        city: 'Baghdad',
        ownerUserId: 'owner-2001',
        ownerName: 'Mazin Kareem',
        description: 'Modern city gym focused on body transformation programs.',
        coverImageUrl: 'https://images.example.com/wizgym-downtown.jpg',
        audience: 'MIXED',
        amenities: ['Sauna', 'Steam Room', 'Pool', 'Parking'],
        status: 'APPROVED',
      },
      {
        id: 'gym-2002',
        name: 'WizGym Ladies Studio',
        city: 'Baghdad',
        ownerUserId: 'owner-2002',
        ownerName: 'Lina Saad',
        description: 'Private women-only training environment with group classes.',
        coverImageUrl: 'https://images.example.com/wizgym-ladies.jpg',
        audience: 'WOMEN_ONLY',
        amenities: ['Food Bar', 'Pilates Studio', 'Kids Area'],
        status: 'APPROVED',
      },
    ],
  });

  await prisma.gymFacility.createMany({
    data: [
      {
        gymId: 'gym-1003',
        name: 'Powerlifting Zone',
        description: 'Competition racks and calibrated plates.',
        imageUrl: 'https://images.example.com/facility-powerlifting.jpg',
      },
      {
        gymId: 'gym-1003',
        name: 'Recovery Studio',
        description: 'Stretching and mobility dedicated room.',
      },
      {
        gymId: 'gym-2001',
        name: 'Cardio Hall',
        description: 'Treadmills, bikes, and rowers with panoramic view.',
      },
      {
        gymId: 'gym-2002',
        name: 'Pilates Studio',
        description: 'Small-group reformer and mat pilates sessions.',
      },
    ],
  });

  await prisma.gymProduct.createMany({
    data: [
      {
        gymId: 'gym-1003',
        title: 'Whey Protein 2kg',
        description: 'High-quality isolate blend.',
        price: 75000,
        imageUrl: 'https://images.example.com/product-whey.jpg',
        isActive: true,
      },
      {
        gymId: 'gym-2001',
        title: 'Monthly Fat Loss Program',
        description: 'Training + nutrition + weekly check-ins.',
        price: 180000,
        isActive: true,
      },
      {
        gymId: 'gym-2002',
        title: 'Ladies Group Class Bundle',
        description: '12 group sessions package.',
        price: 120000,
        isActive: true,
      },
    ],
  });

  await prisma.gymTrainerMembership.createMany({
    data: [
      {
        gymId: 'gym-1003',
        trainerId: 'trainer-1',
        active: true,
      },
      {
        gymId: 'gym-1003',
        trainerId: 'trainer-2',
        active: true,
      },
      {
        gymId: 'gym-2001',
        trainerId: 'trainer-1',
        active: true,
      },
      {
        gymId: 'gym-2001',
        trainerId: 'trainer-3',
        active: true,
      },
      {
        gymId: 'gym-2002',
        trainerId: 'trainer-4',
        active: true,
      },
    ],
  });

  await prisma.gymMembership.createMany({
    data: [
      {
        gymId: 'gym-1003',
        userId: 'user-1',
      },
      {
        gymId: 'gym-2001',
        userId: 'user-1',
      },
      {
        gymId: 'gym-2002',
        userId: 'user-2',
      },
      {
        gymId: 'gym-2001',
        userId: 'user-3',
      },
    ],
  });

  await prisma.trainerHire.createMany({
    data: [
      {
        gymId: 'gym-1003',
        trainerId: 'trainer-1',
        userId: 'user-1',
        status: 'ACTIVE',
      },
      {
        gymId: 'gym-2002',
        trainerId: 'trainer-4',
        userId: 'user-2',
        status: 'ACTIVE',
      },
    ],
  });

  await prisma.gymRating.createMany({
    data: [
      {
        gymId: 'gym-1003',
        userId: 'user-1',
        rating: 5,
        comment: 'Great equipment and clean facility.',
      },
      {
        gymId: 'gym-2001',
        userId: 'user-3',
        rating: 4,
        comment: 'Good trainers and class schedule.',
      },
    ],
  });

  await prisma.trainerRating.createMany({
    data: [
      {
        gymId: 'gym-1003',
        trainerId: 'trainer-1',
        userId: 'user-1',
        rating: 5,
        comment: 'Excellent guidance and tracking.',
      },
      {
        gymId: 'gym-2002',
        trainerId: 'trainer-4',
        userId: 'user-2',
        rating: 4,
        comment: 'Very supportive and punctual.',
      },
    ],
  });
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (error) => {
    console.error(error);
    await prisma.$disconnect();
    process.exit(1);
  });
