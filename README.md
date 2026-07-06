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
| **php** | Symfony 8 + FrankenPHP | 80, 443 | 後端 REST API（Caddy 亦在此路由各服務） |
| **administration** | SvelteKit 2 + Svelte 5 | 3000 | 管理後台 |
| **notification** | Rust + Axum + Tokio | 8081 | 即時通知服務（WebSocket/SSE） |
| **chat** | Rust + Axum + Tokio | 8082 | 即時聊天服務（WebSocket + REST，獨立 `ara_chat` 資料庫） |
| **scheduler** | PHP (Messenger) | — | 排程任務 worker（訂閱續約等） |
| **async-worker** | PHP (Messenger) | — | 非同步背景任務 worker（Redis 佇列） |
| **postgres** | PostgreSQL 17 + pg_partman | 5432 | 資料庫（`symfony` + `ara_chat`） |
| **redis** | Redis 8.4 | 6379 | 快取、訊息佇列與 Pub/Sub |
| **backup** | Alpine + cron | — | 每日自動備份（可選 S3 上傳） |

詳細維運說明（功能開關、金鑰輪替、監控、叢集）見
[docs/operations.md](docs/operations.md)。

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

**必要配置（缺任何一項，`docker compose up` 會直接拒絕啟動——這是刻意的
fail-closed 設計，避免以不安全的預設值上線）：**
```env
# 以下四項皆為必填，各自使用「不同」的隨機字串。用 make gen-secret 產生。
APP_SECRET=your-secure-random-string          # Symfony 密鑰；亦用於加密 2FA 密鑰（留空會明文落庫）
JWT_SECRET=your-secure-random-string-at-least-32-characters  # JWT 對稱密鑰
JWT_PASSPHRASE=your-secure-random-string      # 保護 RS256 私鑰的密語（勿共用、勿提交）
NOTIFICATION_API_KEY=your-secure-random-string-min-16-chars  # 後端↔通知服務的 X-API-Key（至少 16 字元）

# 資料庫配置 (可選，有預設值)
POSTGRES_USER=symfony
POSTGRES_PASSWORD=symfony
POSTGRES_DB=symfony
```

生成安全密鑰（每個變數各跑一次）：
```bash
# 使用 Makefile (推薦)
make gen-secret

# 或 Linux/Mac
openssl rand -base64 32

# 或使用 Python
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

> 🔒 這些是機密，只寫進本地的 `.env`（已被 gitignore），**切勿提交或貼到
> 任何共享位置**。`make init` 會在啟動前檢查它們不是範本佔位值。

### 4. 生成 JWT 金鑰 (RS256)

後端使用 RS256 非對稱簽章發行 JWT：私鑰只存在於 Symfony 後端，
notification 與 chat 服務以唯讀方式掛載 `backend/config/jwt/public.pem`
來驗證 token。**金鑰不進版控，首次啟動前必須先生成**，否則：

- notification / chat 容器會啟動失敗
- Docker 會在缺失的掛載路徑上自動建立一個 `public.pem` **目錄**，
  之後生成金鑰也會失敗（需先手動刪除該目錄）

```bash
# 使用 Makefile (推薦，冪等：已存在則跳過)
make gen-jwt-keys

# 或手動執行
docker compose run --rm --no-deps php bin/console lexik:jwt:generate-keypair --skip-if-exists
```

金鑰會生成在 `backend/config/jwt/{private,public}.pem`，路徑由 `backend/.env`
的 `JWT_SECRET_KEY` / `JWT_PUBLIC_KEY` 控制，**加密密語則來自環境變數
`JWT_PASSPHRASE`（見上一步，無預設值、必填）**。私鑰用此密語加密，因此密語
與金鑰必須成對——換密語就得重新生成金鑰。

**輪替金鑰／密語**（例如密語外洩，或定期輪替）：

```bash
# 1) 在 .env 換上新的 JWT_PASSPHRASE（make gen-secret）
# 2) 用新密語重新生成金鑰對（會使所有現有 JWT 失效，使用者需重新登入）
make rotate-jwt-keys
# 3) 重建以載入新公鑰（notification / chat 以唯讀掛載 public.pem）
docker compose up -d --build
```

> 💡 以上步驟 (2)–(4) 加上建構啟動可用一鍵完成：`make init`

### 5. 啟動服務

```bash
# 建構並啟動所有服務
docker-compose up -d --build

