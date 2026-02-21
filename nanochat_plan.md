# Nanochat 第一期 - 完整规划文档

> 最后更新：2026-01-28

---

## 📋 项目概述

| 项目 | 说明 |
|------|------|
| **应用名称** | Nanochat |
| **目标用户** | 家庭老年成员 |
| **核心特点** | 简洁易用、P2P通话、家庭群组 |
| **一期功能** | 视频通话、语音通话、语音短信、家庭群组管理、管理后台 |
| **支持语言** | 中文、英文（跟随系统语言） |
| **支持平台** | Android (API 24+)、iOS (13+) |

---

## 👨‍👩‍👧‍👦 家庭群组系统设计

### 核心概念

```
┌─────────────────────────────────────────────────────────────┐
│                      家庭 Group                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  group_id: UUID (唯一标识)                           │    │
│  │  group_name: 自定义名称 (默认 "Home")                │    │
│  │  creator_id: 创建者 ID                               │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  成员列表:                                                   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                     │
│  │ Host     │ │ Member 1 │ │ Member 2 │ ...                 │
│  │ (创建者)  │ │ (被邀请) │ │ (被邀请) │                     │
│  └──────────┘ └──────────┘ └──────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

### 用户类型对比

| 属性 | Host (注册用户) | Member (被邀请用户) |
|------|----------------|---------------------|
| **登录方式** | Email + Password | User ID (无需密码，本地保存) |
| **需要邮箱验证** | ✅ 是 | ❌ 否 |
| **可创建 Group** | ✅ 是 | ❌ 否 |
| **可邀请成员** | ✅ 是 | ❌ 否 |
| **可加入多个 Group** | ✅ 是 | ✅ 是 |

> **设计理念**: 老年人扫码加入家庭后无需记忆密码，App 自动保存登录状态。只有注册用户才能创建新家庭。

### 关键参数（全局配置，后端可调）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `membercount` | 6 | 每个家庭最多成员数 |
| `groupcount` | 6 | 每个账号最多加入/创建的家庭数 |
| `voice_msg_max_seconds` | 60 | 语音消息最长秒数 |

---

## 🔐 登录流程设计

### 首次使用流程

```
┌───────────────────────────────────────┐
│           首次登录界面                 │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │                                 │  │
│  │         📷 扫码加入              │  │
│  │    (扫描家庭二维码，无需密码)      │  │
│  │                                 │  │
│  └─────────────────────────────────┘  │
│                                       │
│  ┌─────────────────────────────────┐  │
│  │                                 │  │
│  │         ✉️ 邮箱注册              │  │
│  │    (创建账号，需要密码)            │  │
│  │                                 │  │
│  └─────────────────────────────────┘  │
│                                       │
└───────────────────────────────────────┘
```

### Host 注册流程 (Email + Password)

```
1. 点击 "邮箱注册"
2. 输入 Email + 设置密码 + 昵称 + 选择头像
3. 收到验证邮件，点击激活链接
4. 登录成功
5. 创建第一个家庭（输入家庭名称）
6. 进入家庭成员界面
7. 可生成二维码邀请家人加入
```

### Member 加入流程 (扫码，无需密码)

```
1. 点击 "扫码加入"
2. 扫描家庭二维码
3. 二维码包含: group_id + 邀请信息
4. 输入昵称（家庭称呼，如"妈妈"），选择头像
5. 系统自动创建 user_id（无需设置密码）
6. 加入成功，进入家庭成员界面
7. 之后登录：App 自动保存 user_id，直接登录
```

### 再次登录流程

```
App 启动
    │
    ├── 本地有保存的 user_id?
    │       ├── 是 → 自动登录 → 进入 last_group 的家庭界面
    │       └── 否 → 显示首次登录界面（扫码/注册）
