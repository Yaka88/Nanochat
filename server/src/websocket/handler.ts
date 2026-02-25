import { Server, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { prisma } from '../db.js';
import { config } from '../config.js';

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
const connectedUsers = new Map<string, ConnectedUser>();

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
    prisma.user.updateMany({ data: { isOnline: true } }).catch((error) => {
        console.error('Failed to set all users online on startup:', error);
    });

    // Authentication middleware
    io.use(async (socket, next) => {
        try {
            const token = socket.handshake.auth.token || socket.handshake.headers.authorization?.replace('Bearer ', '');

            if (!token) {
                return next(new Error('Authentication required'));
            }

            const payload = jwt.verify(token, config.jwtSecret) as JwtPayload;
            socket.data.user = payload;
            next();
        } catch (error) {
            next(new Error('Invalid token'));
        }
    });

    io.on('connection', async (socket) => {
        const userId = socket.data.user.id;
        console.log(`🔌 User connected: ${userId}`);

        // Get user's groups
        let groupIds = await loadGroupIds(userId);

        // Join group rooms
        for (const groupId of groupIds) {
            socket.join(`group:${groupId}`);
        }

        // Store connected user
        connectedUsers.set(userId, {
            socket,
            userId,
            groupIds,
        });

        // Update user online status
        try {
            await prisma.user.update({
                where: { id: userId },
                data: { isOnline: true, lastOnlineAt: new Date() },
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
        // Query from DB because users stay online even without a socket.
        const groupMates = await prisma.groupMember.findMany({
            where: {
                groupId: { in: groupIds },
                userId: { not: userId },
                user: { isOnline: true },
            },
            select: { userId: true },
            distinct: ['userId'],
        });
        const onlineUserIds = groupMates.map((m) => m.userId);

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
            const entry = connectedUsers.get(userId);
            if (entry && entry.socket.id === socket.id) {
                entry.groupIds = groupIds;
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
            const entry = connectedUsers.get(userId);
            if (entry && entry.socket.id === socket.id) {
                entry.groupIds = groupIds;
            }

            // Send full presence snapshot (from DB)
            const allGroupMates = await prisma.groupMember.findMany({
                where: {
                    groupId: { in: groupIds },
                    userId: { not: userId },
                    user: { isOnline: true },
                },
                select: { userId: true },
                distinct: ['userId'],
            });
            socket.emit('presence:snapshot', { onlineUserIds: allGroupMates.map((m) => m.userId) });
        });

        // ========================================
        // Call Signaling Events
        // ========================================

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

            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                const caller = await prisma.user.findUnique({
                    where: { id: userId },
                    select: { nickname: true },
                });

                target.socket.emit('call:request', {
                    callerUserId: userId,
                    callerName: caller?.nickname || 'Unknown',
                    isVideo: data.isVideo ?? true,
                });
            } else {
                socket.emit('call:error', { message: 'User is offline' });
            }
        });

        // Accept call
        socket.on('call:accept', (data: { targetUserId: string }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('call:accept', { fromUserId: userId });
            }
        });

        // Reject call
        socket.on('call:reject', (data: { targetUserId: string; reason?: string }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('call:reject', { fromUserId: userId, reason: data.reason });
            }
        });

        // End call
        socket.on('call:end', (data: { targetUserId: string }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('call:end', { fromUserId: userId });
            }
        });

        // ========================================
        // WebRTC Signaling
        // ========================================

        // SDP Offer
        socket.on('signal:offer', (data: { targetUserId: string; sdp?: string; type?: string }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('signal:offer', {
                    fromUserId: userId,
                    sdp: data.sdp,
                    type: data.type || 'offer',
                });
            }
        });

        // SDP Answer
        socket.on('signal:answer', (data: { targetUserId: string; sdp?: string; type?: string }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('signal:answer', {
                    fromUserId: userId,
                    sdp: data.sdp,
                    type: data.type || 'answer',
                });
            }
        });

        // ICE Candidate
        socket.on('signal:ice', (data: { targetUserId: string; candidate: RTCIceCandidateInit }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('signal:ice', { fromUserId: userId, candidate: data.candidate });
            }
        });

        // ========================================
        // Explicit Logout (only way to go offline)
        // ========================================

        socket.on('user:logout', async () => {
            console.log(`🔓 User explicitly logged out: ${userId}`);

            // Remove from connected users
            const current = connectedUsers.get(userId);
            if (current?.socket.id === socket.id) {
                connectedUsers.delete(userId);
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
            const current = connectedUsers.get(userId);
            if (current?.socket.id !== socket.id) {
                return;
            }

            // Remove from connected users map but keep the user marked as ONLINE
            // in the database. Users stay online unless they explicitly log out
            // or account is deleted.
            connectedUsers.delete(userId);

            // Update lastOnlineAt timestamp but do NOT set isOnline to false
            try {
                await prisma.user.update({
                    where: { id: userId },
                    data: { lastOnlineAt: new Date() },
                });
            } catch (error) {
                console.error(`Failed to update lastOnlineAt for user ${userId}:`, error);
            }

            // Do NOT broadcast user:offline — user remains "online"
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
    const receiver = connectedUsers.get(receiverId);
    if (receiver) {
        receiver.socket.emit('message:new', message);
    }
}

interface RTCIceCandidateInit {
    candidate?: string;
    sdpMLineIndex?: number;
    sdpMid?: string;
}
