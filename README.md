# Ara Infrastructure

Ara 平台的 Docker 基礎設施，整合後端 API、管理面板與即時通知服務。

## 架構概覽

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Ara Infrastructure                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐  │
│  │   Symfony PHP   │  │   SvelteKit     │  │   Notification Service  │  │
│  │   (後端 API)    │  │   (管理面板)    │  │   (即時通知)            │  │
│  │                 │  │                 │  │                         │  │
│  │   Port: 80/443  │  │   Port: 3000    │  │   Port: 8081            │  │
│  │   FrankenPHP    │  │   Node.js 22    │  │   Rust + Axum           │  │
│  └────────┬────────┘  └────────┬────────┘  └────────────┬────────────┘  │
│           │                    │                        │               │
│           │         HTTP API   │      WebSocket/SSE     │               │
│           └────────────────────┼────────────────────────┘               │
│                                │                                        │
│                    ┌───────────┴───────────┐                            │
│                    │        Redis          │                            │
│                    │      Port: 6379       │                            │
│                    └───────────┬───────────┘                            │
│                                │                                        │
│                    ┌───────────┴───────────┐                            │
│                    │      PostgreSQL       │                            │
│                    │      Port: 5432       │                            │
│                    └───────────────────────┘                            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## 服務說明

| 服務 | 技術棧 | 端口 | 說明 |
|------|--------|------|------|
| **php** | Symfony 8 + FrankenPHP | 80, 443 | 後端 REST API |
| **administration** | SvelteKit 2 + Svelte 5 | 3000 | 管理後台 |
| **notification** | Rust + Axum + Tokio | 8081 | 即時通知服務 |
| **postgres** | PostgreSQL 17 | 5432 | 主資料庫 |
| **redis** | Redis 8.4 | 6379 | 快取與訊息佇列 |

## 快速開始

### 1. 環境需求

- Docker Desktop 4.0+
- Docker Compose 2.0+
- Git

### 2. 初始化專案

```bash
# 克隆專案 (包含子模組)
git clone --recursive https://github.com/your-org/Ara-infra.git
cd Ara-infra

# 或者如果已經克隆，初始化子模組
git submodule update --init --recursive
```

### 3. 環境配置

```bash
# 複製環境變數範本
cp .env.example .env

# 編輯 .env 設定你的配置 (重要：修改 JWT_SECRET)
# Windows
notepad .env

# Linux/Mac
nano .env
```

**必要配置：**
```env
# 重要：請更換為安全的隨機字串 (至少 32 字元)
JWT_SECRET=your-secure-random-string-at-least-32-characters

# 資料庫配置 (可選，有預設值)
POSTGRES_USER=symfony
POSTGRES_PASSWORD=symfony
POSTGRES_DB=symfony
```

生成安全密鑰：
```bash
# Linux/Mac
openssl rand -base64 32

# 或使用 Python
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

### 4. 啟動服務

```bash
# 建構並啟動所有服務
docker-compose up -d --build

# 查看服務狀態
docker-compose ps

# 查看日誌
docker-compose logs -f
```

### 5. 驗證服務

```bash
# 檢查各服務健康狀態
curl http://localhost/api/health          # Symfony
curl http://localhost:3000                # SvelteKit
curl http://localhost:8081/health         # Notification

# 查看通知服務統計
curl http://localhost:8081/stats
```

## 服務端點

### Symfony 後端 API

| 端點 | 說明 |
|------|------|
| `https://localhost` | API 根路徑 |
| `https://localhost/api/*` | REST API |

### 管理面板

| 端點 | 說明 |
|------|------|
| `http://localhost:3000` | 管理後台首頁 |

### 通知服務

| 方法 | 端點 | 說明 |
|------|------|------|
| WS | `ws://localhost:8081/ws?token=JWT` | WebSocket 連線 |
| GET | `http://localhost:8081/sse?token=JWT` | SSE 連線 (備援) |
| POST | `http://localhost:8081/api/v1/notifications/send` | 發送給用戶 |
| POST | `http://localhost:8081/api/v1/notifications/broadcast` | 廣播給所有人 |
| POST | `http://localhost:8081/api/v1/notifications/channel` | 發送到頻道 |
| GET | `http://localhost:8081/health` | 健康檢查 |
| GET | `http://localhost:8081/stats` | 連線統計 |
| GET | `http://localhost:8081/metrics` | Prometheus 指標 |

