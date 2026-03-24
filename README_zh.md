# Nanochat (纳聊)

Nanochat 是一款专为家中长辈设计的极简通讯应用。它专注于高质量的音视频通话和语音留言，提供最直观、无障碍的交互体验。

## 🌟 核心功能

- **老年友好设计**：采用高对比度、大字体、直观大图标，专为视觉障碍及非技术用户优化。
- **高清通话**：基于 WebRTC 的高清 P2P 视频和音频通话。
- **原生接听体验**：深度集成 iOS/Android CallKit，接听来电如同接听普通电话一样简单，支持后台唤醒和锁屏接听。
- **家庭群组**：极简“扫码加入”系统，长辈无需记忆密码。
- **语音短信**：简单的一键点按录制和回放语音消息。

## 🏗 技术架构

Nanochat 采用现代、稳健的移动端架构：
- **单实例引擎模式**：彻底剥离了冗余的后台常驻服务，转而采用 FCM + CallKit 的原生唤醒机制。这保证了极佳的省电性能，并彻底杜绝了后台幽灵引擎导致的接听冲突。
- **实时信令**：基于 Node.js 和 Socket.IO 自建的实时信令服务器，确保毫秒级的在线状态更新。
- **自动化构建**：通过 GitHub Actions 实现完整的 CI/CD 流程，自动化完成生产环境签名与发布。

## 🛠 技术栈

- **前端**：Flutter
- **后端**：Node.js, Fastify, Socket.IO
- **数据库**：PostgreSQL (Prisma ORM)
- **基础设施**：Docker, Nginx, Coturn (STUN/TURN)
- **推送服务**：Firebase Cloud Messaging (FCM)

## 📖 相关文档

- [English README (英文说明)](README.md)
- [项目规划文档 (Detailed Plan)](nanochat_plan.md)

## 🚀 快速开始

### 环境要求
- Flutter SDK (Stable)
- Node.js & Docker (用于服务器部署)
- Firebase 账号 (用于 FCM 推送)

### 安装步骤
1. 克隆仓库。
2. 配置 `server/` 目录下的 `.env` 文件。
3. 在 `server/` 目录下运行 `npm install` 和 `npx prisma migrate dev`。
4. 在 `app/` 目录下运行 `flutter pub get`。
5. 使用提供的 Docker Compose 配置文件进行部署。

## 📄 授权说明
本项目为私人家庭用途。
