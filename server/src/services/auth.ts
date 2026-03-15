import bcrypt from 'bcryptjs';
import { v4 as uuidv4 } from 'uuid';
import { prisma } from '../db.js';
import { sendVerificationEmail } from './email.js';

interface RegisterInput {
    email: string;
    password: string;
    nickname: string;
    avatarUrl?: string;
    deviceId?: string;
}

interface LoginInput {
    email: string;
    password: string;
    deviceId?: string;
}

interface UpgradeInput {
    userId: string;
    email: string;
    password: string;
    deviceId?: string;
}

export async function registerUser(input: RegisterInput) {
    const { password, nickname, avatarUrl, deviceId } = input;
    const email = input.email.trim().toLowerCase();

    // Check if email already exists
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) {
        throw new Error('Email already registered');
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // Generate verification token
    const verifyToken = uuidv4();

    // Create user
    const user = await prisma.user.create({
        data: {
            email,
            passwordHash,
            nickname,
            avatarUrl,
            isRegistered: true,
            emailVerified: false,
            verifyToken,
            ...(deviceId ? { deviceId } : {}),
        },
    });

    // Send verification email
    const sent = await sendVerificationEmail(email, verifyToken);
    if (!sent) {
        throw new Error('Failed to send verification email');
    }

    return {
        id: user.id,
        email: user.email,
        nickname: user.nickname,
        avatarUrl: user.avatarUrl,
        emailVerified: user.emailVerified,
        isRegistered: user.isRegistered,
        lastGroupId: user.lastGroupId,
    };
}

export async function verifyEmail(token: string) {
    const user = await prisma.user.findFirst({ where: { verifyToken: token } });
    if (!user) {
        throw new Error('Invalid verification token');
    }

    await prisma.user.update({
        where: { id: user.id },
        data: { emailVerified: true, verifyToken: null },
    });

    return { success: true };
}

export async function loginWithEmail(input: LoginInput) {
    const { password, deviceId } = input;
    const email = input.email.trim().toLowerCase();

    const user = await prisma.user.findUnique({ where: { email } });
    if (!user || !user.passwordHash) {
        throw new Error('Invalid email or password');
    }

    if (user.isDisabled) {
        throw new Error('Account is disabled');
    }

    const valid = await bcrypt.compare(password, user.passwordHash);
    if (!valid) {
        throw new Error('Invalid email or password');
    }

    if (!user.emailVerified) {
        throw new Error('Email not verified');
    }

    if (deviceId && deviceId !== user.deviceId) {
        await prisma.user.update({
            where: { id: user.id },
            data: { deviceId },
        });
    }

    return {
        id: user.id,
        email: user.email,
        nickname: user.nickname,
        avatarUrl: user.avatarUrl,
        emailVerified: user.emailVerified,
        isRegistered: user.isRegistered,
        lastGroupId: user.lastGroupId,
    };
}

export async function loginWithId(userId: string, deviceId: string) {
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
        throw new Error('User not found');
    }

    if (user.isDisabled) {
        throw new Error('Account is disabled');
    }

    // Device binding verification: Member users must use the same device
    if (!user.deviceId) {
        throw new Error('No device bound to this account');
    }

    if (user.deviceId !== deviceId) {
        throw new Error('Device not authorized for this account');
    }

    return {
        id: user.id,
        email: user.email,
        nickname: user.nickname,
        avatarUrl: user.avatarUrl,
        emailVerified: user.emailVerified,
        isRegistered: user.isRegistered,
        lastGroupId: user.lastGroupId,
    };
}

export async function getUserById(userId: string) {
    const user = await prisma.user.findUnique({
        where: { id: userId },
        include: {
            memberships: {
                include: {
                    group: true,
                },
            },
        },
    });

    if (!user) {
        throw new Error('User not found');
    }

    return {
        id: user.id,
        email: user.email,
        nickname: user.nickname,
        avatarUrl: user.avatarUrl,
        emailVerified: user.emailVerified,
        isRegistered: user.isRegistered,
        lastGroupId: user.lastGroupId,
        groups: user.memberships.map((m: any) => ({
            id: m.group.id,
            name: m.group.name,
            nameInGroup: m.nameInGroup,
        })),
    };
}

export async function upgradeMemberToRegistered(input: UpgradeInput) {
    const { userId, email, password, deviceId } = input;
    const normalizedEmail = email.trim().toLowerCase();

    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
        throw new Error('User not found');
    }

    if (user.isDisabled) {
        throw new Error('Account is disabled');
    }

    if (user.isRegistered) {
        throw new Error('Account is already registered');
    }

    const existing = await prisma.user.findUnique({ where: { email: normalizedEmail } });
    if (existing) {
        throw new Error('Email already registered');
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const verifyToken = uuidv4();

    const updated = await prisma.user.update({
        where: { id: userId },
        data: {
            email: normalizedEmail,
            passwordHash,
            isRegistered: true,
            emailVerified: false,
            verifyToken,
            ...(deviceId ? { deviceId } : {}),
        },
    });

    const sent = await sendVerificationEmail(normalizedEmail, verifyToken);
    if (!sent) {
        throw new Error('Failed to send verification email');
    }

    return {
        id: updated.id,
        email: updated.email,
        nickname: updated.nickname,
        avatarUrl: updated.avatarUrl,
        emailVerified: updated.emailVerified,
        isRegistered: updated.isRegistered,
        lastGroupId: updated.lastGroupId,
    };
}

export async function resendVerificationEmailForUser(userId: string) {
    const user = await prisma.user.findUnique({
        where: { id: userId },
        select: {
            id: true,
            email: true,
            nickname: true,
            avatarUrl: true,
            emailVerified: true,
            isRegistered: true,
            lastGroupId: true,
            isDisabled: true,
        },
    });

    if (!user) {
        throw new Error('User not found');
    }

    if (user.isDisabled) {
        throw new Error('Account is disabled');
    }

    if (!user.isRegistered) {
        throw new Error('Only registered users can resend verification email');
    }

    if (!user.email) {
        throw new Error('Email is required');
    }

    if (user.emailVerified) {
        throw new Error('Email is already verified');
    }

    const verifyToken = uuidv4();

    await prisma.user.update({
        where: { id: userId },
        data: { verifyToken },
    });

    const sent = await sendVerificationEmail(user.email, verifyToken);
    if (!sent) {
        throw new Error('Failed to send verification email');
    }

    return {
        id: user.id,
        email: user.email,
        nickname: user.nickname,
        avatarUrl: user.avatarUrl,
        emailVerified: user.emailVerified,
        isRegistered: user.isRegistered,
        lastGroupId: user.lastGroupId,
    };
}
