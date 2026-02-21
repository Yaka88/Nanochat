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

export function setupWebSocket(io: Server) {
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
        const memberships = await prisma.groupMember.findMany({
            where: { userId },
            select: { groupId: true },
        });
        const groupIds = memberships.map(m => m.groupId);

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
        await prisma.user.update({
            where: { id: userId },
            data: { isOnline: true, lastOnlineAt: new Date() },
        });

        // Broadcast online status to groups
        for (const groupId of groupIds) {
            socket.to(`group:${groupId}`).emit('user:online', {
                userId,
                groupId,
            });
        }

        // ========================================
        // Call Signaling Events
        // ========================================

        // Request a call
        socket.on('call:request', async (data: { targetUserId: string; callType: 'video' | 'voice'; groupId: string }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('call:incoming', {
                    callerId: userId,
                    callType: data.callType,
                    groupId: data.groupId,
                });
            } else {
                socket.emit('call:error', { message: 'User is offline' });
            }
        });

        // Accept call
        socket.on('call:accept', (data: { callerId: string }) => {
            const caller = connectedUsers.get(data.callerId);
            if (caller) {
                caller.socket.emit('call:accepted', { accepterId: userId });
            }
        });

        // Reject call
        socket.on('call:reject', (data: { callerId: string; reason?: string }) => {
            const caller = connectedUsers.get(data.callerId);
            if (caller) {
                caller.socket.emit('call:rejected', { rejecterId: userId, reason: data.reason });
            }
        });

        // End call
        socket.on('call:end', (data: { targetUserId: string }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('call:ended', { endedBy: userId });
            }
        });

        // ========================================
        // WebRTC Signaling
        // ========================================

        // SDP Offer
        socket.on('signal:offer', (data: { targetUserId: string; offer: RTCSessionDescriptionInit }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('signal:offer', { fromUserId: userId, offer: data.offer });
            }
        });

        // SDP Answer
        socket.on('signal:answer', (data: { targetUserId: string; answer: RTCSessionDescriptionInit }) => {
            const target = connectedUsers.get(data.targetUserId);
            if (target) {
                target.socket.emit('signal:answer', { fromUserId: userId, answer: data.answer });
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

            // Remove from connected users
            connectedUsers.delete(userId);

            // Update user offline status
            await prisma.user.update({
                where: { id: userId },
                data: { isOnline: false, lastOnlineAt: new Date() },
            });

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

// Helper function to notify user of new message
export function notifyNewMessage(receiverId: string, message: any) {
    const receiver = connectedUsers.get(receiverId);
    if (receiver) {
        receiver.socket.emit('message:new', message);
    }
}

// Type declaration for WebRTC
interface RTCSessionDescriptionInit {
    type: 'offer' | 'answer';
    sdp?: string;
}

interface RTCIceCandidateInit {
    candidate?: string;
    sdpMLineIndex?: number;
    sdpMid?: string;
}
