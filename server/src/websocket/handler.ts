import { Server, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
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

export function setupWebSocket(io: Server) {
    prisma.user.updateMany({ data: { isOnline: false } }).catch((error) => {
        console.error('Failed to reset online status on startup:', error);
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
        let groupIds: string[] = [];
        try {
            const memberships = await prisma.groupMember.findMany({
                where: { userId },
                select: { groupId: true },
            });
            groupIds = memberships.map(m => m.groupId);
        } catch (error) {
            console.error(`Failed to load groups for user ${userId}:`, error);
        }

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

        // Send current presence snapshot to the newly connected user
        const onlineUserIds = Array.from(connectedUsers.values())
            .filter((u) => u.userId !== userId && u.groupIds.some((gid) => groupIds.includes(gid)))
            .map((u) => u.userId);

        socket.emit('presence:snapshot', { onlineUserIds });

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
        // Disconnect Handling
        // ========================================

        socket.on('disconnect', async () => {
            console.log(`🔌 User disconnected: ${userId}`);

            // Only clean up if this socket is still the active one for this user
            // (prevents race condition when user reconnects before old socket disconnects)
            const current = connectedUsers.get(userId);
            if (current?.socket.id !== socket.id) {
                return;
            }

            // Remove from connected users
            connectedUsers.delete(userId);

            // Update user offline status
            try {
                await prisma.user.update({
                    where: { id: userId },
                    data: { isOnline: false, lastOnlineAt: new Date() },
                });
            } catch (error) {
                console.error(`Failed to set offline status for user ${userId}:`, error);
            }

            // Broadcast offline status to groups
            for (const groupId of groupIds) {
                socket.to(`group:${groupId}`).emit('user:offline', {
                    userId,
                    groupId,
                });
            }
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