```

### 二维码内容设计

```json
{
  "type": "nanochat_invite",
  "group_id": "550e8400-e29b-41d4-a716-446655440000",
  "group_name": "王家",
  "inviter_name": "王妈妈",
  "timestamp": 1705900800,
  "signature": "..."  // HMAC 签名，防止伪造邀请
}
```

---

## 📱 UI 界面设计

### 设计原则（老年友好）

| 原则 | 说明 |
|------|------|
| **大字体** | 最小字号 20sp |
| **大按钮** | 最小点击区域 64x64dp |
| **高对比度** | 深色文字配浅色背景，状态颜色鲜明 |
| **简洁布局** | 每页元素少，层级浅 |
| **图标+文字** | 按钮同时显示图标和文字 |

### 家庭成员列表界面

```
┌──────────────────────────────────────────┐
│  Nanochat     [王家 ▼]        [⚙️设置]   │  ← 多家庭可切换
├──────────────────────────────────────────┤
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ 👵  妈妈             ● 在线        │  │  ← 显示 name_in_group (家庭称呼)
│  │     [📹视频] [📞语音] [🎤留言]      │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ 👴  爸爸             ● 在线        │  │
│  │     [📹视频] [📞语音] [🎤留言]      │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ 👩  小妹             ○ 离线        │  │
│  │     [📹灰色] [📞灰色] [🎤留言]      │  │  ← 离线时视频/语音按钮禁用
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ 👨  小弟             ● 在线        │  │
│  │     [📹视频] [📞语音] [🎤留言]      │  │
│  └────────────────────────────────────┘  │
│                                          │
│  [➕ 邀请新成员]                          │  ← 仅 Host 可见
│                                          │
└──────────────────────────────────────────┘

每行布局: 头像 | 家庭称呼 + 在线状态 | 视频按钮 | 语音按钮 | 留言按钮
一页最多显示 6 个成员（可滚动）
```

### 按钮状态说明

| 成员状态 | 视频通话按钮 | 语音通话按钮 | 语音留言按钮 |
|----------|-------------|-------------|-------------|
| ● 在线 | ✅ 可点击 (蓝色) | ✅ 可点击 (绿色) | ✅ 可点击 (橙色) |
| ○ 离线 | ❌ 禁用 (灰色) | ❌ 禁用 (灰色) | ✅ 可点击 (橙色) |

---

## 🗄️ 数据库模型设计

### 设计原则

1. **users 表统一管理所有用户** - Host 和 Member 都在同一张表
2. **Host 有密码，Member 无密码** - Member 通过 user_id 直接登录
3. **group_members 表只存关联关系** - 简化为连接表
4. **全局配置统一管理** - membercount/groupcount 是系统级配置

### 表结构

```sql
-- 用户表 (所有用户: Host 和 Member)
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) UNIQUE,       -- Host 必填，Member 可为空
    password_hash   VARCHAR(255),              -- Host 必填，Member 为空
    email_verified  BOOLEAN DEFAULT FALSE,     -- Host 需验证
    nickname        VARCHAR(50) NOT NULL,      -- 用户昵称（全局）
    avatar_url      VARCHAR(255),
    is_registered   BOOLEAN DEFAULT FALSE,     -- true=Host注册用户, false=Member扫码用户
    last_group_id   UUID,                      -- 上次访问的家庭，下次自动进入
    is_online       BOOLEAN DEFAULT FALSE,
    device_token    VARCHAR(255),              -- 推送通知用
    created_at      TIMESTAMP DEFAULT NOW(),
    last_online_at  TIMESTAMP
);

-- 家庭群组表
CREATE TABLE groups (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(50) DEFAULT 'Home',
    creator_id      UUID REFERENCES users(id), -- 创建者
    invite_code     VARCHAR(32) UNIQUE,        -- 邀请码（用于生成二维码）
    created_at      TIMESTAMP DEFAULT NOW()
);

-- 群组成员关联表 (简化版)
CREATE TABLE group_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id        UUID REFERENCES groups(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    name_in_group   VARCHAR(50) NOT NULL,      -- 在该家庭中的称呼（如"妈妈"）
    joined_at       TIMESTAMP DEFAULT NOW(),
    UNIQUE(group_id, user_id)                  -- 一个用户在一个群组只能有一条记录
);