## 開發指南

### Symfony 後端開發

```bash
# 進入 PHP 容器
docker-compose exec php bash

# 常用命令
composer install                    # 安裝依賴
bin/console cache:clear            # 清除快取
bin/console doctrine:migrations:migrate  # 執行遷移
bin/console make:controller        # 建立控制器
```

### SvelteKit 前端開發

```bash
# 進入 Node 容器
docker-compose exec administration sh

# 常用命令
pnpm install          # 安裝依賴
pnpm dev              # 開發伺服器 (已自動啟動)
pnpm build            # 建構生產版本
pnpm check            # 類型檢查
pnpm test:unit        # 單元測試
```

### 通知服務開發

```bash
# 進入 notification 目錄
cd services/notification

# 本地開發 (需要 Rust 環境)
cargo run             # 執行
cargo test            # 測試 (265 個測試)
cargo check           # 快速編譯檢查
cargo clippy          # Linter
```

## 整合指南

### 從 Symfony 發送通知

#### 方法一：HTTP API

```php
// src/Service/NotificationService.php
<?php

namespace App\Service;

use Symfony\Contracts\HttpClient\HttpClientInterface;

class NotificationService
{
    public function __construct(
        private HttpClientInterface $httpClient,
        private string $notificationUrl = 'http://notification:8081'
    ) {}

    public function sendToUser(string $userId, string $eventType, array $payload): void
    {
        $this->httpClient->request('POST', "{$this->notificationUrl}/api/v1/notifications/send", [
            'json' => [
                'user_id' => $userId,
                'event_type' => $eventType,
                'payload' => $payload,
            ],
        ]);
    }

    public function broadcast(string $eventType, array $payload): void
    {
        $this->httpClient->request('POST', "{$this->notificationUrl}/api/v1/notifications/broadcast", [
            'json' => [
                'event_type' => $eventType,
                'payload' => $payload,
            ],
        ]);
    }
}
```

#### 方法二：Redis Pub/Sub (推薦)

```php
// src/Service/NotificationService.php
<?php

namespace App\Service;

use Predis\Client as RedisClient;

class NotificationService
{
    public function __construct(private RedisClient $redis) {}

    public function sendToUser(string $userId, string $eventType, array $payload): void
    {
        $this->redis->publish("notification:user:{$userId}", json_encode([
            'type' => 'user',
            'target' => $userId,
            'event' => [
                'event_type' => $eventType,
                'payload' => $payload,
            ],
        ]));
    }

    public function broadcast(string $eventType, array $payload): void
    {
        $this->redis->publish('notification:broadcast', json_encode([
            'type' => 'broadcast',
            'event' => [
                'event_type' => $eventType,
                'payload' => $payload,
            ],
        ]));
    }
}
```

### 在 SvelteKit 接收通知

```typescript
// src/lib/services/notification.ts
import { writable } from 'svelte/store';

export const notifications = writable<any[]>([]);
export const connectionStatus = writable<'connecting' | 'connected' | 'disconnected'>('disconnected');

class NotificationClient {
    private ws: WebSocket | null = null;

    connect(token: string) {
        const wsUrl = import.meta.env.DEV
            ? `ws://localhost:8081/ws?token=${token}`
            : `wss://${window.location.host}/ws?token=${token}`;

        connectionStatus.set('connecting');
        this.ws = new WebSocket(wsUrl);

        this.ws.onopen = () => {
            connectionStatus.set('connected');
        };

        this.ws.onmessage = (event) => {
            const message = JSON.parse(event.data);
            if (message.type === 'Notification') {
                notifications.update(n => [message.event, ...n].slice(0, 100));
            }
        };

        this.ws.onclose = () => {
            connectionStatus.set('disconnected');
            // 自動重連邏輯...
        };
    }

    subscribe(channels: string[]) {
        this.ws?.send(JSON.stringify({
            type: 'Subscribe',
            payload: { channels }
        }));
    }

    disconnect() {
        this.ws?.close();
    }
}

