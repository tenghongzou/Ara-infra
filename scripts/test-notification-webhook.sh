#!/bin/bash

# Notification Service Webhook Test Script
# Tests various notification endpoints to verify frontend connectivity

set -e

# Configuration
NOTIFICATION_HOST="${NOTIFICATION_HOST:-http://localhost:8081}"
API_KEY="${API_KEY:-your-api-key}"
TEST_USER_ID="${TEST_USER_ID:-test-user-123}"
TEST_CHANNEL="${TEST_CHANNEL:-test-channel}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_test() {
    echo -e "\n${YELLOW}▶ Test: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local name="$1"
    local response="$2"
    local http_code="$3"

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        print_success "$name (HTTP $http_code)"
        echo "Response: $response"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "$name (HTTP $http_code)"
        echo "Response: $response"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Main tests
print_header "Notification Service Webhook Tests"
echo "Host: $NOTIFICATION_HOST"
echo "API Key: ${API_KEY:0:10}..."
echo "Test User: $TEST_USER_ID"
echo "Test Channel: $TEST_CHANNEL"

# 1. Health Check (no auth required)
print_test "Health Check"
response=$(curl -s -w "\n%{http_code}" "$NOTIFICATION_HOST/health" 2>/dev/null)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')
run_test "Health Check" "$body" "$http_code" || true

# 2. Send notification to single user
print_test "Send Notification to Single User"
response=$(curl -s -w "\n%{http_code}" -X POST "$NOTIFICATION_HOST/api/v1/notifications/send" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "target_user_id": "'"$TEST_USER_ID"'",
        "event_type": "test.webhook",
        "payload": {
            "message": "Test notification from webhook test script",
            "timestamp": "'"$(date -Iseconds)"'"
        },
        "priority": "High"
    }' 2>/dev/null)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')
run_test "Send to Single User" "$body" "$http_code" || true

# 3. Send notification to multiple users
print_test "Send Notification to Multiple Users"
response=$(curl -s -w "\n%{http_code}" -X POST "$NOTIFICATION_HOST/api/v1/notifications/send-to-users" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "target_user_ids": ["'"$TEST_USER_ID"'", "user-2", "user-3"],
        "event_type": "test.multi_user",
        "payload": {
            "message": "Multi-user test notification",
            "timestamp": "'"$(date -Iseconds)"'"
        },
        "priority": "Normal"
    }' 2>/dev/null)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')
run_test "Send to Multiple Users" "$body" "$http_code" || true

# 4. Broadcast notification
print_test "Broadcast Notification"
response=$(curl -s -w "\n%{http_code}" -X POST "$NOTIFICATION_HOST/api/v1/notifications/broadcast" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "event_type": "test.broadcast",
        "payload": {
            "message": "Broadcast test notification",
            "timestamp": "'"$(date -Iseconds)"'"
        },
        "priority": "Normal"
    }' 2>/dev/null)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')
run_test "Broadcast" "$body" "$http_code" || true

# 5. Send to channel
print_test "Send to Channel"
response=$(curl -s -w "\n%{http_code}" -X POST "$NOTIFICATION_HOST/api/v1/notifications/channel" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "channel": "'"$TEST_CHANNEL"'",
        "event_type": "test.channel",
        "payload": {
            "message": "Channel test notification",
            "timestamp": "'"$(date -Iseconds)"'"
        },
        "priority": "High"
    }' 2>/dev/null)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')
run_test "Send to Channel" "$body" "$http_code" || true

# 6. Send to multiple channels
print_test "Send to Multiple Channels"
response=$(curl -s -w "\n%{http_code}" -X POST "$NOTIFICATION_HOST/api/v1/notifications/channels" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "channels": ["'"$TEST_CHANNEL"'", "orders", "alerts"],
        "event_type": "test.multi_channel",
        "payload": {
            "message": "Multi-channel test notification",
            "timestamp": "'"$(date -Iseconds)"'"
        },
        "priority": "Normal"
    }' 2>/dev/null)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')
run_test "Send to Multiple Channels" "$body" "$http_code" || true

# 7. Batch notifications
print_test "Batch Notifications"
response=$(curl -s -w "\n%{http_code}" -X POST "$NOTIFICATION_HOST/api/v1/notifications/batch" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "notifications": [
            {
                "target": {"type": "user", "value": "'"$TEST_USER_ID"'"},
                "event_type": "test.batch.user",
                "payload": {"index": 1, "type": "user"}
            },
            {
                "target": {"type": "channel", "value": "'"$TEST_CHANNEL"'"},
                "event_type": "test.batch.channel",
                "payload": {"index": 2, "type": "channel"}
            },
            {
                "target": {"type": "broadcast"},
                "event_type": "test.batch.broadcast",
                "payload": {"index": 3, "type": "broadcast"}
            }
        ],
        "options": {
            "stop_on_error": false,
            "deduplicate": true
        }
    }' 2>/dev/null)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')
run_test "Batch Notifications" "$body" "$http_code" || true

# 8. Get stats
print_test "Get Statistics"
response=$(curl -s -w "\n%{http_code}" "$NOTIFICATION_HOST/stats" \
    -H "X-API-Key: $API_KEY" 2>/dev/null)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')
run_test "Get Stats" "$body" "$http_code" || true

# 9. List channels
print_test "List Channels"
response=$(curl -s -w "\n%{http_code}" "$NOTIFICATION_HOST/api/v1/channels" \
    -H "X-API-Key: $API_KEY" 2>/dev/null)
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')
run_test "List Channels" "$body" "$http_code" || true

# Summary
print_header "Test Summary"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    print_success "All tests passed!"
    exit 0
else
    print_error "Some tests failed"
    exit 1
fi
