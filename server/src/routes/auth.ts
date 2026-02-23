import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';
import path from 'path';
import { registerUser, verifyEmail, loginWithEmail, loginWithId, getUserById, upgradeMemberToRegistered, resendVerificationEmailForUser } from '../services/auth.js';
import { verifyToken } from '../middleware/auth.js';
import { saveFile } from '../services/storage.js';
import { prisma } from '../db.js';

const registerSchema = z.object({
    email: z.string().email(),
    password: z.string().min(6),
    nickname: z.string().min(1).max(50),
    avatarUrl: z.string().url().optional(),
});

const loginSchema = z.object({
    email: z.string().email(),
    password: z.string().min(1),
});

const loginByIdSchema = z.object({
    userId: z.string().uuid(),
    deviceId: z.string().min(1),
});

const upgradeSchema = z.object({
    email: z.string().email(),
    password: z.string().min(6),
});

export async function authRoutes(fastify: FastifyInstance) {
    // POST /api/auth/register
    fastify.post('/register', async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const body = registerSchema.parse(request.body);
            const user = await registerUser(body);
            const token = fastify.jwt.sign({
                id: user.id,
                email: user.email,
                isRegistered: user.isRegistered,
            });

            reply.code(201).send({
                success: true,
                message: 'Registration successful. Please check your email to verify your account.',
                token,
                user,
            });
        } catch (error: any) {
            if (error.name === 'ZodError') {
                reply.code(400).send({ error: 'Validation error', details: error.errors });
            } else {
                reply.code(400).send({ error: error.message });
            }
        }
    });

    // GET /api/auth/verify-email
    fastify.get('/verify-email', async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const { token } = request.query as { token: string };
            if (!token) {
                reply.code(400).send({ error: 'Token is required' });
                return;
            }

            await verifyEmail(token);

            // Redirect to success page or return JSON
            reply.type('text/html').send(`
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>邮箱验证成功</title></head>
        <body style="font-family: sans-serif; text-align: center; padding: 50px;">
          <h1 style="color: #22c55e;">✅ 邮箱验证成功</h1>
          <p>您现在可以关闭此页面，返回 App 登录。</p>
        </body>
        </html>
      `);
        } catch (error: any) {
            reply.code(400).send({ error: error.message });
        }
    });

    // POST /api/auth/login
    fastify.post('/login', async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const body = loginSchema.parse(request.body);
            const user = await loginWithEmail(body);

            const token = fastify.jwt.sign({
                id: user.id,
                email: user.email,
                isRegistered: user.isRegistered,
            });

            reply.send({
                success: true,
                token,
                user,
            });
        } catch (error: any) {
            if (error.name === 'ZodError') {
                reply.code(400).send({ error: 'Validation error', details: error.errors });
            } else {
                reply.code(401).send({ error: error.message });
            }
        }
    });

    // POST /api/auth/login-by-id
    fastify.post('/login-by-id', async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const body = loginByIdSchema.parse(request.body);
            const user = await loginWithId(body.userId, body.deviceId);

            const token = fastify.jwt.sign({
                id: user.id,
                email: user.email,
                isRegistered: user.isRegistered,
            });

            reply.send({
                success: true,
                token,
                user,
            });
        } catch (error: any) {
            if (error.name === 'ZodError') {
                reply.code(400).send({ error: 'Validation error', details: error.errors });
            } else {
                reply.code(401).send({ error: error.message });
            }
        }
    });

    // GET /api/auth/me
    fastify.get('/me', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const user = await getUserById(request.user.id);
            reply.send({ success: true, user });
        } catch (error: any) {
            reply.code(404).send({ error: error.message });
        }
    });

    // POST /api/auth/upgrade
    fastify.post('/upgrade', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const body = upgradeSchema.parse(request.body);
            const user = await upgradeMemberToRegistered({
                userId: request.user.id,
                email: body.email,
                password: body.password,
            });

            const token = fastify.jwt.sign({
                id: user.id,
                email: user.email,
                isRegistered: user.isRegistered,
            });

            reply.send({
                success: true,
                message: 'Registration upgrade successful. Please check your email to verify your account.',
                token,
                user,
            });
        } catch (error: any) {
            if (error.name === 'ZodError') {
                reply.code(400).send({ error: 'Validation error', details: error.errors });
            } else {
                reply.code(400).send({ error: error.message });
            }
        }
    });

    // POST /api/auth/resend-verification
    fastify.post('/resend-verification', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const user = await resendVerificationEmailForUser(request.user.id);
            reply.send({
                success: true,
                message: 'Verification email sent',
                user,
            });
        } catch (error: any) {
            reply.code(400).send({ error: error.message });
        }
    });

    // POST /api/auth/upload-avatar
    fastify.post('/upload-avatar', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const data = await request.file();
            if (!data) {
                reply.code(400).send({ error: 'Avatar file is required' });
                return;
            }

            const contentType = data.mimetype || '';
            if (!contentType.startsWith('image/')) {
                reply.code(400).send({ error: 'Only image files are allowed' });
                return;
            }

            const extFromName = path.extname(data.filename || '');
            const extension = extFromName || '.jpg';
            const buffer = await data.toBuffer();
            const avatarUrl = await saveFile(buffer, extension);

            reply.code(201).send({
                success: true,
                avatarUrl,
            });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });

    // PUT /api/auth/me/avatar
    fastify.put('/me/avatar', { preHandler: [verifyToken] }, async (request: FastifyRequest, reply: FastifyReply) => {
        try {
            const data = await request.file();
            if (!data) {
                reply.code(400).send({ error: 'Avatar file is required' });
                return;
            }

            const contentType = data.mimetype || '';
            if (!contentType.startsWith('image/')) {
                reply.code(400).send({ error: 'Only image files are allowed' });
                return;
            }

            const extFromName = path.extname(data.filename || '');
            const extension = extFromName || '.jpg';
            const buffer = await data.toBuffer();
            const avatarUrl = await saveFile(buffer, extension);

            const user = await prisma.user.update({
                where: { id: request.user.id },
                data: { avatarUrl },
                select: {
                    id: true,
                    email: true,
                    emailVerified: true,
                    nickname: true,
                    avatarUrl: true,
                    isRegistered: true,
                    lastGroupId: true,
                },
            });

            reply.send({ success: true, user });
        } catch (error: any) {
            reply.code(500).send({ error: error.message });
        }
    });
}
