import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import { prisma } from '../db.js';
import { verifyToken } from '../middleware/auth.js';
import { saveFile } from '../services/storage.js';
import { notifyNewMessage } from '../websocket/handler.js';

export async function messageRoutes(fastify: FastifyInstance) {
    // GET /api/messages - List voice messages for user
    fastify.get('/', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { groupId, unreadOnly } = request.query as { groupId?: string; unreadOnly?: string };

            const where: any = {
                receiverId: request.user.id,
            };

            if (groupId) {
                where.groupId = groupId;
            }

            if (unreadOnly === 'true') {
                where.isRead = false;
            }

            const messages = await prisma.voiceMessage.findMany({
                where,
                include: {
                    sender: {
                        select: {
                            id: true,
                            nickname: true,
                            avatarUrl: true,
                        },
                    },
                    group: {
                        select: {
                            id: true,
                            name: true,
                        },
                    },
                },
                orderBy: { createdAt: 'desc' },
                take: 50,
            });

            reply.send({
                success: true,
                messages: messages.map(m => ({
                    id: m.id,
                    audioUrl: m.audioUrl,
                    durationSeconds: m.durationSeconds,
                    isRead: m.isRead,
                    createdAt: m.createdAt,
                    sender: m.sender,
                    group: m.group,
                })),
            });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });

    // POST /api/messages - Upload voice message
    fastify.post('/', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const data = await request.file();
            if (!data) {
                reply.code(400).send({ error: 'Audio file is required' });
                return;
            }

            // Get form fields
            const fields = data.fields as any;
            const groupId = fields.groupId?.value;
            const receiverId = fields.receiverId?.value;
            const durationSeconds = parseInt(fields.durationSeconds?.value || '0');

            if (!groupId || !receiverId) {
                reply.code(400).send({ error: 'groupId and receiverId are required' });
                return;
            }

            // Validate duration against system config
            const maxDurationConfig = await prisma.systemConfig.findUnique({ where: { key: 'voice_msg_max_seconds' } });
            const maxDuration = parseInt(maxDurationConfig?.value || '60');
            if (durationSeconds > maxDuration) {
                reply.code(400).send({ error: `Voice message cannot exceed ${maxDuration} seconds` });
                return;
            }

            // Check if user is member of the group
            const membership = await prisma.groupMember.findUnique({
                where: {
                    groupId_userId: { groupId, userId: request.user.id },
                },
            });

            if (!membership) {
                reply.code(403).send({ error: 'You are not a member of this group' });
                return;
            }

            // Check if receiver is member of the group
            const receiverMembership = await prisma.groupMember.findUnique({
                where: {
                    groupId_userId: { groupId, userId: receiverId },
                },
            });

            if (!receiverMembership) {
                reply.code(400).send({ error: 'Receiver is not a member of this group' });
                return;
            }

            // Save audio file
            const buffer = await data.toBuffer();
            const audioUrl = await saveFile(buffer, '.m4a');

            // Create message record
            const message = await prisma.voiceMessage.create({
                data: {
                    groupId,
                    senderId: request.user.id,
                    receiverId,
                    audioUrl,
                    durationSeconds,
                },
                include: {
                    sender: {
                        select: { id: true, nickname: true, avatarUrl: true },
                    },
                },
            });

            const messagePayload = {
                id: message.id,
                audioUrl: message.audioUrl,
                durationSeconds: message.durationSeconds,
                createdAt: message.createdAt,
                sender: message.sender,
            };

            // Notify receiver via WebSocket in real-time
            notifyNewMessage(receiverId, messagePayload);

            reply.code(201).send({
                success: true,
                message: messagePayload,
            });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });

    // PUT /api/messages/:id/read - Mark message as read
    fastify.put('/:id/read', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { id } = request.params as { id: string };

            const message = await prisma.voiceMessage.findUnique({
                where: { id },
            });

            if (!message) {
                reply.code(404).send({ error: 'Message not found' });
                return;
            }

            if (message.receiverId !== request.user.id) {
                reply.code(403).send({ error: 'You can only mark your own messages as read' });
                return;
            }

            await prisma.voiceMessage.update({
                where: { id },
                data: { isRead: true },
            });

            reply.send({ success: true });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });
}
