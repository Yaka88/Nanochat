# Nanochat

[English](README.md) | [中文](README_zh.md)

Nanochat is a minimalist, elder-friendly communication application designed for simple family connectivity. It focuses on high-quality video/audio calls and voice messaging with a streamlined user interface.

## 🌟 Key Features

- **Elder-Friendly Design**: High-contrast, large-font UI with intuitive iconography.
- **VoIP Calling**: Reliable P2P video and audio calls powered by WebRTC.
- **One-Tap Connectivity**: CallKit integration (iOS/Android) for a native "phone-like" experience even from background/lock screen.
- **Family Groups**: Easy "Scan-to-Join" system for elderly members; no passwords to remember.
- **Voice Messaging**: Simple push-to-talk voice messages.

## 🏗 Architecture

Nanochat uses a robust, modern mobile architecture:
- **Single Engine Pattern**: Unlike traditional background apps, Nanochat uses a single Flutter isolate combined with Firebase Cloud Messaging (FCM) and CallKit. This ensures maximum battery efficiency and zero conflict between background and foreground tasks.
- **Proactive Signaling**: Custom signaling server built with Node.js and Socket.IO for real-time presence and WebRTC negotiation.
- **Secure Signing**: Automated CI/CD pipeline via GitHub Actions with full release signing.

## 🛠 Tech Stack

- **Frontend**: Flutter
- **Backend**: Node.js, Fastify, Socket.IO
- **Database**: PostgreSQL (Prisma ORM)
- **Infrastructure**: Docker, Nginx, Coturn (STUN/TURN)
- **Push Notifications**: Firebase Cloud Messaging (FCM)

## 📖 Documentation

- [中文说明 (Chinese README)](README_zh.md)
- [Detailed Project Plan](nanochat_plan.md)

## 🔧 Build & Deployment

### Android (CI/CD via GitHub Actions)

- CI builds are triggered automatically on commits/PRs.
- Required GitHub repository secrets: `GOOGLE_SERVICES_JSON`, `KEYSTORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`.
- Artifacts (APKs/AABs) are available in the Actions run page.
- See `.github/workflows/android-build.yml` for details.

### Server

- Docker & Docker Compose: `cd server && docker compose up -d`
- For detailed deployment steps, see [server/DEPLOY.md](server/DEPLOY.md).


## 🚀 Getting Started

### Prerequisites
- Flutter SDK (Stable)
- Node.js & Docker (for server deployment)
- Firebase Account (for FCM)

### Installation
1. Clone the repository.
2. Configure `.env` in the `server/` directory.
3. Run `npm install` and `npx prisma migrate dev` in the `server/` directory.
4. Run `flutter pub get` in the `app/` directory.
5. Deploy using the provided Docker Compose configuration (located in the `server/` directory).

