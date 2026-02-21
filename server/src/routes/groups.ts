import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import {
    createGroup,
    getUserGroups,
    getGroupById,
    getGroupMembers,
    generateInvite,
    joinGroup,
    createMemberUser,
    verifyInvitePayload,
} from '../services/groups.js';
import { verifyToken, verifyRegisteredUser } from '../middleware/auth.js';
import { prisma } from '../db.js';

const createGroupSchema = z.object({
    name: z.string().min(1).max(50),
    nameInGroup: z.string().min(1).max(50),
});

const joinGroupSchema = z.object({
    // QR payload fields (for signature verification and expiry check)
    inviteCode: z.string().min(1),
    groupId: z.string().uuid(),
    groupName: z.string().min(1),
    inviterName: z.string().min(1),
    timestamp: z.number(),
    signature: z.string().min(1),
    // User fields
    nickname: z.string().min(1).max(50),
    nameInGroup: z.string().min(1).max(50),
    avatarUrl: z.string().url().optional(),
    deviceId: z.string().min(1),
});

export async function groupRoutes(fastify: FastifyInstance) {
    // GET /api/groups - List my groups
    fastify.get('/', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const groups = await getUserGroups(request.user.id);
            reply.send({ success: true, groups });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });

    // POST /api/groups - Create new group (Host only)
    fastify.post('/', { preHandler: [verifyRegisteredUser] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const body = createGroupSchema.parse(request.body);
            const group = await createGroup({
                name: body.name,
                creatorId: request.user.id,
                creatorNameInGroup: body.nameInGroup,
            });

            reply.code(201).send({ success: true, group });
        } catch (error: any) {
            if (error.name === 'ZodError') {
                reply.code(400).send({ error: 'Validation error', details: error.errors });
            } else {
                reply.code(400).send({ error: error.message });
            }
        }
    });

    // GET /api/groups/:id - Group details
    fastify.get('/:id', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { id } = request.params as { id: string };
            const group = await getGroupById(id, request.user.id);
            reply.send({ success: true, group });
        } catch (error: any) {
            reply.code(404).send({ error: error.message });
        }
    });

    // GET /api/groups/:id/members - List members with online status
    fastify.get('/:id/members', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { id } = request.params as { id: string };
            const members = await getGroupMembers(id, request.user.id);
            reply.send({ success: true, members });
        } catch (error: any) {
            reply.code(404).send({ error: error.message });
        }
    });

    // GET /api/groups/:id/invite - Generate invite QR payload (Host only)
    fastify.get('/:id/invite', { preHandler: [verifyRegisteredUser] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { id } = request.params as { id: string };
            const invite = await generateInvite(id, request.user.id);
            reply.send({ success: true, invite });
        } catch (error: any) {
            reply.code(400).send({ error: error.message });
        }
    });

    // POST /api/groups/:id/join - Join group via group ID (existing authenticated users)
    fastify.post('/:id/join', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const body = z.object({ nameInGroup: z.string().min(1).max(50) }).parse(request.body);
            const { id } = request.params as { id: string };

            // Get invite code from group
            const group = await prisma.group.findUnique({ where: { id } });
            if (!group) {
                reply.code(404).send({ error: 'Group not found' });
                return;
            }

            const result = await joinGroup({
                inviteCode: group.inviteCode,
                userId: request.user.id,
                nameInGroup: body.nameInGroup,
            });

            reply.send({ success: true, group: result });
        } catch (error: any) {
            reply.code(400).send({ error: error.message });
        }
    });

    // POST /api/groups/join-by-code - Join group as new member (creates user)
    // This is for scanning QR code without existing account
    // Verifies QR code signature and 24-hour expiry
    fastify.post('/join-by-code', async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const body = joinGroupSchema.parse(request.body);

            // Verify QR code signature and check 24-hour expiry
            verifyInvitePayload({
                inviteCode: body.inviteCode,
                groupId: body.groupId,
                groupName: body.groupName,
                inviterName: body.inviterName,
                timestamp: body.timestamp,
                signature: body.signature,
            });

            // Create new member user with device binding
            const user = await createMemberUser(body.nickname, body.avatarUrl, body.deviceId);

            // Join group
            const group = await joinGroup({
                inviteCode: body.inviteCode,
                userId: user.id,
                nameInGroup: body.nameInGroup,
            });

            // Generate token
            const token = fastify.jwt.sign({
                id: user.id,
                email: null,
                isRegistered: false,
            });

            reply.code(201).send({
                success: true,
                token,
                user,
                group,
            });
        } catch (error: any) {
            if (error.name === 'ZodError') {
                reply.code(400).send({ error: 'Validation error', details: error.errors });
            } else {
                reply.code(400).send({ error: error.message });
            }
        }
    });
}
