import { FastifyRequest, FastifyReply } from 'fastify';
import { prisma } from '../db.js';

export interface JwtPayload {
    id: string;
    email?: string | null;
    isRegistered?: boolean;
    username?: string;
    isAdmin?: boolean;
}

declare module '@fastify/jwt' {
    interface FastifyJWT {
        payload: JwtPayload;
        user: JwtPayload;
    }
}

export async function verifyToken(request: FastifyRequest, reply: FastifyReply) {
    try {
        await request.jwtVerify();
    } catch (err) {
        return reply.code(401).send({ error: 'Unauthorized', message: 'Invalid or expired token' });
    }
}

export async function verifyRegisteredUser(request: FastifyRequest, reply: FastifyReply) {
    try {
        await request.jwtVerify();
        if (!request.user.isRegistered) {
            return reply.code(403).send({ error: 'Forbidden', message: 'This action requires a registered account' });
        }
    } catch (err) {
        return reply.code(401).send({ error: 'Unauthorized', message: 'Invalid or expired token' });
    }
}

export async function verifyRegisteredAndVerifiedUser(request: FastifyRequest, reply: FastifyReply) {
    try {
        await request.jwtVerify();
        if (!request.user.isRegistered) {
            return reply.code(403).send({ error: 'Forbidden', message: 'This action requires a registered account' });
        }

        const user = await prisma.user.findUnique({
            where: { id: request.user.id },
            select: { emailVerified: true },
        });

        if (!user?.emailVerified) {
            return reply.code(403).send({ error: 'Forbidden', message: 'Please verify your email before creating a group' });
        }
    } catch (err) {
        return reply.code(401).send({ error: 'Unauthorized', message: 'Invalid or expired token' });
    }
}
