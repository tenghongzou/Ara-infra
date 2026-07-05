# 維運指南

功能開關、金鑰輪替、監控與分區等維運主題。快速開始請看
[README](../README.md)；Redis 頻道契約請看 [redis-channels.md](redis-channels.md)。

## 通知服務功能開關

五個開關都在根目錄 `.env`（預設全部 `false`），由 docker-compose 傳入
notification 容器。細部調校參數存在於服務端但 compose 目前**只傳開關本身**——
需要調校時把對應變數加進 `docker-compose.yml` 的 `notification.environment`
區塊（完整清單見 `services/notification/README.md` 與 `.env.example`）。

| 開關 | 作用 | 何時開 | 主要調校參數 |
|------|------|--------|--------------|
| `QUEUE_ENABLED` | 離線訊息佇列：使用者離線時通知暫存，重連後自動補發 | 通知不可漏接時（審批、告警） | `QUEUE_MAX_SIZE_PER_USER`、`QUEUE_MESSAGE_TTL_SECONDS`、佇列後端（memory/Redis/PostgreSQL） |
| `ACK_ENABLED` | 送達確認：客戶端回 ACK，後端可查詢送達狀態 | 需要送達稽核時 | ACK timeout（啟動時固定） |
| `RATELIMIT_ENABLED` | Token bucket 限流（HTTP 與 WS 分開計） | 對外暴露或多租戶時 | `RATELIMIT_HTTP_REQUESTS_PER_SECOND`、`RATELIMIT_HTTP_BURST_SIZE`；分散式模式走 Redis |
| `TENANT_ENABLED` | 多租戶隔離：JWT 的 `tenant_id` claim 自動為頻道加命名空間（`{tenant}:{channel}`），連線數按租戶限制 | 多租戶部署 | 後端簽發的 JWT 需帶 `tenant_id` claim（目前 `JwtClaimsListener` 未埋此 claim，啟用前需補） |
| `CLUSTER_ENABLED` | 通知服務多實例：跨節點路由走 Redis Pub/Sub | 單實例連線數不足時 | `CLUSTER_SESSION_TTL_SECONDS`（必須大於心跳間隔）、路由頻道見 redis-channels.md |

聊天服務的對應開關是 `CHAT__CLUSTER__ENABLED`（見下方叢集一節），
訊息通知開關為 `NOTIFICATION_ENABLED` 等（`services/chat` 端設定，預設開）。

## JWT 金鑰輪替

架構前提：**私鑰只在 Symfony 後端**（簽發），notification/chat 只掛載
`backend/config/jwt/public.pem`（驗證）。輪替程序：

```bash
# 1. 產生新金鑰對（覆寫舊檔）
docker compose exec php bin/console lexik:jwt:generate-keypair --overwrite

# 2. 重啟掛載公鑰的服務（唯讀掛載，須重啟才會讀到新檔）
docker compose restart notification chat

# 3.（正式環境）同時更換 backend/.env 的 JWT_PASSPHRASE
```

影響範圍：舊私鑰簽的 JWT 立刻全部失效（access token TTL 30 分鐘、
使用者會被要求重新登入）；refresh token 存在資料庫、不受金鑰輪替影響，
重新整理後會取得新金鑰簽發的 JWT。**不支援雙金鑰過渡期**——lexik 只設定
單一公鑰，輪替請安排在低峰時段。

`JWT_SECRET`（對稱密鑰，`.env`）目前僅作為 compose 啟動檢查與部分服務的
HS256 後備，RS256 主流程不使用；輪替它不影響既有 token。

## Prometheus 監控

notification 與 chat 都在各自埠上暴露 `/metrics`：

| 服務 | 直連 | 經 Caddy |
|------|------|----------|
| notification | `http://localhost:8081/metrics` | `http://localhost/metrics`（Caddyfile 已轉發） |
| chat | `http://localhost:8082/metrics` | `http://localhost/chat/metrics` |

Prometheus 抓取設定範例（Prometheus 跑在同一個 Docker 網路時）：

```yaml
scrape_configs:
  - job_name: ara-notification
    static_configs:
      - targets: ['notification:8081']
  - job_name: ara-chat
    static_configs:
      - targets: ['chat:8082']
```

兩個服務也支援 OpenTelemetry（OTLP gRPC，`OTEL_*` 環境變數，預設關），
詳見各服務 README。

## PostgreSQL 分區（pg_partman）

`docker/postgres` 映像內建 pg_partman，初始化腳本會在 `symfony` 與
`ara_chat` 兩個資料庫建立 extension。目前**實際使用分區的只有聊天服務**：
`messages` 表按日期 range 分區、預設保留 30 天，分區維護由聊天服務的
遷移與背景任務處理。後端（symfony 庫）尚未使用分區——extension 已就緒，
audit_logs/notifications 這類大表未來可遷移。

分區狀態檢查：

```bash
make psql
# 切到聊天庫
\c ara_chat
SELECT parent_table, retention FROM partman.part_config;
\dt+ messages*
```

## 聊天服務叢集模式

```bash
docker compose -f docker-compose.yml -f docker-compose.cluster.yml up -d
```

- 啟動 3 個 chat 節點（8082/8083/8084），跨節點訊息路由走 Redis
  （頻道 `chat:cluster:route`，session 存 `chat:cluster:sessions*`）
- 節點皆以 RS256 驗證 JWT、共用 `ara_chat` 資料庫；migration 只由
  node-1 執行（其餘節點 `RUN_MIGRATIONS=false`）
- 這是**測試用**拓撲：正式環境需在節點前加負載平衡器
  （Caddyfile 目前只指向 `chat:8082`）

通知服務叢集則是設 `CLUSTER_ENABLED=true` 後直接
`docker compose up -d --scale notification=N`（需先移除固定
`container_name` 與 host port 綁定）。

## 備份與還原

| 操作 | 指令 |
|------|------|
| 立即備份 | `make backup-now` |
| 還原最新備份 | `make backup-restore` |
| 看備份日誌 | `make backup-logs` |

排程與保留天數由 `.env` 的 `BACKUP_SCHEDULE`、`BACKUP_RETENTION_DAYS`
控制。備份涵蓋 `symfony` + `ara_chat` 兩個資料庫與 Redis snapshot。
排程由 busybox crond 執行（任務寫在 root 的 crontab，容器每次啟動時
重建）；確認排程存活：`docker compose exec backup cat /etc/crontabs/root`。

### 啟用 S3 上傳

AWS 憑證**不放環境變數**（`docker inspect` 可見）。兩種方式擇一：

1. **IAM role**（在 AWS 上跑時的首選）：主機掛 instance role，
   aws-cli 自動取得憑證，什麼都不用設。
2. **Docker secret**（其他環境）：建立 `secrets/aws-credentials`
   （已在 .gitignore），內容為標準 AWS credentials 格式，然後用
   疊加檔啟動：
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.s3.yml up -d backup
   ```

之後在 `.env` 設 `S3_BACKUP_ENABLED=true` 與 `S3_BACKUP_BUCKET`。

## 服務埠曝露原則

notification（8081）與 chat（8082）只綁 `127.0.0.1`——本機開發仍可
直連 `localhost:808x`，但外部流量一律經 Caddy（80/443）的路由進入
（`/ws`、`/sse`、`/chat/*`）。如果正式環境的前端設定了直連
`:8081`/`:8082` 的 URL，改為走 Caddy 路徑即可。
