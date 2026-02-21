import { v4 as uuidv4 } from 'uuid';
import crypto from 'crypto';
import { prisma } from '../db.js';
import { config } from '../config.js';

interface CreateGroupInput {
    name: string;
    creatorId: string;
    creatorNameInGroup: string;
}

interface JoinGroupInput {
    inviteCode: string;
    userId: string;
    nameInGroup: string;
}

interface InviteVerifyInput {
    inviteCode: string;
    groupId: string;
    groupName: string;
    inviterName: string;
    timestamp: number;
    signature: string;
}

const INVITE_EXPIRY_MS = 24 * 60 * 60 * 1000; // 24 hours

async function getSystemConfig(key: string): Promise<string> {
    const cfg = await prisma.systemConfig.findUnique({ where: { key } });
    return cfg?.value || '6';
}

/**
 * Verify the HMAC signature of an invite QR payload and check 24-hour expiry.
 * Throws an error if verification fails.
 */
export function verifyInvitePayload(data: InviteVerifyInput): void {
    // Check 24-hour expiry
    if (Date.now() - data.timestamp > INVITE_EXPIRY_MS) {
        throw new Error('Invite QR code has expired (valid for 24 hours)');
    }

    // Reconstruct the signed payload in the exact same order as generateInvite
    const payload = {
        type: 'nanochat_invite',
        group_id: data.groupId,
        group_name: data.groupName,
        inviter_name: data.inviterName,
        invite_code: data.inviteCode,
        timestamp: data.timestamp,
    };

    const hmac = crypto.createHmac('sha256', config.jwtSecret);
    hmac.update(JSON.stringify(payload));
    const expectedSignature = hmac.digest('hex');

    if (expectedSignature !== data.signature) {
        throw new Error('Invalid invite QR code');
    }
}

export async function createGroup(input: CreateGroupInput) {
    const { name, creatorId, creatorNameInGroup } = input;

    // Check group count limit
    const groupCount = await getSystemConfig('groupcount');
    const userGroupsCount = await prisma.groupMember.count({
        where: { userId: creatorId },
    });

    if (userGroupsCount >= parseInt(groupCount)) {
        throw new Error(`Maximum ${groupCount} groups allowed per user`);
    }

    // Generate unique invite code
    const inviteCode = crypto.randomBytes(8).toString('hex');

    // Create group and add creator as member
    const group = await prisma.group.create({
        data: {
            name,
            creatorId,
            inviteCode,
            members: {
                create: {
                    userId: creatorId,
                    nameInGroup: creatorNameInGroup,
                },
            },
        },
        include: {
            members: {
                include: {
                    user: {
                        select: {
                            id: true,
                            nickname: true,
                            avatarUrl: true,
                            isOnline: true,
                        },
                    },
                },
            },
        },
    });

    // Update user's last group
    await prisma.user.update({
        where: { id: creatorId },
        data: { lastGroupId: group.id },
    });

    return group;
}

export async function getUserGroups(userId: string) {
    const memberships = await prisma.groupMember.findMany({
        where: { userId },
        include: {
            group: {
                include: {
                    _count: {
                        select: { members: true },
                    },
                },
            },
        },
        orderBy: { joinedAt: 'desc' },
    });

    return memberships.map(m => ({
        id: m.group.id,
        name: m.group.name,
        nameInGroup: m.nameInGroup,
        memberCount: m.group._count.members,
        joinedAt: m.joinedAt,
    }));
}

export async function getGroupById(groupId: string, userId: string) {
    // Check if user is member
    const membership = await prisma.groupMember.findUnique({
        where: {
            groupId_userId: { groupId, userId },
        },
    });

    if (!membership) {
        throw new Error('You are not a member of this group');
    }

    const group = await prisma.group.findUnique({
        where: { id: groupId },
        include: {
            creator: {
                select: { id: true, nickname: true },
            },
            _count: {
                select: { members: true },
            },
        },
    });

    if (!group) {
        throw new Error('Group not found');
    }

    return {
        id: group.id,
        name: group.name,
        creatorId: group.creatorId,
        creatorNickname: group.creator.nickname,
        memberCount: group._count.members,
        createdAt: group.createdAt,
    };
}

