import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import fastifyStatic from '@fastify/static';
import fastifyMultipart from '@fastify/multipart';
import { Server } from 'socket.io';
import path from 'path';
import { fileURLToPath } from 'url';

import { config } from './config.js';
import { connectDatabase, disconnectDatabase } from './db.js';
import { authRoutes } from './routes/auth.js';
import { groupRoutes } from './routes/groups.js';
import { messageRoutes } from './routes/messages.js';
import { adminRoutes } from './routes/admin.js';
import { setupWebSocket } from './websocket/handler.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const fastify = Fastify({
    logger: true,
});

// Register plugins
await fastify.register(cors, {
    origin: config.nodeEnv === 'production' ? config.appUrl : true,
    credentials: true,
});

await fastify.register(jwt, {
    secret: config.jwtSecret,
    sign: {
        expiresIn: config.jwtExpiresIn,
    },
});

await fastify.register(fastifyMultipart, {
    limits: {
        fileSize: 50 * 1024 * 1024, // 50MB
    },
});

// Serve static files (uploads)
await fastify.register(fastifyStatic, {
    root: path.join(__dirname, '..', 'uploads'),
    prefix: '/uploads/',
});

// Serve admin panel static files
await fastify.register(fastifyStatic, {
    root: path.join(__dirname, '..', 'public', 'admin'),
    prefix: '/admin',
    decorateReply: false,
    index: 'index.html',
});

// Health check
fastify.get('/health', async () => {
    return { status: 'OK', version: '1.0.0', timestamp: new Date().toISOString() };
});

// Register routes
await fastify.register(authRoutes, { prefix: '/api/auth' });
await fastify.register(groupRoutes, { prefix: '/api/groups' });
await fastify.register(messageRoutes, { prefix: '/api/messages' });
await fastify.register(adminRoutes, { prefix: '/admin/api' });

// Start server
const start = async () => {
    try {
        // Connect to database
        await connectDatabase();

        // Start HTTP server
        await fastify.listen({ port: config.port, host: config.host });
        console.log(`🚀 Nanochat Server running at http://${config.host}:${config.port}`);

        // Setup Socket.IO
        const io = new Server(fastify.server, {
            cors: {
                origin: config.nodeEnv === 'production' ? config.appUrl : '*',
                methods: ['GET', 'POST'],
            },
        });
        setupWebSocket(io);
        console.log('🔌 WebSocket server ready');

    } catch (err) {
        fastify.log.error(err);
        process.exit(1);
    }
};

// Graceful shutdown
const shutdown = async () => {
    console.log('Shutting down...');
    await disconnectDatabase();
    await fastify.close();
    process.exit(0);
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

start();
