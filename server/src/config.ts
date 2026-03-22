import dotenv from 'dotenv';
dotenv.config();

const nodeEnv = process.env.NODE_ENV || 'development';
const isProduction = nodeEnv === 'production';

function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value || value.trim() === '') {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value;
}

function rejectInsecureDefault(name: string, value: string, insecureDefault: string): string {
    if (isProduction && value === insecureDefault) {
        throw new Error(`${name} must be explicitly configured in production`);
    }
    return value;
}

const jwtSecret = rejectInsecureDefault(
    'JWT_SECRET',
    process.env.JWT_SECRET || 'fallback-secret',
    'fallback-secret'
);

const turnSecret = rejectInsecureDefault(
    'TURN_SECRET',
    process.env.TURN_SECRET || 'nanochat-turn-secret',
    'nanochat-turn-secret'
);

const adminPassword = rejectInsecureDefault(
    'ADMIN_PASSWORD',
    process.env.ADMIN_PASSWORD || 'admin123',
    'admin123'
);

export const config = {
    // Server
    port: parseInt(process.env.PORT || '3000'),
    host: process.env.HOST || '0.0.0.0',
    nodeEnv,

    // Database
    databaseUrl: requireEnv('DATABASE_URL'),

    // JWT
    jwtSecret,
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
    turnSecret,
    turnCredentialTTL: parseInt(process.env.TURN_CREDENTIAL_TTL || '86400'), // 24h

    // Admin
    adminUsername: process.env.ADMIN_USERNAME || 'admin',
    adminPassword,

    // FCM (Firebase Cloud Messaging) – push notifications
    fcmServiceAccountPath: process.env.FCM_SERVICE_ACCOUNT_PATH || '',
};
