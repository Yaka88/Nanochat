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

    // TURN / STUN
    turnHost: process.env.TURN_HOST || 'chat.bluelaser.cn',
    turnPort: parseInt(process.env.TURN_PORT || '3478'),
    turnSecret: process.env.TURN_SECRET || 'nanochat-turn-secret',
    turnCredentialTTL: parseInt(process.env.TURN_CREDENTIAL_TTL || '86400'), // 24h

    // Admin
    adminUsername: process.env.ADMIN_USERNAME || 'admin',
    adminPassword: process.env.ADMIN_PASSWORD || 'admin123',
};