-- 语音消息表
CREATE TABLE voice_messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id        UUID REFERENCES groups(id),
    sender_id       UUID REFERENCES users(id),
    receiver_id     UUID REFERENCES users(id),
    audio_url       VARCHAR(255) NOT NULL,
    duration_seconds INTEGER,
    is_read         BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP DEFAULT NOW()
);

-- 系统配置表 (全局参数)
CREATE TABLE system_config (
    key             VARCHAR(50) PRIMARY KEY,
    value           VARCHAR(255) NOT NULL,
    description     VARCHAR(255)
);

-- 管理员表
CREATE TABLE admins (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username        VARCHAR(50) UNIQUE NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    created_at      TIMESTAMP DEFAULT NOW()
);

-- 默认全局配置
INSERT INTO system_config (key, value, description) VALUES
('membercount', '6', '每个家庭最大成员数'),
('groupcount', '6', '每个账号最大可加入/创建的家庭数'),
('voice_msg_max_seconds', '60', '语音消息最长秒数');
```

### 实体关系图

```
┌─────────────────┐         ┌─────────────────┐
│     users       │         │     groups      │
│─────────────────│         │─────────────────│
│ id (PK)         │◄────────│ creator_id      │
│ email (可空)    │         │ id (PK)         │
│ password (可空) │         │ name            │
│ nickname        │         │ invite_code     │
│ is_registered   │         └────────┬────────┘
│ last_group_id   │──────────────────┘
│ is_online       │
└────────┬────────┘
         │
         │ 1:N
         ▼
┌─────────────────────────────┐
│      group_members          │
│─────────────────────────────│
│ id (PK)                     │
│ group_id (FK → groups)      │
│ user_id (FK → users)        │
│ name_in_group (家庭称呼)     │
│ joined_at                   │
└─────────────────────────────┘

┌─────────────────────────────┐
│      system_config          │
│─────────────────────────────│
│ key (PK)     │ value        │
│──────────────┼──────────────│
│ membercount  │ 6            │  ← 全局配置
│ groupcount   │ 6            │
└─────────────────────────────┘
```

### 用户登录对比

| 用户类型 | email | password_hash | is_registered | 登录方式 |
|----------|-------|---------------|---------------|----------|
| Host (注册) | ✅ 有 | ✅ 有 | true | Email + Password |
| Member (扫码) | ❌ 空 | ❌ 空 | false | User ID (本地保存，自动登录) |

---

## 🔧 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| **前端** | Flutter (Dart) | 一套代码 Android + iOS |
| **后端** | Node.js + TypeScript + Fastify | WebRTC 生态成熟 |
| **数据库** | PostgreSQL | 可靠、功能丰富 |
| **实时通信** | WebSocket (socket.io) | 在线状态 + 信令 |
| **通话** | WebRTC (flutter_webrtc) | P2P 视频/语音 |
| **STUN** | 自建 coturn | 国内可用 |
| **容器** | Docker Compose | 一键部署（不含 Nginx） |
| **反向代理** | Nginx (系统级) | HTTPS + WebSocket，全局代理 |
| **邮件服务** | Brevo | 发送验证邮件 |

---

## 🌐 服务器部署架构

### 架构总览

> **重要**: Nginx 作为系统级全局反向代理（不在 Docker 内），统一管理所有域名的 HTTPS 和路由。

### 双域名架构

```
                     VPS (同一台服务器)
                           │
            ┌──────────────┴──────────────┐
            │      系统级 Nginx            │
            │   /etc/nginx/sites-enabled/  │
            └──────────────┬──────────────┘
                           │
       ┌───────────────────┴───────────────────┐
       │                                       │
 vps.bluelaser.cn                      chat.bluelaser.cn
       │                                       │
  ┌────┴────┐                             ┌────┴────┐
  │         │                             │         │
 :443      :8443                         :443      :80
