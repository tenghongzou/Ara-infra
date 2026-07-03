# Redis Pub/Sub 頻道契約

本文件是各服務之間 Redis Pub/Sub 的**唯一約定來源**。頻道名稱與 payload
形狀在發布端與訂閱端都是程式碼裡的字串——不匹配時訊息會被靜默丟棄
（訂閱端只留一條 WARN log），不會有任何錯誤回報給發布端。改動任何一側
之前，請先更新本文件並核對另一側。

## 總覽：誰發布、誰訂閱

```
┌──────────────┐  HTTP /api/v1/notifications/*   ┌───────────────────────┐
│ Symfony 後端 │ ───────────────────────────────▶ │                       │
│  (PHP)       │      （不使用 Redis 發布）        │  Notification Service │
└──────────────┘                                  │  (Rust, port 8081)    │
                                                  │                       │
┌──────────────┐  PUBLISH notification:user:{id}  │  PSUBSCRIBE           │
│ Chat Service │ ───────────────────────────────▶ │  notification:user:*  │
│ (Rust, 8082) │                                  │  notification:broadcast│
└──────────────┘                                  │  notification:channel:*│
                                                  └───────────────────────┘
```

- **後端 → 通知服務走 HTTP**（`NotificationClient`，見
  `backend/src/Modules/Notification/Infrastructure/Client/NotificationClient.php`）。
  後端**沒有** Redis 發布路徑；README 的 Predis 範例僅為示意，若要改走
  Redis 必須遵循本契約。
- **聊天服務 → 通知服務走 Redis Pub/Sub**（本契約的主要使用者）。

## 通知事件頻道

### 頻道名稱

| 頻道 | 用途 | 目標來源 |
|------|------|----------|
| `notification:user:{user_id}` | 發給單一使用者（所有裝置） | payload 的 `target` |
| `notification:broadcast` | 廣播給所有連線 | 無 |
| `notification:channel:{name}` | 發給頻道訂閱者 | payload 的 `target` |

**重要**：頻道名稱只影響「訂閱端收不收得到」；實際的分發目標
**完全取自 payload**（`type` + `target` 欄位），訂閱端不會從頻道名稱
解析 user id。頻道名與 payload 不一致時以 payload 為準。

### 訂閱端設定

通知服務由 `REDIS_CHANNELS` 環境變數（逗號分隔）決定訂閱哪些頻道，
含 `*`/`?`/`[` 的用 PSUBSCRIBE、其餘用 SUBSCRIBE。預設值
（也是 docker-compose.yml 設定的值）：

```
REDIS_CHANNELS=notification:user:*,notification:broadcast,notification:channel:*
```

實作：`services/notification/src/domain/notification/triggers/redis.rs`

### Payload 格式

```json
{
  "type": "user",
  "target": "0198c2f1-…-uuid",
  "event": {
    "event_type": "chat.message",
    "payload": { "任意": "JSON 物件" },
    "priority": "Normal",
    "ttl": 3600,
    "correlation_id": "optional-trace-id"
  },
  "tenant_id": "optional-tenant"
}
```

| 欄位 | 型別 | 必填 | 說明 |
|------|------|------|------|
| `type` | string | ✔ | 目標類型：`user` / `users` / `broadcast` / `channel` / `channels` |
| `target` | string 或 string[] | 視 type | `user`/`channel` 用字串、`users`/`channels` 用陣列、`broadcast` 免填 |
| `event.event_type` | string | ✔ | 事件識別字串，見下方慣例 |
| `event.payload` | object | ✔ | 事件內容，通知服務原樣轉發 |
| `event.priority` | string | ✘ | **PascalCase**：`Low` / `Normal` / `High` / `Critical`（預設 `Normal`） |
| `event.ttl` | number | ✘ | 離線佇列存活秒數 |
| `event.correlation_id` | string | ✘ | 追蹤用 ID（後端 notifications 表有索引） |
| `tenant_id` | string | ✘ | 多租戶隔離（`TENANT_ENABLED=true` 時生效） |

訂閱端反序列化結構：`RedisNotificationMessage`
（`services/notification/src/domain/notification/triggers/redis.rs`）。

**常見地雷**：`priority` 是 PascalCase（`"High"`），小寫 `"high"` 會導致
整則訊息解析失敗而被丟棄。

### event_type 慣例

| 前綴 | 發布者 | 事件 |
|------|--------|------|
| `chat.message` | chat service | 離線使用者收到新訊息（未靜音的會話才發） |
| `chat.mention` | chat service | 被 @提及 |
| `chat.reaction` | chat service | 自己的訊息收到表情回應（僅 add，不含 remove） |
| `notification.info/success/warning/error` | 後端（經 HTTP） | 一般通知 |
| `security.alert`、`system.notification`、`subscription.reminder` | 後端（經 HTTP） | 對應後端 Notification TYPE_* |
| `permissions.changed` | 後端（經 HTTP） | 權限快取失效訊號：前端收到後靜默重抓權限，**不顯示為通知**（角色權限編輯、使用者角色變更時發出） |

聊天事件的 `event.payload` 形狀見
`services/chat/src/domain/notification/types.rs` 的 `NotificationPayload`
（conversation_id、message_id、sender_id、sender_name、content_preview、
emoji、action）。

## 失敗模式與除錯

- **Payload 解析失敗 / 未知的 `type`**：通知服務記一條 WARN
  （含 channel 與原始 payload）後**丟棄**，發布端不會收到任何回饋。
- 除錯步驟：
  ```bash
  # 即時監看實際流過的訊息
  docker compose exec redis redis-cli PSUBSCRIBE "notification:*"

  # 看訂閱端是否在丟棄訊息
  docker compose logs notification | grep -i "failed to parse"
  ```

## 叢集內部頻道（勿佔用）

以下頻道是各服務叢集模式的內部路由通道，與通知事件契約無關，
其他服務**不得**發布或訂閱：

| 頻道 | 服務 | 設定鍵（預設值） |
|------|------|------------------|
| `ara:cluster:route` | notification | `CLUSTER_ROUTING_CHANNEL` |
| `chat:cluster:route` | chat | `CHAT__CLUSTER__ROUTING_CHANNEL` |
| `chat:cluster:sessions*`（key prefix） | chat | `CHAT__CLUSTER__SESSION_PREFIX` |

## 新增發布者檢查清單

1. 頻道名稱符合上表；新的頻道模式需同步加進 `REDIS_CHANNELS`
   （docker-compose.yml 與 `.env.example`）。
2. Payload 通過上方欄位表——特別是 `priority` 的 PascalCase。
3. `event_type` 加入本文件的慣例表。
4. 用 `redis-cli PSUBSCRIBE` + 通知服務 log 實測一次端到端。
5. 更新本文件。