export const notificationClient = new NotificationClient();
```

```svelte
<!-- src/routes/+layout.svelte -->
<script lang="ts">
    import { onMount } from 'svelte';
    import { notificationClient, notifications, connectionStatus } from '$lib/services/notification';
    import { authStore } from '$lib/stores/auth';

    onMount(() => {
        if ($authStore.token) {
            notificationClient.connect($authStore.token);
        }
    });
</script>

<div class="connection-status" class:connected={$connectionStatus === 'connected'}>
    {$connectionStatus}
</div>

<slot />
```

## 環境變數

### 共用配置

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `JWT_SECRET` | (必填) | JWT 簽名密鑰，Symfony 與 Notification 共用 |
| `JWT_ISSUER` | `ara-platform` | JWT 發行者 |
| `JWT_AUDIENCE` | `ara-services` | JWT 受眾 |

### 資料庫

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `POSTGRES_DB` | `symfony` | 資料庫名稱 |
| `POSTGRES_USER` | `symfony` | 資料庫用戶 |
| `POSTGRES_PASSWORD` | `symfony` | 資料庫密碼 |

### 應用程式

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `APP_ENV` | `dev` | Symfony 環境 |
| `APP_DEBUG` | `1` | 除錯模式 |
| `RUST_LOG` | `info` | Notification 日誌等級 |

### 通知服務功能開關

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `QUEUE_ENABLED` | `false` | 離線訊息佇列 |
| `ACK_ENABLED` | `false` | 送達確認追蹤 |
| `RATELIMIT_ENABLED` | `false` | 請求限流 |
| `TENANT_ENABLED` | `false` | 多租戶模式 |
| `CLUSTER_ENABLED` | `false` | 分布式集群模式 |

## 常用命令

### Docker 操作

```bash
# 啟動所有服務
docker-compose up -d

# 停止所有服務
docker-compose down

# 重建特定服務
docker-compose up -d --build notification

# 查看日誌
docker-compose logs -f php
docker-compose logs -f notification

# 進入容器
docker-compose exec php bash
docker-compose exec notification sh
```

### 資料庫操作

```bash
# 進入 PostgreSQL
docker-compose exec postgres psql -U symfony -d symfony

# 備份資料庫
docker-compose exec postgres pg_dump -U symfony symfony > backup.sql

# 還原資料庫
docker-compose exec -T postgres psql -U symfony symfony < backup.sql
```

### Redis 操作

```bash
# 進入 Redis CLI
docker-compose exec redis redis-cli

# 監控 Pub/Sub 訊息
docker-compose exec redis redis-cli PSUBSCRIBE "notification:*"

# 查看所有鍵
docker-compose exec redis redis-cli KEYS "*"
```

## 故障排除

### 服務無法啟動

```bash
# 檢查日誌
docker-compose logs notification

# 常見問題：
# 1. JWT_SECRET 未設定 → 編輯 .env 設定 JWT_SECRET
# 2. 端口衝突 → 修改 docker-compose.yml 中的端口映射
# 3. 建構失敗 → docker-compose build --no-cache notification
```

### WebSocket 連線失敗

```bash
# 檢查通知服務狀態
curl http://localhost:8081/health

# 檢查 JWT Token 是否有效
# Token 必須包含 "sub" (用戶 ID) 欄位

# 檢查 CORS 設定 (如果從不同域連線)
```

### Redis 連線問題

```bash
# 測試 Redis 連線
docker-compose exec redis redis-cli ping
# 應該回應 PONG

# 檢查通知服務是否連接 Redis
docker-compose logs notification | grep -i redis
```

## 專案結構

```
Ara-infra/
├── backend/                 # Symfony 後端 (子模組)
├── administration/          # SvelteKit 管理面板 (子模組)
├── services/
│   └── notification/        # Rust 通知服務
│       ├── src/
│       ├── tests/
│       ├── docs/
│       ├── Cargo.toml
│       └── Dockerfile
├── docker/
│   ├── php/
│   │   └── Dockerfile
│   └── node/
│       └── Dockerfile
├── docker-compose.yml
├── .env.example
├── .env                     # 本地配置 (不提交)
└── README.md
```

## 授權

MIT License

## 貢獻

歡迎提交 Issue 和 Pull Request！