(Nginx)   (VLESS)                       (Nginx)  (→443)
  │       直连                             │
  ├─/admin/* → :8080 (3x-ui面板)          └─/* → :3000 (Nanochat Docker)
  └─/sub → :25500 (SubConverter)              ├─/api/* → API
                                              ├─/socket.io/* → WebSocket
                                              ├─/uploads/* → 静态资源
                                              └─/admin/* → 管理后台
+ :3478/udp → coturn (STUN, Docker)
```

### 域名与端口分配

| 域名 | 端口 | 服务 |
|------|------|------|
| `vps.bluelaser.cn` | 443 | Nginx → 3x-ui 面板 + SubConverter |
| `vps.bluelaser.cn` | 8443 | VLESS 代理（直连） |
| `chat.bluelaser.cn` | 443 | Nginx → Nanochat API + 管理后台 |
| `chat.bluelaser.cn` | 80 | HTTP 重定向到 HTTPS |
| - | 3478/udp | STUN (coturn) |

### SSL 证书

- **类型**: 泛域名证书 `*.bluelaser.cn`
- **申请方式**: acme.sh + ZoneEdit DNS 验证
- **路径**: `/etc/ssl/bluelaser.cn.crt` 和 `.key`

### Nginx 配置（系统级）

> **配置文件统一管理在项目 `nginx/` 目录，通过软链接安装到系统 Nginx。**

| 配置文件 | 用途 |
|----------|------|
| `vps.bluelaser.cn.conf` | 3x-ui 面板 + SubConverter |
| `chat.bluelaser.cn.conf` | Nanochat API + WebSocket + 管理后台 |

```bash
# 配置文件位置
/home/yaka/Documents/Nanochat/nginx/
├── vps.bluelaser.cn.conf    # 3x-ui 面板、SubConverter
└── chat.bluelaser.cn.conf   # Nanochat 服务

# 安装方式：创建软链接到 sites-enabled
sudo ln -sf /home/yaka/Documents/Nanochat/nginx/*.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

#### vps.bluelaser.cn 路由规则

| 路径 | 目标服务 | 端口 |
|------|----------|------|
| `/admin`, `/admin/*` | 3x-ui 面板 | 8080 |
| `/sub`, `/convert`, ... | SubConverter | 25500 |
| `8443 (直连)` | VLESS 代理 | 8443 (不经过 Nginx) |

#### chat.bluelaser.cn 路由规则

| 路径 | 目标服务 | 说明 |
|------|----------|------|
| `/api/*` | Node.js 后端 | REST API |
| `/socket.io/*` | Node.js 后端 | WebSocket (在线状态 + 信令) |
| `/admin/*` | Node.js 后端 | 管理后台 |
| `/uploads/*` | Node.js 后端 | 静态资源 (头像、语音消息) |

### Docker Compose 服务（不含 Nginx）

```
nanochat/
├── docker-compose.yml
├── nginx/                        # Nginx 配置（仅配置文件，系统级 Nginx 使用）
│   ├── vps.bluelaser.cn.conf     # 3x-ui + SubConverter
│   └── chat.bluelaser.cn.conf    # Nanochat
├── api/                          # Node.js 后端 (端口 3000)
├── postgres/                     # 数据库 (端口 5432, 仅内部访问)
└── coturn/                       # STUN 服务器 (端口 3478/udp)
```

### Docker 服务端口

| 服务 | 容器内端口 | 宿主机端口 | 访问方式 |
|------|-----------|-----------|----------|
| api (Node.js) | 3000 | 3000 | 通过 Nginx 代理 |
| postgres | 5432 | - | 仅容器内部访问 |
| coturn | 3478/udp | 3478/udp | 直接暴露 |

---

## �️ 管理后台

### 功能列表

```
chat.bluelaser.cn/admin

┌─────────────────────────────────────────────────────────────┐
│  Nanochat 管理后台                      [管理员] [登出]      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  📊 统计概览                                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ 用户总数  │  │ 家庭总数  │  │ 今日通话  │  │ 语音消息  │    │
│  │   128    │  │    45    │  │    23    │  │   156    │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
│                                                             │
│  ⚙️ 系统配置                                                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ membercount (每家庭最大成员数):  [ 6  ] [保存]       │    │
│  │ groupcount (每用户最大家庭数):   [ 6  ] [保存]       │    │
│  │ voice_msg_max_seconds:          [ 60 ] [保存]       │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  👥 用户管理                                                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ID       │ 昵称    │ 类型   │ 家庭数 │ 状态   │ 操作 │    │
│  │ a1b2c3.. │ 王妈妈  │ Host   │ 2     │ 在线   │ [禁用] │   │
│  │ d4e5f6.. │ 王爸爸  │ Member │ 1     │ 离线   │ [禁用] │   │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  🏠 家庭管理                                                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ ID       │ 名称   │ 创建者  │ 成员数 │ 创建时间       │    │
│  │ x1y2z3.. │ 王家   │ 王妈妈  │ 4     │ 2026-01-20    │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 管理后台 API

| 路径 | 方法 | 说明 |
|------|------|------|
| `/admin/api/login` | POST | 管理员登录 |
| `/admin/api/stats` | GET | 统计数据 |
| `/admin/api/config` | GET | 获取系统配置 |
| `/admin/api/config` | PUT | 更新系统配置 |
| `/admin/api/users` | GET | 用户列表 |
| `/admin/api/users/:id` | PUT | 更新用户状态 |
| `/admin/api/groups` | GET | 家庭列表 |

---

## 📡 API 设计

### 公开 API (App 使用)

| 路径 | 方法 | 说明 |
|------|------|------|
| `/api/auth/register` | POST | 用户注册 |
| `/api/auth/verify-email` | GET | 邮箱验证 |
| `/api/auth/login` | POST | 用户登录 |
| `/api/auth/login-by-id` | POST | Member 用 ID 登录 |
| `/api/auth/me` | GET | 获取当前用户信息 |
| `/api/groups` | GET | 获取我的家庭列表 |
| `/api/groups` | POST | 创建家庭 |
| `/api/groups/:id` | GET | 获取家庭详情 |
| `/api/groups/:id/members` | GET | 获取家庭成员 |
| `/api/groups/:id/invite` | GET | 生成邀请二维码 |
| `/api/groups/:id/join` | POST | 加入家庭 |
| `/api/messages` | GET | 获取语音消息列表 |
| `/api/messages` | POST | 发送语音消息 |
| `/api/messages/:id/read` | PUT | 标记已读 |

### WebSocket 事件

| 事件 | 方向 | 说明 |
|------|------|------|
| `user:online` | 服务端→客户端 | 用户上线通知 |
| `user:offline` | 服务端→客户端 | 用户下线通知 |
| `call:request` | 客户端→服务端 | 发起通话请求 |
| `call:accept` | 客户端→服务端 | 接受通话 |
| `call:reject` | 客户端→服务端 | 拒绝通话 |
| `call:end` | 双向 | 结束通话 |
| `signal:offer` | 双向 | WebRTC SDP Offer |
| `signal:answer` | 双向 | WebRTC SDP Answer |
| `signal:ice` | 双向 | WebRTC ICE Candidate |
| `message:new` | 服务端→客户端 | 新语音消息通知 |

---

## 🔄 开发流程

### 本地开发环境

| 软件 | 版本 | 用途 |
|------|------|------|
| Flutter SDK | 最新稳定版 | 前端开发 |
| Docker | 最新版 | 本地运行后端 |
| Git | 最新版 | 版本控制 |

### 开发模式

```
1. 本地安装 Flutter SDK
   sudo snap install flutter --classic
   
2. AI Agent 写代码

3. 本地 Android 真机即时调试

4. Push 到 GitHub

5. GitHub Actions 构建 iOS

6. 下载 IPA 测试 iPhone
```

---

## 📅 开发计划

| 阶段 | 时长 | 内容 |
|------|------|------|
| **Phase 1** | 2天 | 项目结构 + 数据库 + 后端认证 API |
| **Phase 2** | 2天 | 家庭群组管理 API + 管理后台 |
| **Phase 3** | 2天 | WebSocket 在线状态 + 信令服务 |
| **Phase 4** | 3天 | Flutter 前端 UI（老年友好设计） |
| **Phase 5** | 3天 | WebRTC 视频/语音通话 |
| **Phase 6** | 2天 | 语音留言功能 |
| **Phase 7** | 2天 | 部署 + 真机联调 |
| **总计** | ~16天 | |

---

## � 项目目录结构

```
nanochat/
├── app/                         # Flutter 移动端
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/
│   │   │   ├── routes/          # 路由配置
│   │   │   └── themes/          # 主题配置（老年友好）
│   │   ├── features/
│   │   │   ├── auth/            # 注册/登录
│   │   │   ├── home/            # 家庭成员列表
│   │   │   ├── call/            # 视频/语音通话
│   │   │   └── voice_message/   # 语音留言
│   │   ├── core/
│   │   │   ├── api/             # API 客户端
│   │   │   ├── webrtc/          # WebRTC 封装
│   │   │   └── l10n/            # 国际化
│   │   └── shared/              # 共享组件
│   ├── android/
│   ├── ios/
│   └── pubspec.yaml
│
├── server/                      # Node.js 后端
│   ├── src/
│   │   ├── index.ts             # 入口
│   │   ├── routes/
│   │   │   ├── auth.ts          # 认证路由
│   │   │   ├── groups.ts        # 家庭路由
│   │   │   ├── messages.ts      # 消息路由
│   │   │   └── admin.ts         # 管理后台路由
│   │   ├── services/
│   │   │   ├── auth.ts
│   │   │   ├── email.ts
│   │   │   ├── signaling.ts     # WebSocket 信令
│   │   │   └── storage.ts       # 文件存储
│   │   ├── websocket/
│   │   │   └── handler.ts
│   │   └── middleware/
│   ├── prisma/
│   │   └── schema.prisma        # 数据库模型
│   ├── public/
│   │   └── admin/               # 管理后台静态文件
│   ├── Dockerfile
│   └── package.json
│
├── nginx/                       # 系统级 Nginx 配置
│   └── chat.bluelaser.cn.conf   # 软链接到 /etc/nginx/sites-enabled/
│
├── docker/
│   ├── docker-compose.yml       # 不含 Nginx
│   └── coturn/
│       └── turnserver.conf
│
├── .github/
│   └── workflows/
│       ├── backend-deploy.yml   # 后端 CI/CD
│       ├── android-build.yml    # Android 构建
│       └── ios-build.yml        # iOS 构建
│
└── docs/
    └── nanochat_plan.md         # 本文档
```

---

## ✅ 已确认信息

| 项目 | 状态 | 值 |
|------|------|-----|
| 主域名 | ✅ | `vps.bluelaser.cn` (3x-ui) |
| Nanochat 域名 | ✅ | `chat.bluelaser.cn` |
| 泛域名证书 | ✅ | `*.bluelaser.cn` (已申请) |
| Nanochat 端口 | ✅ | 443 (标准 HTTPS) |
| STUN 端口 | ✅ | 3478/udp |
| 邮件服务 | ✅ | Brevo |
| 开发模式 | ✅ | 本地 Flutter + GitHub Actions iOS |

---

## 🔜 二期预留

以下功能在一期代码中预留接口，二期实现：

| 功能 | 预留方式 |
|------|----------|
| 文本短信 | messages 表增加 type 字段 |
| 手机号注册 | users 表增加 phone 字段 |
| 其他语言 | 国际化框架支持动态添加 |
| 群组通话 | WebRTC 支持多人，信令预留 |

---

*文档版本: 1.1*
*最后更新: 2026-01-28*
*变更记录: v1.1 - Nginx 改为系统级全局代理（不在 Docker 内）*
