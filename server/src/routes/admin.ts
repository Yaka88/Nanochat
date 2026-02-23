import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import { prisma } from '../db.js';
import { config } from '../config.js';
import { getOnlineUserIds, isUserOnline } from '../websocket/handler.js';

// Admin auth middleware
async function verifyAdmin(request: FastifyRequest, reply: FastifyReply) {
    try {
        await request.jwtVerify();
        if (!request.user.isAdmin) {
            return reply.code(403).send({ error: 'Admin access required' });
        }
    } catch (err) {
        return reply.code(401).send({ error: 'Unauthorized' });
    }
}

export async function adminRoutes(fastify: FastifyInstance) {
    // POST /admin/api/login
    fastify.post('/login', async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const body = z.object({
                username: z.string().min(1),
                password: z.string().min(1),
            }).parse(request.body);

            const admin = await prisma.admin.findUnique({
                where: { username: body.username },
            });

            if (!admin) {
                reply.code(401).send({ error: 'Invalid credentials' });
                return;
            }

            const valid = await bcrypt.compare(body.password, admin.passwordHash);
            if (!valid) {
                reply.code(401).send({ error: 'Invalid credentials' });
                return;
            }

            const token = fastify.jwt.sign({
                id: admin.id,
                username: admin.username,
                isAdmin: true,
            });

            reply.send({ success: true, token });
        } catch (error: any) {
            reply.code(400).send({ error: error.message });
        }
    });

    // GET /admin/api/stats
    fastify.get('/stats', { preHandler: [verifyAdmin] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const [
                userCount,
                registeredUserCount,
                memberUserCount,
                groupCount,
                messageCount,
            ] = await Promise.all([
                prisma.user.count(),
                prisma.user.count({ where: { isRegistered: true } }),
                prisma.user.count({ where: { isRegistered: false } }),
                prisma.group.count(),
                prisma.voiceMessage.count(),
            ]);

            const onlineCount = getOnlineUserIds().length;

            // Today's stats
            const today = new Date();
            today.setHours(0, 0, 0, 0);

            const todayMessages = await prisma.voiceMessage.count({
                where: { createdAt: { gte: today } },
            });

            reply.send({
                success: true,
                stats: {
                    totalUsers: userCount,
                    registeredUsers: registeredUserCount,
                    memberUsers: memberUserCount,
                    totalGroups: groupCount,
                    totalMessages: messageCount,
                    onlineUsers: onlineCount,
                    todayMessages,
                },
            });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });

    // GET /admin/api/config
    fastify.get('/config', { preHandler: [verifyAdmin] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const configs = await prisma.systemConfig.findMany();
            reply.send({
                success: true,
                config: configs.reduce((acc, c) => {
                    acc[c.key] = { value: c.value, description: c.description };
                    return acc;
                }, {} as Record<string, { value: string; description: string | null }>),
            });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });

    // PUT /admin/api/config
    fastify.put('/config', { preHandler: [verifyAdmin] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const body = z.record(z.string(), z.string()).parse(request.body);

            for (const [key, value] of Object.entries(body)) {
                await prisma.systemConfig.upsert({
                    where: { key },
                    update: { value },
                    create: { key, value },
                });
            }

            reply.send({ success: true });
        } catch (error: any) {
            reply.code(400).send({ error: error.message });
        }
    });

    // GET /admin/api/users
    fastify.get('/users', { preHandler: [verifyAdmin] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { page = '1', limit = '20', search } = request.query as { page?: string; limit?: string; search?: string };
            const skip = (parseInt(page) - 1) * parseInt(limit);

            const where: any = {};
            if (search) {
                where.OR = [
                    { nickname: { contains: search, mode: 'insensitive' } },
                    { email: { contains: search, mode: 'insensitive' } },
                ];
            }

            const [users, total] = await Promise.all([
                prisma.user.findMany({
                    where,
                    select: {
                        id: true,
                        email: true,
                        emailVerified: true,
                        nickname: true,
                        avatarUrl: true,
                        isRegistered: true,
                        isDisabled: true,
                        createdAt: true,
                        lastOnlineAt: true,
                        _count: {
                            select: { memberships: true },
                        },
                    },
                    orderBy: { createdAt: 'desc' },
                    skip,
                    take: parseInt(limit),
                }),
                prisma.user.count({ where }),
            ]);

            reply.send({
                success: true,
                users: users.map(u => ({
                    ...u,
                    isOnline: isUserOnline(u.id),
                    groupCount: u._count.memberships,
                })),
                pagination: {
                    page: parseInt(page),
                    limit: parseInt(limit),
                    total,
                    totalPages: Math.ceil(total / parseInt(limit)),
                },
            });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });

    // PUT /admin/api/users/:id
    fastify.put('/users/:id', { preHandler: [verifyAdmin] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { id } = request.params as { id: string };
            const body = z.object({
                isDisabled: z.boolean().optional(),
                nickname: z.string().min(1).max(50).optional(),
            }).parse(request.body);

            await prisma.user.update({
                where: { id },
                data: body,
            });

            reply.send({ success: true });
        } catch (error: any) {
            reply.code(400).send({ error: error.message });
        }
    });

    // DELETE /admin/api/users/:id
    fastify.delete('/users/:id', { preHandler: [verifyAdmin] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { id } = request.params as { id: string };

            const user = await prisma.user.findUnique({ where: { id } });
            if (!user) {
                reply.code(404).send({ error: 'User not found' });
                return;
            }

            await prisma.$transaction(async (tx) => {
                const createdGroups = await tx.group.findMany({
                    where: { creatorId: id },
                    select: { id: true },
                });
                const createdGroupIds = createdGroups.map(g => g.id);

                if (createdGroupIds.length > 0) {
                    await tx.voiceMessage.deleteMany({
                        where: { groupId: { in: createdGroupIds } },
                    });
                    await tx.groupMember.deleteMany({
                        where: { groupId: { in: createdGroupIds } },
                    });
                    await tx.group.deleteMany({
                        where: { id: { in: createdGroupIds } },
                    });
                }

                await tx.voiceMessage.deleteMany({
                    where: {
                        OR: [{ senderId: id }, { receiverId: id }],
                    },
                });

                await tx.groupMember.deleteMany({ where: { userId: id } });
                await tx.user.delete({ where: { id } });
            });

            reply.send({ success: true });
        } catch (error: any) {
            reply.code(400).send({ error: error.message });
        }
    });

    // GET /admin/api/groups
    fastify.get('/groups', { preHandler: [verifyAdmin] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { page = '1', limit = '20' } = request.query as { page?: string; limit?: string };
            const skip = (parseInt(page) - 1) * parseInt(limit);

            const [groups, total] = await Promise.all([
                prisma.group.findMany({
                    include: {
                        creator: {
                            select: { id: true, nickname: true },
                        },
                        _count: {
                            select: { members: true },
                        },
                    },
                    orderBy: { createdAt: 'desc' },
                    skip,
                    take: parseInt(limit),
                }),
                prisma.group.count(),
            ]);

            reply.send({
                success: true,
                groups: groups.map(g => ({
                    id: g.id,
                    name: g.name,
                    creator: g.creator,
                    memberCount: g._count.members,
                    createdAt: g.createdAt,
                })),
                pagination: {
                    page: parseInt(page),
                    limit: parseInt(limit),
                    total,
                    totalPages: Math.ceil(total / parseInt(limit)),
                },
            });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });

    // DELETE /admin/api/groups/:id
    fastify.delete('/groups/:id', { preHandler: [verifyAdmin] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { id } = request.params as { id: string };

            const group = await prisma.group.findUnique({ where: { id } });
            if (!group) {
                reply.code(404).send({ error: 'Group not found' });
                return;
            }

            await prisma.$transaction(async (tx) => {
                await tx.voiceMessage.deleteMany({ where: { groupId: id } });
                await tx.groupMember.deleteMany({ where: { groupId: id } });
                await tx.group.delete({ where: { id } });
            });

            reply.send({ success: true });
        } catch (error: any) {
            reply.code(400).send({ error: error.message });
        }
    });
}
