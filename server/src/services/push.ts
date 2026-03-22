import admin from 'firebase-admin';
import { readFileSync } from 'fs';
import { prisma } from '../db.js';
import { config } from '../config.js';

let firebaseInitialized = false;

/**
 * Initialize Firebase Admin SDK.
 * Call once at server startup. Silently skips if no service account is configured.
 */
export function initFirebase(): boolean {
    if (firebaseInitialized) return true;

    const saPath = config.fcmServiceAccountPath;
    if (!saPath) {
        console.warn('⚠️  FCM_SERVICE_ACCOUNT_PATH not set – push notifications disabled');
        return false;
    }

    try {
        const serviceAccount = JSON.parse(readFileSync(saPath, 'utf-8'));
        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
        });
        firebaseInitialized = true;
        console.log('🔔 Firebase Admin SDK initialized – push notifications enabled');
        return true;
    } catch (error) {
        console.error('❌ Failed to initialize Firebase Admin SDK:', error);
        return false;
    }
}

/**
 * Send a high-priority FCM data message to trigger incoming call UI.
 * Works for both Android (FCM) and iOS (APNs via FCM).
 */
export async function sendCallPush(
    targetUserId: string,
    callerName: string,
    callerUserId: string,
    isVideo: boolean
): Promise<boolean> {
    if (!firebaseInitialized) return false;

    try {
        const user = await prisma.user.findUnique({
            where: { id: targetUserId },
            select: { deviceToken: true, pushPlatform: true },
        });

        if (!user?.deviceToken) {
            console.log(`📵 No push token for user ${targetUserId}`);
            return false;
        }

        const message: admin.messaging.Message = {
            token: user.deviceToken,
            data: {
                type: 'call_incoming',
                callerUserId,
                callerName,
                isVideo: isVideo ? 'true' : 'false',
                timestamp: Date.now().toString(),
            },
            // Android: high priority to wake device
            android: {
                priority: 'high',
                ttl: 30000, // 30 seconds – calls are time-sensitive
            },
            // iOS: use content-available for background processing
            // and set priority to high for immediate delivery
            apns: {
                headers: {
                    'apns-priority': '10',
                    'apns-push-type': 'voip',
                },
                payload: {
                    aps: {
                        'content-available': 1,
                    },
                },
            },
        };

        const response = await admin.messaging().send(message);
        console.log(`🔔 Push sent to ${targetUserId}: ${response}`);
        return true;
    } catch (error: any) {
        // If token is invalid, clear it from DB
        if (
            error?.code === 'messaging/registration-token-not-registered' ||
            error?.code === 'messaging/invalid-registration-token'
        ) {
            console.warn(`🗑️ Clearing invalid token for user ${targetUserId}`);
            await prisma.user.update({
                where: { id: targetUserId },
                data: { deviceToken: null, pushPlatform: null },
            }).catch(() => {});
        }
        console.error(`❌ Push failed for ${targetUserId}:`, error?.message || error);
        return false;
    }
}

/**
 * Save or update a user's push notification token.
 */
export async function saveDeviceToken(
    userId: string,
    token: string,
    platform: string
): Promise<void> {
    await prisma.user.update({
        where: { id: userId },
        data: {
            deviceToken: token,
            pushPlatform: platform, // 'android' or 'ios'
        },
    });
}
