const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017/gymos';
const dbName = process.env.MONGODB_DB_NAME || inferDbName(uri) || 'gymos';

async function main() {
  const client = new MongoClient(uri);
  await client.connect();

  try {
    const db = client.db(dbName);

    await Promise.all([
      db.collection('phoneVerificationSessions').deleteMany({}),
      db.collection('trainerRatings').deleteMany({}),
      db.collection('gymRatings').deleteMany({}),
      db.collection('trainerHires').deleteMany({}),
      db.collection('gymProducts').deleteMany({}),
      db.collection('gymFacilities').deleteMany({}),
      db.collection('gymTrainerMemberships').deleteMany({}),
      db.collection('gymMemberships').deleteMany({}),
      db.collection('gyms').deleteMany({}),
      db.collection('platformSubscriptions').deleteMany({}),
      db.collection('gymApplications').deleteMany({}),
      db.collection('userAccounts').deleteMany({}),
    ]);

    const now = new Date();

    await db.collection('userAccounts').insertMany([
      {
        id: 'acc-admin-1',
        phoneNumber: '9647700000001',
        displayName: 'Platform Admin',
        role: 'ADMIN',
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'acc-owner-1',
        phoneNumber: '9647700000002',
        displayName: 'Demo Owner',
        role: 'OWNER',
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'acc-trainer-1',
        phoneNumber: '9647700000003',
        displayName: 'Demo Trainer',
        role: 'TRAINER',
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'acc-user-1',
        phoneNumber: '9647700000004',
        displayName: 'Demo User',
        role: 'USER',
        createdAt: now,
        updatedAt: now,
      },
    ]);

    await db.collection('gymApplications').insertMany([
      {
        id: 'gym-1001',
        gymName: 'Power Zone Fitness',
        ownerName: 'Khaled Alotaibi',
        ownerUserId: 'owner-1001',
        city: 'Riyadh',
        requestedAt: new Date('2026-02-09T09:20:00.000Z'),
        status: 'PENDING',
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'gym-1002',
        gymName: 'Elite Ladies Gym',
        ownerName: 'Nora Alharbi',
        ownerUserId: 'owner-1002',
        city: 'Jeddah',
        requestedAt: new Date('2026-02-10T14:05:00.000Z'),
        status: 'PENDING',
        createdAt: now,
        updatedAt: now,
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
        createdAt: now,
        updatedAt: now,
      },
    ]);

    await db.collection('platformSubscriptions').insertMany([
      {
        id: 'sub-501',
        gymId: 'gym-1003',
        gymName: 'Iron Core Club',
        planName: 'Business Pro',
        membersLimit: 1500,
        monthlyPrice: 1299,
        nextBillingDate: new Date('2026-03-01T00:00:00.000Z'),
        status: 'ACTIVE',
        createdAt: now,
        updatedAt: now,
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
        createdAt: now,
        updatedAt: now,
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
        createdAt: now,
        updatedAt: now,
      },
    ]);

    await db.collection('gyms').insertMany([
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
        createdAt: now,
        updatedAt: now,
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
        createdAt: now,
        updatedAt: now,
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
        createdAt: now,
        updatedAt: now,
      },
    ]);

    await db.collection('gymFacilities').insertMany([
      {
        id: 'fac-1',
        gymId: 'gym-1003',
        name: 'Powerlifting Zone',
        description: 'Competition racks and calibrated plates.',
        imageUrl: 'https://images.example.com/facility-powerlifting.jpg',
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'fac-2',
        gymId: 'gym-1003',
        name: 'Recovery Studio',
        description: 'Stretching and mobility dedicated room.',
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'fac-3',
        gymId: 'gym-2001',
        name: 'Cardio Hall',
        description: 'Treadmills, bikes, and rowers with panoramic view.',
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'fac-4',
        gymId: 'gym-2002',
        name: 'Pilates Studio',
        description: 'Small-group reformer and mat pilates sessions.',
        createdAt: now,
        updatedAt: now,
      },
    ]);

    await db.collection('gymProducts').insertMany([
      {
        id: 'prd-1',
        gymId: 'gym-1003',
        title: 'Whey Protein 2kg',
        description: 'High-quality isolate blend.',
        price: 75000,
        imageUrl: 'https://images.example.com/product-whey.jpg',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'prd-2',
        gymId: 'gym-2001',
        title: 'Monthly Fat Loss Program',
        description: 'Training + nutrition + weekly check-ins.',
        price: 180000,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'prd-3',
        gymId: 'gym-2002',
        title: 'Ladies Group Class Bundle',
        description: '12 group sessions package.',
        price: 120000,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      },
    ]);

    await db.collection('gymTrainerMemberships').insertMany([
      {
        id: 'tm-1',
        gymId: 'gym-1003',
        trainerId: 'trainer-1',
        joinedAt: now,
        active: true,
      },
      {
        id: 'tm-2',
        gymId: 'gym-1003',
        trainerId: 'trainer-2',
        joinedAt: now,
        active: true,
      },
      {
        id: 'tm-3',
        gymId: 'gym-2001',
        trainerId: 'trainer-1',
        joinedAt: now,
        active: true,
      },
      {
        id: 'tm-4',
        gymId: 'gym-2001',
        trainerId: 'trainer-3',
        joinedAt: now,
        active: true,
      },
      {
        id: 'tm-5',
        gymId: 'gym-2002',
        trainerId: 'trainer-4',
        joinedAt: now,
        active: true,
      },
    ]);

    await db.collection('gymMemberships').insertMany([
      {
        id: 'gm-1',
        gymId: 'gym-1003',
        userId: 'user-1',
        joinedAt: now,
      },
      {
        id: 'gm-2',
        gymId: 'gym-2001',
        userId: 'user-1',
        joinedAt: now,
      },
      {
        id: 'gm-3',
        gymId: 'gym-2002',
        userId: 'user-2',
        joinedAt: now,
      },
      {
        id: 'gm-4',
        gymId: 'gym-2001',
        userId: 'user-3',
        joinedAt: now,
      },
    ]);

    await db.collection('trainerHires').insertMany([
      {
        id: 'hire-1',
        gymId: 'gym-1003',
        trainerId: 'trainer-1',
        userId: 'user-1',
        status: 'ACTIVE',
        hiredAt: now,
        endedAt: null,
      },
      {
        id: 'hire-2',
        gymId: 'gym-2002',
        trainerId: 'trainer-4',
        userId: 'user-2',
        status: 'ACTIVE',
        hiredAt: now,
        endedAt: null,
      },
    ]);

    await db.collection('gymRatings').insertMany([
      {
        id: 'gr-1',
        gymId: 'gym-1003',
        userId: 'user-1',
        rating: 5,
        comment: 'Great equipment and clean facility.',
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'gr-2',
        gymId: 'gym-2001',
        userId: 'user-3',
        rating: 4,
        comment: 'Good trainers and class schedule.',
        createdAt: now,
        updatedAt: now,
      },
    ]);

    await db.collection('trainerRatings').insertMany([
      {
        id: 'tr-1',
        gymId: 'gym-1003',
        trainerId: 'trainer-1',
        userId: 'user-1',
        rating: 5,
        comment: 'Excellent guidance and tracking.',
        createdAt: now,
        updatedAt: now,
      },
      {
        id: 'tr-2',
        gymId: 'gym-2002',
        trainerId: 'trainer-4',
        userId: 'user-2',
        rating: 4,
        comment: 'Very supportive and punctual.',
        createdAt: now,
        updatedAt: now,
      },
    ]);
  } finally {
    await client.close();
  }
}

function inferDbName(value) {
  try {
    const parsed = new URL(value);
    const pathname = parsed.pathname.replace(/^\//, '').trim();
    return pathname.length > 0 ? pathname : null;
  } catch {
    return null;
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
