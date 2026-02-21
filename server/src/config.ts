import dotenv from 'dotenv';
dotenv.config();

export const config = {
    // Server
    port: parseInt(process.env.PORT || '3000'),
    host: process.env.HOST || '0.0.0.0',
    nodeEnv: process.env.NODE_ENV || 'development',

    // Database
    databaseUrl: process.env.DATABASE_URL!,

    // JWT
    jwtSecret: process.env.JWT_SECRET || 'fallback-secret',
    jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',

    // Email (Brevo)
    brevoApiKey: process.env.BREVO_API_KEY || '',
    emailFrom: process.env.EMAIL_FROM || 'noreply@bluelaser.cn',
    emailFromName: process.env.EMAIL_FROM_NAME || 'Nanochat',

    // App
    appUrl: process.env.APP_URL || 'https://chat.bluelaser.cn',
    stunServer: process.env.STUN_SERVER || 'chat.bluelaser.cn:3478',

    // Admin
    adminUsername: process.env.ADMIN_USERNAME || 'admin',
    adminPassword: process.env.ADMIN_PASSWORD || 'admin123',
};
