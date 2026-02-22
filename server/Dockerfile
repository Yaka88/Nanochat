FROM node:20-alpine AS builder

# Install dependencies for Prisma and building
RUN apk add --no-cache openssl libc6-compat

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm install

# Copy source and build
COPY . .
RUN npm run db:generate
RUN npm run build

# Production stage
FROM node:20-alpine

# Install runtime dependencies for Prisma
RUN apk add --no-cache openssl libc6-compat

WORKDIR /app

# Copy built files
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/public ./public

# Create uploads directory
RUN mkdir -p uploads

# Create entrypoint script that ensures DB schema is synced before starting
RUN echo '#!/bin/sh' > /app/entrypoint.sh && \
    echo 'set -e' >> /app/entrypoint.sh && \
    echo 'echo "⏳ Syncing database schema..."' >> /app/entrypoint.sh && \
    echo 'npx prisma db push --skip-generate' >> /app/entrypoint.sh && \
    echo 'echo "✅ Database schema synced"' >> /app/entrypoint.sh && \
    echo 'echo "🚀 Starting server..."' >> /app/entrypoint.sh && \
    echo 'exec node dist/index.js' >> /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

EXPOSE 3000

CMD ["/app/entrypoint.sh"]