export async function getGroupMembers(groupId: string, userId: string) {
    // Check if user is member
    const membership = await prisma.groupMember.findUnique({
        where: {
            groupId_userId: { groupId, userId },
        },
    });

    if (!membership) {
        throw new Error('You are not a member of this group');
    }

    const members = await prisma.groupMember.findMany({
        where: { groupId },
        include: {
            user: {
                select: {
                    id: true,
                    nickname: true,
                    avatarUrl: true,
                    isOnline: true,
                    lastOnlineAt: true,
                },
            },
        },
        orderBy: { joinedAt: 'asc' },
    });

    return members.map(m => ({
        id: m.user.id,
        nameInGroup: m.nameInGroup,
        nickname: m.user.nickname,
        avatarUrl: m.user.avatarUrl,
        isOnline: m.user.isOnline,
        lastOnlineAt: m.user.lastOnlineAt,
        joinedAt: m.joinedAt,
    }));
}

export async function generateInvite(groupId: string, userId: string) {
    // Check if user is registered Host
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user?.isRegistered) {
        throw new Error('Only registered users can invite members');
    }

    // Check if user is member
    const membership = await prisma.groupMember.findUnique({
        where: {
            groupId_userId: { groupId, userId },
        },
        include: {
            group: true,
        },
    });

    if (!membership) {
        throw new Error('You are not a member of this group');
    }

    // Generate invite payload for QR code
    const payload = {
        type: 'nanochat_invite',
        group_id: groupId,
        group_name: membership.group.name,
        inviter_name: membership.nameInGroup,
        invite_code: membership.group.inviteCode,
        timestamp: Date.now(),
    };

    // Add HMAC-SHA256 signature (full length, not truncated)
    const hmac = crypto.createHmac('sha256', config.jwtSecret);
    hmac.update(JSON.stringify(payload));
    const signature = hmac.digest('hex');

    return {
        ...payload,
        signature,
    };
}

export async function joinGroup(input: JoinGroupInput) {
    const { inviteCode, userId, nameInGroup } = input;

    // Find group by invite code
    const group = await prisma.group.findUnique({
        where: { inviteCode },
        include: {
            _count: { select: { members: true } },
        },
    });

    if (!group) {
        throw new Error('Invalid invite code');
    }

    // Check if already member
    const existing = await prisma.groupMember.findUnique({
        where: {
            groupId_userId: { groupId: group.id, userId },
        },
    });

    if (existing) {
        throw new Error('You are already a member of this group');
    }

    // Check member count limit
    const memberLimit = await getSystemConfig('membercount');
    if (group._count.members >= parseInt(memberLimit)) {
        throw new Error(`This group has reached its maximum capacity of ${memberLimit} members`);
    }

    // Check user's group count
    const groupCount = await getSystemConfig('groupcount');
    const userGroupsCount = await prisma.groupMember.count({
        where: { userId },
    });

    if (userGroupsCount >= parseInt(groupCount)) {
        throw new Error(`You have reached the maximum of ${groupCount} groups`);
    }

    // Add member
    await prisma.groupMember.create({
        data: {
            groupId: group.id,
            userId,
            nameInGroup,
        },
    });

    // Update user's last group
    await prisma.user.update({
        where: { id: userId },
        data: { lastGroupId: group.id },
    });

    return {
        id: group.id,
        name: group.name,
        nameInGroup,
    };
}

export async function createMemberUser(nickname: string, avatarUrl?: string, deviceId?: string) {
    const user = await prisma.user.create({
        data: {
            nickname,
            avatarUrl,
            isRegistered: false,
            emailVerified: false,
            deviceId,
        },
    });

    return {
        id: user.id,
        nickname: user.nickname,
        avatarUrl: user.avatarUrl,
        isRegistered: user.isRegistered,
    };
}