# 查看服務狀態
docker-compose ps

# 查看日誌
docker-compose logs -f
```

### 6. 驗證服務

```bash
# 檢查各服務健康狀態
curl http://localhost/api/health          # Symfony
curl http://localhost:3000                # SvelteKit
curl http://localhost:8081/health         # Notification（僅回環，需在 host 上執行）

# 查看通知服務統計（受 API key 保護；:8081 僅綁 127.0.0.1）
curl -H "X-API-Key: $NOTIFICATION_API_KEY" http://localhost:8081/stats
```

## 生產部署

預設的 `docker-compose.yml` 是**開發拓撲**（`APP_ENV=dev`、Xdebug、Vite dev
server、原始碼掛載）。正式環境請疊加 `docker-compose.prod.yml`：

```bash
# 除了開發必填的四個密鑰，prod overlay 另外需要 CORS_ORIGINS
#   CORS_ORIGINS=https://admin.example.com   （通知服務生產模式強制非空）
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

overlay 會：

- 建置各服務專用的 `prod` 映像階段（`build.target: prod`）：
  - **php**：不含 Xdebug、`composer install --no-dev` + optimized/authoritative
    autoloader、prod `php.ini`（`display_errors=Off`、OPcache），程式碼與 vendor
    烘入映像；
  - **administration**：`adapter-static` 建置產物，改由 Caddy 提供靜態檔並就地
    反代 `/api`、`/ws`、`/sse`、`/chat` 到後端服務（取代 dev 的 Vite proxy），
    WS 位址於建置時烘為同源 `/ws`；
- 以 `!override` 標籤移除 dev 的原始碼 bind mount，容器改跑烘好的映像
  （需 Docker Compose v2.24+；本 repo 開發環境為 v5.x）；
- 後端切到 `APP_ENV=prod`、`APP_DEBUG=0`、關閉 Xdebug；
- 通知服務進入 `RUN_MODE=production`（強制 `X-API-Key` 與非空 `CORS_ORIGINS`），並開啟佇列／ACK／限流；
- Redis 開啟 AOF 持久化，並為所有長駐服務補上 `restart: unless-stopped`。

> 💡 API 文件（`/api/doc`，Nelmio）只在 `dev` 環境註冊；prod 映像以
> `--no-dev` 建置且不載入該 bundle。

**overlay 尚未涵蓋、需另行處理的強化項**（見 [docs/operations.md](docs/operations.md)）：
以非 root 使用者執行 php 容器、輪替 `POSTGRES_PASSWORD` 預設值並為 chat 建立
獨立 DB 使用者、Redis 加上 `requirepass`、部署監控告警與離機備份。

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

通知服務容器只綁 `127.0.0.1:8081`，對外一律經 Caddy。端點分兩類：

**客戶端頻道**（經 Caddy 對外，JWT 逐連線驗證）：

| 方法 | 端點 | 說明 |
|------|------|------|
| WS | `ws://localhost/ws?token=JWT` | WebSocket 連線 |
| GET | `http://localhost/sse?token=JWT` | SSE 連線 (備援) |

**寫入／管理端點**（server-to-server，**不經 Caddy 對外**，需 `X-API-Key`）：

這些端點（`/api/v1/notifications/{send,send-to-users,broadcast,channel,channels}`、
`/stats`、`/metrics`）只供後端在 Docker 內網呼叫（`http://notification:8081`，
並帶 `X-API-Key: $NOTIFICATION_API_KEY`）。前台要發通知，一律呼叫 **Symfony
後端** 的 `POST /api/v1/notifications/dispatch`（受 `notifications:manage` 權限
保護），由後端轉發——請勿把這些端點重新暴露到 Caddy，否則會繞過權限檢查。

| 方法 | 端點（內網） | 說明 |
|------|------|------|
| POST | `http://notification:8081/api/v1/notifications/send` | 發送給用戶 |
| POST | `http://notification:8081/api/v1/notifications/broadcast` | 廣播給所有人 |
| POST | `http://notification:8081/api/v1/notifications/channel` | 發送到頻道 |
| GET | `http://localhost/health` | 健康檢查（經 Caddy） |
| GET | `http://notification:8081/stats` | 連線統計（需 API key） |
| GET | `http://notification:8081/metrics` | Prometheus 指標（需 API key） |

### 聊天服務

