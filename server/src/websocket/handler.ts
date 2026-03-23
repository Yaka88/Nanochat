import { Server, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { prisma } from '../db.js';
import { config } from '../config.js';
import { sendCallPush, initFirebase } from '../services/push.js';

interface JwtPayload {
    id: string;
    email?: string;
    isRegistered: boolean;
}

interface ConnectedUser {
    socket: Socket;
    userId: string;
    groupIds: string[];
}

// In-memory store for connected users
// Supports multiple concurrent sockets per user (e.g. foreground app + background service, or multiple devices)
const connectedUsers = new Map<string, Map<string, ConnectedUser>>();

// Pending offline timers: userId -> timeout handle
// When a socket disconnects we wait before marking the user offline
// so that brief reconnects (e.g. WiFi ↔ cellular) don't flash offline.
const pendingOfflineTimers = new Map<string, ReturnType<typeof setTimeout>>();

// Track recently cancelled calls so that a late-arriving call:request
// on the callee side can be dismissed.
const cancelledCalls = new Set<string>(); // "callerUserId -> targetUserId"

// Keep reference to the Socket.IO server for deferred broadcasts
let ioRef: Server | null = null;

// ========================================
// TURN Credential Generation
// ========================================

/**
 * Generate time-limited TURN credentials using the shared secret.
 * coturn validates these with --use-auth-secret / --static-auth-secret.
 */
function generateTurnCredentials(userId: string): { username: string; credential: string } {
    const ttl = config.turnCredentialTTL;
    const unixExpiry = Math.floor(Date.now() / 1000) + ttl;
    const username = `${unixExpiry}:${userId}`;
    const hmac = crypto.createHmac('sha1', config.turnSecret);
    hmac.update(username);
    const credential = hmac.digest('base64');
    return { username, credential };
}

function getIceServers(userId: string) {
    const { username, credential } = generateTurnCredentials(userId);
    const host = config.turnHost;
    const port = config.turnPort;
    return [
        { urls: `stun:${host}:${port}` },
        { urls: `turn:${host}:${port}?transport=udp`, username, credential },
        { urls: `turn:${host}:${port}?transport=tcp`, username, credential },
        { urls: 'stun:stun.l.google.com:19302' },
    ];
}

// ========================================
// Helpers
// ========================================

async function hasCommonGroup(userA: string, userB: string): Promise<boolean> {
    const member = await prisma.groupMember.findFirst({
        where: {
            userId: userA,
            group: {
                members: {
                    some: {
                        userId: userB,
                    },
                },
            },
        },
        select: { id: true },
    });

    return !!member;
}

async function loadGroupIds(userId: string): Promise<string[]> {
    try {
        const memberships = await prisma.groupMember.findMany({
            where: { userId },
            select: { groupId: true },
        });
        return memberships.map(m => m.groupId);
    } catch (error) {
        console.error(`Failed to load groups for user ${userId}:`, error);
        return [];
    }
}

// ========================================
// WebSocket Setup
// ========================================

export function setupWebSocket(io: Server) {
    ioRef = io;

    // Initialize Firebase for push notifications (fails gracefully if unconfigured)
    initFirebase();

    // On (re)start, reset ALL users to offline.  Only users who actually
    // connect a WebSocket will be marked online.
    prisma.user.updateMany({ data: { isOnline: false } }).catch((error) => {
        console.error('Failed to reset all users offline on startup:', error);
    });

    // Authentication middleware
    io.use(async (socket, next) => {
        try {
            const token = socket.handshake.auth.token || socket.handshake.headers.authorization?.replace('Bearer ', '');

            if (!token) {
                return next(new Error('Authentication required'));
            }

            const payload = jwt.verify(token, config.jwtSecret) as JwtPayload;
            const user = await prisma.user.findUnique({
                where: { id: payload.id },
                select: { id: true, isDisabled: true },
            });

            if (!user) {
                return next(new Error('User not found'));
            }

            if (user.isDisabled) {
                return next(new Error('Account is disabled'));
            }

            // Save deviceId from the handshake
            const deviceId = socket.handshake.auth.deviceId || socket.handshake.headers['x-device-id'];
            if (deviceId) {
                socket.data.deviceId = deviceId;
            }

            socket.data.user = payload;
            next();
        } catch (error) {
            next(new Error('Invalid token'));
        }
    });

    io.on('connection', async (socket) => {
        const userId = socket.data.user.id;
        console.log(`🔌 User connected: ${userId}`);

        // Cancel any pending offline timer for this user (reconnected in time)
        const pendingTimer = pendingOfflineTimers.get(userId);
        if (pendingTimer) {
            clearTimeout(pendingTimer);
            pendingOfflineTimers.delete(userId);
        }

        // Get user's groups
        let groupIds = await loadGroupIds(userId);

        // Join group rooms
        for (const groupId of groupIds) {
            socket.join(`group:${groupId}`);
        }

        // Store connected user
        if (!connectedUsers.has(userId)) {
            connectedUsers.set(userId, new Map());
        }
        
        // Before adding the new socket, check if we need to enforce device singleness
        const currentDeviceId = socket.data.deviceId;
        if (currentDeviceId) {
            const userSockets = connectedUsers.get(userId)!;
            for (const [sid, connectedUser] of userSockets.entries()) {
                const existingDeviceId = connectedUser.socket.data.deviceId;
                // If the existing socket has a DIFFERENT device ID, kick it
                if (existingDeviceId && existingDeviceId !== currentDeviceId) {
                    connectedUser.socket.emit('force_logout', { message: '您的账号已在其他设备登录' });
                    connectedUser.socket.disconnect(true);
                    userSockets.delete(sid);
                }
            }
        }

        connectedUsers.get(userId)!.set(socket.id, {
            socket,
            userId,
            groupIds,
        });

        // Update user online status
        try {
            await prisma.user.update({
                where: { id: userId },
                data: { 
                    isOnline: true, 
                    lastOnlineAt: new Date(),
                    ...(currentDeviceId ? { deviceId: currentDeviceId } : {})
                },
            });
        } catch (error) {
            console.error(`Failed to set online status for user ${userId}:`, error);
        }

        // Broadcast online status to groups
        for (const groupId of groupIds) {
            socket.to(`group:${groupId}`).emit('user:online', {
                userId,
                groupId,
            });
        }

        // Send current presence snapshot to the newly connected user.
        // Use the in-memory connectedUsers map (authoritative real-time source)
        // instead of DB isOnline field which can be stale.
        const onlineUserIds: string[] = [];
        for (const groupId of groupIds) {
            const groupMembers = await prisma.groupMember.findMany({
                where: {
                    groupId,
                    userId: { not: userId },
                },
                select: { userId: true },
            });
            for (const gm of groupMembers) {
                if (connectedUsers.has(gm.userId) && !onlineUserIds.includes(gm.userId)) {
                    onlineUserIds.push(gm.userId);
                }
            }
        }

        socket.emit('presence:snapshot', { onlineUserIds });

        // ========================================
        // ICE Server Configuration
        // ========================================

        socket.on('get:ice-servers', (_, callback) => {
            const iceServers = getIceServers(userId);
            if (typeof callback === 'function') {
                callback({ iceServers });
            } else {
                socket.emit('ice-servers', { iceServers });
            }
        });

        // ========================================
        // Dynamic Group Room Management
        // ========================================

        // Client emits this after joining a group (QR scan, etc.)
        socket.on('group:joined', async (data: { groupId: string }) => {
            if (!data?.groupId) return;
            const gid = data.groupId;

            // Verify user is actually a member
            const membership = await prisma.groupMember.findFirst({
                where: { userId, groupId: gid },
                select: { id: true },
            });
            if (!membership) return;

            // Join the socket room
            socket.join(`group:${gid}`);

            // Update in-memory groupIds
            if (!groupIds.includes(gid)) {
                groupIds.push(gid);
            }
            const userSockets = connectedUsers.get(userId);
            if (userSockets) {
                const entry = userSockets.get(socket.id);
                if (entry) {
                    entry.groupIds = groupIds;
                }
            }

            // Broadcast online to the newly joined group
            socket.to(`group:${gid}`).emit('user:online', { userId, groupId: gid });

            // Send presence snapshot for this group's members (from DB)
            const groupMembers = await prisma.groupMember.findMany({
                where: {
                    groupId: gid,
                    userId: { not: userId },
                    user: { isOnline: true },
                },
                select: { userId: true },
            });
            socket.emit('presence:snapshot', { onlineUserIds: groupMembers.map((m) => m.userId) });
        });

        // Refresh all group rooms (e.g., after app resume)
        socket.on('groups:refresh', async () => {
            const freshGroupIds = await loadGroupIds(userId);

            // Leave rooms no longer a member of
            for (const oldGid of groupIds) {
                if (!freshGroupIds.includes(oldGid)) {
                    socket.leave(`group:${oldGid}`);
                }
            }
            // Join new rooms
            for (const newGid of freshGroupIds) {
                if (!groupIds.includes(newGid)) {
                    socket.join(`group:${newGid}`);
                    socket.to(`group:${newGid}`).emit('user:online', { userId, groupId: newGid });
                }
            }

            groupIds = freshGroupIds;
            const userSockets = connectedUsers.get(userId);
            if (userSockets) {
                const entry = userSockets.get(socket.id);
                if (entry) {
                    entry.groupIds = groupIds;
                }
            }

            // Send full presence snapshot using in-memory connectedUsers (authoritative)
            const refreshOnlineIds: string[] = [];
            for (const gid of groupIds) {
                const gMembers = await prisma.groupMember.findMany({
                    where: {
                        groupId: gid,
                        userId: { not: userId },
                    },
                    select: { userId: true },
                });
                for (const gm of gMembers) {
                    if (connectedUsers.has(gm.userId) && !refreshOnlineIds.includes(gm.userId)) {
                        refreshOnlineIds.push(gm.userId);
                    }
                }
            }
            socket.emit('presence:snapshot', { onlineUserIds: refreshOnlineIds });
        });

        // ========================================
        // Call Signaling Events
        // ========================================

        const ensureAuthorizedTarget = async (
            targetUserId: string | undefined,
            eventType: 'call' | 'signal'
        ): Promise<string | null> => {
            if (!targetUserId || targetUserId === userId) {
                socket.emit('call:error', { message: `Invalid ${eventType} target` });
                return null;
            }

            const authorized = await hasCommonGroup(userId, targetUserId);
            if (!authorized) {
                socket.emit('call:error', { message: `Not allowed to ${eventType} this user` });
                return null;
            }

            return targetUserId;
        };

        // Request a call
        socket.on('call:request', async (data: { targetUserId: string; isVideo?: boolean }) => {
            if (!data?.targetUserId || data.targetUserId === userId) {
                socket.emit('call:error', { message: 'Invalid call target' });
                return;
            }

            const authorized = await hasCommonGroup(userId, data.targetUserId);
            if (!authorized) {
                socket.emit('call:error', { message: 'Not allowed to call this user' });
                return;
            }

            // Check if this specific call was recently cancelled
            const cancelKey = `${userId}->${data.targetUserId}`;
            if (cancelledCalls.has(cancelKey)) {
                // The caller hung up before we could process the request
                cancelledCalls.delete(cancelKey);
                return;
            }

            const caller = await prisma.user.findUnique({
                where: { id: userId },
                select: { nickname: true },
            });
            const callerName = caller?.nickname || 'Unknown';
            const isVideo = data.isVideo ?? true;

            const targetSockets = connectedUsers.get(data.targetUserId);
            if (targetSockets && targetSockets.size > 0) {
                for (const target of targetSockets.values()) {
                    target.socket.emit('call:request', {
                        callerUserId: userId,
                        callerName,
                        isVideo,
                    });
                }
                // Also send push as a safety net – the WebSocket may be stale
                // (connected in memory but the device dropped it).
                sendCallPush(data.targetUserId, callerName, userId, isVideo).catch(() => {});
            } else {
                // No active WebSocket – push notification is the only way
                const pushed = await sendCallPush(data.targetUserId, callerName, userId, isVideo);
                if (!pushed) {
                    socket.emit('call:error', { message: 'User is offline and unreachable' });
                }
            }
        });

        // Accept call
        socket.on('call:accept', async (data: { targetUserId: string }) => {
            const targetUserId = await ensureAuthorizedTarget(data?.targetUserId, 'call');
            if (!targetUserId) return;

            const targetSockets = connectedUsers.get(targetUserId);
            if (targetSockets) {
                for (const target of targetSockets.values()) {
                    target.socket.emit('call:accept', { 
                        fromUserId: userId,
                        fromSocketId: socket.id 
                    });
                }
            }

            // Tell my OTHER devices to stop ringing CallKit because I answered here
            const mySockets = connectedUsers.get(userId);
            if (mySockets) {
                for (const [socketId, myClient] of mySockets.entries()) {
                    if (socketId !== socket.id) {
                        myClient.socket.emit('call:answered_elsewhere', { fromUserId: targetUserId });
                    }
                }
            }
        });

        // Reject call
        socket.on('call:reject', async (data: { targetUserId: string; reason?: string }) => {
            const targetUserId = await ensureAuthorizedTarget(data?.targetUserId, 'call');
            if (!targetUserId) return;

            const targetSockets = connectedUsers.get(targetUserId);
            if (targetSockets) {
                for (const target of targetSockets.values()) {
                    target.socket.emit('call:reject', { fromUserId: userId, reason: data.reason });
                }
            }
        });

        // End call
        socket.on('call:end', async (data: { targetUserId: string }) => {
            const targetUserId = await ensureAuthorizedTarget(data?.targetUserId, 'call');
            if (!targetUserId) return;

            // Record cancellation so a late-arriving call:request can be
            // suppressed on the callee side when they check.
            cancelledCalls.add(`${userId}->${targetUserId}`);
            // Auto-clean after 60 seconds
            setTimeout(() => cancelledCalls.delete(`${userId}->${targetUserId}`), 60_000);

            const targetSockets = connectedUsers.get(targetUserId);
            if (targetSockets) {
                for (const target of targetSockets.values()) {
                    target.socket.emit('call:end', { fromUserId: userId });
                }
            }
        });

        // ========================================
        // WebRTC Signaling
        // ========================================

        // Helper to route signaling to either a specific socket or all of a user's sockets
        const routeSignalToTarget = (targetUserId: string, targetSocketId: string | undefined, event: string, payload: any) => {
            const targetSockets = connectedUsers.get(targetUserId);
            if (!targetSockets) return;
            
            if (targetSocketId && targetSockets.has(targetSocketId)) {
                // Route explicitly to the socket that accepted/initiated the call
                targetSockets.get(targetSocketId)!.socket.emit(event, payload);
            } else {
                // Fallback: broadcast to all sockets for this user
                for (const target of targetSockets.values()) {
                    target.socket.emit(event, payload);
                }
            }
        };

        // SDP Offer
        socket.on('signal:offer', async (data: { targetUserId: string; targetSocketId?: string; sdp?: string; type?: string }) => {
            const targetUserId = await ensureAuthorizedTarget(data?.targetUserId, 'signal');
            if (!targetUserId) return;

            routeSignalToTarget(targetUserId, data.targetSocketId, 'signal:offer', {
                fromUserId: userId,
                fromSocketId: socket.id, // Identify where this offer came from
                sdp: data.sdp,
                type: data.type || 'offer',
            });
        });

        // SDP Answer
        socket.on('signal:answer', async (data: { targetUserId: string; targetSocketId?: string; sdp?: string; type?: string }) => {
            const targetUserId = await ensureAuthorizedTarget(data?.targetUserId, 'signal');
            if (!targetUserId) return;

            routeSignalToTarget(targetUserId, data.targetSocketId, 'signal:answer', {
                fromUserId: userId,
                fromSocketId: socket.id,
                sdp: data.sdp,
                type: data.type || 'answer',
            });
        });

        // ICE Candidate
        socket.on('signal:ice', async (data: { targetUserId: string; targetSocketId?: string; candidate: RTCIceCandidateInit }) => {
            const targetUserId = await ensureAuthorizedTarget(data?.targetUserId, 'signal');
            if (!targetUserId) return;

            if (!data?.candidate) {
                socket.emit('call:error', { message: 'Invalid ICE candidate' });
                return;
            }

            routeSignalToTarget(targetUserId, data.targetSocketId, 'signal:ice', { 
                fromUserId: userId, 
                fromSocketId: socket.id,
                candidate: data.candidate 
            });
        });

        // ========================================
        // Explicit Logout (only way to go offline)
        // ========================================

        socket.on('user:logout', async () => {
            console.log(`🔓 User explicitly logged out: ${userId}`);

            // Remove from connected users
            const userSockets = connectedUsers.get(userId);
            if (userSockets) {
                userSockets.delete(socket.id);
                if (userSockets.size === 0) {
                    connectedUsers.delete(userId);
                }
            }

            // Set user offline only on explicit logout
            try {
                await prisma.user.update({
                    where: { id: userId },
                    data: { isOnline: false, lastOnlineAt: new Date() },
                });
            } catch (error) {
                console.error(`Failed to set offline status for user ${userId}:`, error);
            }

            // Broadcast offline status
            for (const groupId of groupIds) {
                socket.to(`group:${groupId}`).emit('user:offline', {
                    userId,
                    groupId,
                });
            }

            socket.disconnect(true);
        });

        // ========================================
        // Disconnect Handling
        // ========================================

        socket.on('disconnect', async () => {
            console.log(`🔌 User disconnected: ${userId}`);

            // Only clean up in-memory entry if this socket is still the active one
            const userSockets = connectedUsers.get(userId);
            if (!userSockets || !userSockets.has(socket.id)) {
                return;
            }

            // Remove from connected-users map immediately so call:request
            // won't try to reach an unreachable socket.
            userSockets.delete(socket.id);
            if (userSockets.size === 0) {
                connectedUsers.delete(userId);
            } else {
                // User still has other connected sockets (e.g. background service), do not mark offline
                return;
            }

            // Keep user online across transient/background disconnects.
            // Use a delayed timer: if the user doesn't reconnect within 15 seconds,
            // mark them offline in DB and broadcast user:offline.
            const offlineTimer = setTimeout(async () => {
                pendingOfflineTimers.delete(userId);

                // If the user reconnected in the meantime, skip
                if (connectedUsers.has(userId)) return;

                // Mark offline in DB
                try {
                    await prisma.user.update({
                        where: { id: userId },
                        data: { isOnline: false, lastOnlineAt: new Date() },
                    });
                } catch (error) {
                    console.error(`Failed to set offline status for user ${userId}:`, error);
                }

                // Broadcast offline to all groups
                for (const groupId of groupIds) {
                    io.to(`group:${groupId}`).emit('user:offline', {
                        userId,
                        groupId,
                    });
                }

                console.log(`⏰ User ${userId} marked offline after 15s grace period`);
            }, 15_000);

            pendingOfflineTimers.set(userId, offlineTimer);
        });
    });
}

export function getOnlineUserIds(): string[] {
    return Array.from(connectedUsers.keys());
}

export function isUserOnline(userId: string): boolean {
    return connectedUsers.has(userId);
}

// Helper function to notify user of new message
export function notifyNewMessage(receiverId: string, message: any) {
    const receiverSockets = connectedUsers.get(receiverId);
    if (receiverSockets) {
        for (const receiver of receiverSockets.values()) {
            receiver.socket.emit('message:new', message);
        }
    }
}

// Mark all users offline – call during graceful shutdown
export async function markAllUsersOffline() {
    // Cancel all pending timers
    for (const timer of pendingOfflineTimers.values()) {
        clearTimeout(timer);
    }
    pendingOfflineTimers.clear();
    connectedUsers.clear();

    await prisma.user.updateMany({
        data: { isOnline: false, lastOnlineAt: new Date() },
    });
}

// Kick all sockets of a user that do NOT match the given deviceId
export function forceLogoutOtherDevices(userId: string, activeDeviceId: string) {
    const userSockets = connectedUsers.get(userId);
    if (!userSockets) return;

    for (const [socketId, userState] of userSockets.entries()) {
        const socketDevice = userState.socket.data.deviceId;
        if (socketDevice && socketDevice !== activeDeviceId) {
            userState.socket.emit('force_logout', { message: '您的账号已在其他设备登录' });
            userState.socket.disconnect(true);
            userSockets.delete(socketId);
        }
    }
}

interface RTCIceCandidateInit {
    candidate?: string;
    sdpMLineIndex?: number;
    sdpMid?: string;
}
