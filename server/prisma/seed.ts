import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
    console.log('🌱 Seeding database...');

    // Create system config
    const configs = [
        { key: 'membercount', value: '6', description: '每个家庭最大成员数' },
        { key: 'groupcount', value: '6', description: '每个账号最大可加入/创建的家庭数' },
        { key: 'voice_msg_max_seconds', value: '60', description: '语音消息最长秒数' },
    ];

    for (const cfg of configs) {
        await prisma.systemConfig.upsert({
            where: { key: cfg.key },
            update: { value: cfg.value, description: cfg.description },
            create: cfg,
        });
    }
    console.log('✅ System config created');

    // Create default admin
    const adminPassword = process.env.ADMIN_PASSWORD || 'admin123';
    const passwordHash = await bcrypt.hash(adminPassword, 10);

    await prisma.admin.upsert({
        where: { username: 'admin' },
        update: { passwordHash },
        create: {
            username: 'admin',
            passwordHash,
        },
    });
    console.log('✅ Admin user created (username: admin)');

    console.log('🎉 Database seeding completed');
}

main()
    .catch((e) => {
        console.error('❌ Seeding failed:', e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