經 Caddy 以 `/chat/*` 前綴轉發（前綴會被剝除）：

| 方法 | 端點 | 說明 |
|------|------|------|
| WS | `ws://localhost/chat/ws?token=JWT` | 聊天 WebSocket |
| GET/POST | `http://localhost/chat/api/v1/conversations` | 會話列表 / 建立會話 |
| GET/POST | `http://localhost/chat/api/v1/conversations/{id}/messages` | 讀取 / 發送訊息 |
| GET | `http://localhost:8082/health` | 健康檢查（直連） |
| GET | `http://localhost:8082/metrics` | Prometheus 指標（直連） |

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

> ⚠️ 通知服務的寫入端點需要 `X-API-Key` 標頭（值為 `NOTIFICATION_API_KEY`）。
> 後端已內建 `NotificationClient`（`App\Modules\Notification\Infrastructure\Client`）
> 會自動帶上該標頭，實務上直接注入它即可；以下手寫範例僅為示意，若自行
> 呼叫務必補上 `'headers' => ['X-API-Key' => $apiKey]`。

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

#### 方法二：Redis Pub/Sub

> ⚠️ **注意**：目前後端實際採用方法一（HTTP，已內建
> `NotificationClient`）；以下 Predis 範例僅為示意。頻道名稱與 payload
> 形狀是嚴格契約——不匹配的訊息會被訂閱端**靜默丟棄**。發布前請務必
> 閱讀 [Redis Pub/Sub 頻道契約](docs/redis-channels.md)。

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
| `APP_SECRET` | **(必填)** | Symfony 密鑰；亦用於加密儲存的 2FA 密鑰（留空會明文落庫） |
| `JWT_SECRET` | **(必填)** | JWT 對稱密鑰，Symfony 與 Notification 共用 |
| `JWT_PASSPHRASE` | **(必填)** | 保護 RS256 私鑰的密語；勿共用、勿提交，換值需 `make rotate-jwt-keys` |
| `NOTIFICATION_API_KEY` | **(必填)** | 後端↔通知服務寫入端點的 `X-API-Key`（至少 16 字元） |
| `JWT_ISSUER` | `ara-platform` | JWT 發行者 |
| `JWT_AUDIENCE` | `ara-services` | JWT 受眾 |

> 上列標「必填」者若未設定，`docker compose up` 會直接失敗並提示缺哪個變數。

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
# 1. 必填密鑰未設定 → compose 報 "XXX must be set"；在 .env 補上
#    APP_SECRET / JWT_SECRET / JWT_PASSPHRASE / NOTIFICATION_API_KEY（make gen-secret）
# 2. 換了 JWT_PASSPHRASE 但沿用舊金鑰 → 私鑰解不開、後端啟動失敗；
#    執行 make rotate-jwt-keys 用新密語重新生成金鑰對
# 3. JWT 金鑰缺失 → notification/chat 啟動失敗，執行 make gen-jwt-keys
#    (若 backend/config/jwt/public.pem 已被 Docker 建成「目錄」，先刪除它再生成)
# 4. 通知寫入端點回 401 → 後端與通知服務的 NOTIFICATION_API_KEY 不一致
# 5. 端口衝突 → 修改 docker-compose.yml 中的端口映射
# 6. 建構失敗 → docker-compose build --no-cache notification
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
│   ├── notification/        # Rust 通知服務 (子模組)
│   └── chat/                # Rust 聊天服務 (子模組)
├── docker/
│   ├── php/                 # FrankenPHP 映像 + entrypoint
│   ├── node/                # 管理面板開發映像
│   ├── caddy/               # Caddyfile (路由設定)
│   ├── postgres/            # PostgreSQL + pg_partman + 初始化腳本
│   └── backup/              # 備份服務映像與腳本
├── docs/
│   ├── operations.md        # 維運指南（功能開關、金鑰輪替、監控）
│   └── redis-channels.md    # Redis Pub/Sub 頻道契約
├── scripts/                 # 測試輔助腳本
├── docker-compose.yml
├── docker-compose.prod.yml     # 生產強化 overlay
├── docker-compose.cluster.yml  # 聊天叢集測試拓撲
├── Makefile
├── .env.example
├── .env                     # 本地配置 (不提交)
└── README.md
```

## 授權

MIT License

## 貢獻

歡迎提交 Issue 和 Pull Request！
