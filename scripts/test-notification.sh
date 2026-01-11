#!/usr/bin/env bash

set -euo pipefail

API_URL="http://localhost:8081/api/v1/notifications/broadcast"

echo "🚀 開始測試通知廣播 API"
echo "➡️  POST ${API_URL}"
echo

response=$(curl -s -X POST "${API_URL}" \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "test.notification",
    "payload": {
      "type": "success",
      "title": "測試通知",
      "message": "通知系統正常運作"
    }
  }'
)

echo "📦 API 回傳結果："
echo "${response}"
echo

# 簡單檢查 success 欄位
if echo "${response}" | grep -q '"success":true'; then
  echo "✅ 通知廣播測試成功"
else
  echo "❌ 通知廣播測試失敗"
  exit 1
fi

