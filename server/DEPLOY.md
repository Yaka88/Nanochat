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

## 3. 部署步骤

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
- `DATABASE_URL`: 保持默认即可（容器内部通信）。
- `JWT_SECRET`: 请修改为一个随机长字符串。
- `BREVO_API_KEY`: 发送验证邮件所需的 API Key。
- `APP_URL`: 您的服务公开访问地址（例如 `https://chat.yourdomain.com`）。
- `ADMIN_USERNAME`: 管理员后台用户名。
- `ADMIN_PASSWORD`: **初始管理员密码，请务必修改。**

### 第三步：启动服务
使用 Docker Compose 构建并启动所有容器：
```bash
sudo docker compose up -d --build
```
该命令会自动完成：
1. 构建 API 镜像。
2. 启动 PostgreSQL 数据库。
3. 启动 Coturn (STUN/TURN) 服务。
4. 运行数据库迁移和自动初始化 (Seed)。

## 4. 后台管理与初始化

### 验证管理员账号
如果由于网络或容器启动顺序原因，初始管理员账号未能自动创建，请执行以下命令手动初始化：
```bash
sudo docker compose exec api npx tsx prisma/seed.ts
```

### 访问管理后台
- **地址**: `http://<your-vps-ip>:3000/admin/` 或 `https://your-domain.com/admin/`
- **默认账号**: `admin`
- **默认密码**: 您在 `.env` 中设置的 `ADMIN_PASSWORD`

## 5. 常用维护命令

- **查看日志**:
  ```bash
  sudo docker compose logs -f api
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

## 6. 常见问题排错

1. **无法连接数据库**:
   - 检查 `nanochat-db` 容器是否健康：`sudo docker compose ps`
   - 确保 `DATABASE_URL` 在 `.env` 中正确指向 `db` 主机。

2. **验证邮件发送失败**:
   - 检查 `BREVO_API_KEY` 是否有效。
   - 检查环境变量中的 `EMAIL_FROM` 是否已在 Brevo 后台验证。

3. **管理后台 401 Unauthorized**:
   - 确认数据库中 `admins` 表是否存在记录。
   - 使用方案 4 中的初始化命令重新生成管理员账号。
