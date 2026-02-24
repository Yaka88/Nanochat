# Nanochat 部署指南

本手册指导如何将 Nanochat 服务部署到远程 VPS 环境。

## 1. 环境依赖

在部署之前，请确保您的 VPS 已安装以下软件：
- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **Git**

## 2. 项目结构

建议的目录结构：
```text
Nanochat/
├── server/             # 后端 API 服务
│   ├── .env           # 环境变量配置文件
│   ├── docker-compose.yml
│   └── ...
```

## 3. 防火墙 / 安全组端口

coturn TURN 服务需要以下端口对外开放：

| 端口 | 协议 | 用途 |
|------|------|------|
| 3478 | TCP + UDP | STUN / TURN 监听端口 |

**基础配置（推荐）**：

```bash
# ufw 示例
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp
```

> 如果部署后发现某些网络环境下通话失败，可以根据排错指南开放 49152-65535/UDP 端口。

## 4. 部署步骤

### 第一步：克隆代码
```bash
git clone <your-repo-url> Nanochat
cd Nanochat/server
```

### 第二步：配置环境变量
复制示例配置文件并根据实际情况修改：
```bash
cp .env.example .env
nano .env
```
**关键配置项说明：**

| 变量 | 说明 | 示例 |
|------|------|------|
| `JWT_SECRET` | 随机长字符串，用于签名 token | `openssl rand -hex 32` 生成 |
| `BREVO_API_KEY` | 发送验证邮件的 API Key | — |
| `APP_URL` | 公开访问地址 | `https://chat.bluelaser.cn` |
| `TURN_HOST` | TURN 服务器域名/IP（须与客户端可达的地址一致） | `chat.bluelaser.cn` |
| `TURN_SECRET` | coturn 共享密钥（服务端和 coturn 必须一致） | `openssl rand -hex 16` 生成 |
| `ADMIN_PASSWORD` | 管理后台密码，**必须修改** | — |

`.env` 完整示例：
```dotenv
PORT=3000
HOST=0.0.0.0
NODE_ENV=production

DATABASE_URL="postgresql://postgres:postgres@db:5432/nanochat?schema=public"

JWT_SECRET="替换为随机字符串"
JWT_EXPIRES_IN="7d"

BREVO_API_KEY="你的Brevo密钥"
EMAIL_FROM="noreply@bluelaser.cn"
EMAIL_FROM_NAME="Nanochat"

APP_URL="https://chat.bluelaser.cn"

TURN_HOST="chat.bluelaser.cn"
TURN_PORT=3478
TURN_SECRET="替换为随机字符串"
TURN_CREDENTIAL_TTL=86400

ADMIN_USERNAME="admin"
ADMIN_PASSWORD="替换为强密码"
```

### 第三步：启动服务
```bash
sudo docker compose up -d --build
```
该命令会自动完成：
1. 构建 API 镜像。
2. 启动 PostgreSQL 数据库。
3. 启动 coturn TURN/STUN 中继服务。
4. 运行数据库迁移和自动初始化 (Seed)。

### 第四步：验证 TURN 服务
```bash
# 检查 coturn 容器运行状态
sudo docker compose ps coturn

# 测试 STUN 端口是否可达（从本地执行）
nc -zvu <你的服务器IP> 3478
```

也可以用在线工具验证：https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/
- 输入 `turn:chat.bluelaser.cn:3478`
- 用户名格式为 `<unix过期时间>:<任意字符>`，密码为 HMAC-SHA1 签名（或直接在 App 中测试通话）

## 5. 后台管理与初始化

### 验证管理员账号
如果由于网络或容器启动顺序原因，初始管理员账号未能自动创建，请执行以下命令手动初始化：
```bash
sudo docker compose exec api npx tsx prisma/seed.ts
```

### 访问管理后台
- **地址**: `https://chat.bluelaser.cn/admin/`
- **默认账号**: `admin`
- **默认密码**: 您在 `.env` 中设置的 `ADMIN_PASSWORD`

## 6. 更新部署（本次更新）

如果是从旧版本升级，执行以下步骤：

```bash
cd Nanochat/server

# 1. 拉取最新代码
git pull

# 2. 更新 .env —— 添加 TURN 相关变量（如已有则跳过）
#    删除旧的 STUN_SERVER 变量（不再使用）
cat >> .env << 'EOF'

# TURN / STUN (coturn) — 新增
TURN_HOST="chat.bluelaser.cn"
TURN_PORT=3478
TURN_SECRET="替换为你的随机密钥"
TURN_CREDENTIAL_TTL=86400
EOF

# 3. 重新构建并重启所有容器
sudo docker compose up -d --build

# 4. 确认所有容器正常运行
sudo docker compose ps
```

> **注意**：旧的 `STUN_SERVER` 环境变量已弃用，可从 `.env` 中删除。

## 7. 常用维护命令

- **查看日志**:
  ```bash
  sudo docker compose logs -f api
  sudo docker compose logs -f coturn
  ```

- **重启服务**:
  ```bash
  sudo docker compose restart
  ```

- **更新服务**:
  ```bash
  git pull
  sudo docker compose up -d --build
  ```

- **重置数据库 (警告：会清除所有数据)**:
  ```bash
  sudo docker compose exec api npx prisma migrate reset
  ```

## 8. 常见问题排错

1. **语音/视频通话无法连通**:
   - 确认防火墙已放行 3478/TCP 和 3478/UDP。
   - `sudo docker compose logs coturn` 查看 coturn 日志。
   - 确认 `.env` 中的 `TURN_SECRET` 与 docker-compose.yml 中一致。
   - 如果基础配置后仍无法通话（某些严格网络环境），可尝试开放 TURN relay 媒体端口：
     ```bash
     sudo ufw allow 49152:65535/udp
     sudo docker compose restart
     ```

2. **在线状态不正确**:
   - 重启 API 容器会自动重置所有用户为离线。
   - 客户端在 reconnect 时会自动刷新群组房间。

3. **无法连接数据库**:
   - 检查 `nanochat-db` 容器是否健康：`sudo docker compose ps`
   - 确保 `DATABASE_URL` 在 `.env` 中正确指向 `db` 主机。

4. **验证邮件发送失败**:
   - 检查 `BREVO_API_KEY` 是否有效。
   - 检查环境变量中的 `EMAIL_FROM` 是否已在 Brevo 后台验证。

3. **管理后台 401 Unauthorized**:
   - 确认数据库中 `admins` 表是否存在记录。
   - 使用方案 4 中的初始化命令重新生成管理员账号。
