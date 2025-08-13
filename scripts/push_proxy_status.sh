#!/bin/bash
#
# 프록시 상태를 mkt.techb.kr로 전송하고 자동 토글 체크
# 1분마다 크론으로 실행
#

LOG_FILE="/home/proxy/logs/push_status.log"
AUTO_TOGGLE_LOG="/home/proxy/logs/auto_toggle.log"

# 로그 디렉토리 생성
mkdir -p /home/proxy/logs

# 로그 함수
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 자동 토글 로그 함수
log_toggle() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$AUTO_TOGGLE_LOG"
}

# 로컬 API에서 상태 가져오기
PROXY_STATUS=$(curl -s http://localhost:8080/status)

# 상태 확인 - API가 다운되었으면 재시작
if [ -z "$PROXY_STATUS" ]; then
    log_message "WARNING: API is down, attempting restart..."
    systemctl restart dongle-toggle-api
    sleep 2
    
    # 재시도
    PROXY_STATUS=$(curl -s http://localhost:8080/status)
    if [ -z "$PROXY_STATUS" ]; then
        log_message "ERROR: Failed to get proxy status after restart"
        exit 1
    fi
    log_message "INFO: API restarted successfully"
fi

# 서버 외부 IP 동적으로 가져오기
SERVER_IP=$(curl -s -m 3 http://techb.kr/ip.php 2>/dev/null | head -1)
if [ -z "$SERVER_IP" ]; then
    # 실패시 메인 인터페이스 IP 사용
    SERVER_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
fi
# 여전히 없으면 기본값 사용
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="0.0.0.0"
fi

# 서버가 기대하는 형식으로 변환
FORMATTED_STATUS=$(echo "$PROXY_STATUS" | SERVER_IP="$SERVER_IP" python3 -c "
import json, sys
from datetime import datetime
import os

try:
    data = json.loads(sys.stdin.read())
    server_ip = os.environ.get('SERVER_IP')
    
    # 서버가 기대하는 형식으로 변환
    formatted = {
        'status': data.get('status', 'ready'),
        'timestamp': data.get('timestamp', ''),
        'last_heartbeat_at': datetime.now().isoformat(),
        'available_proxies': data.get('available_proxies', []),
        'proxy_count': len(data.get('available_proxies', [])),
        'server_ip': server_ip
    }
    
    print(json.dumps(formatted))
except Exception as e:
    # 변환 실패시 원본 데이터 사용
    print(sys.stdin.read())
" 2>/dev/null)

# 변환된 데이터 사용, 실패시 원본 사용
if [ -z "$FORMATTED_STATUS" ]; then
    FORMATTED_STATUS="$PROXY_STATUS"
fi

# mkt.techb.kr로 상태 전송
RESPONSE=$(curl -s -X POST http://mkt.techb.kr:3001/api/proxy \
  -H "Content-Type: application/json" \
  -d "$FORMATTED_STATUS" \
  -w "\nHTTP_CODE:%{http_code}")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

# 프록시 개수 추출
PROXY_COUNT=$(echo "$PROXY_STATUS" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    count = len(data.get('available_proxies', []))
    print(count)
except:
    print('0')
" 2>/dev/null)

# 허브서버 응답 출력 (수동 실행시)
# 크론이 아닌 직접 실행인지 확인 (크론은 환경변수가 다름)
if [ -z "$CRON_JOB" ] && [ "$0" != "/bin/bash" ]; then
    echo "==================== HUB SERVER RESPONSE ===================="
    echo "HTTP Code: $HTTP_CODE"
    echo "Response Body:"
    if [ -n "$BODY" ] && [ "$BODY" != "" ]; then
        echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    else
        echo "(Empty response body)"
    fi
    echo "Active Proxies: $PROXY_COUNT"
    echo "============================================================="
fi

# 결과 로깅
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    log_message "SUCCESS: Status pushed (HTTP $HTTP_CODE) - Active proxies: $PROXY_COUNT"
else
    log_message "FAILED: Push failed (HTTP $HTTP_CODE) - Response: $BODY"
fi

# 로그 파일 크기 제한 (10MB)
if [ -f "$LOG_FILE" ]; then
    log_size=$(stat -c%s "$LOG_FILE")
    if [ "$log_size" -gt 10485760 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d)"
        log_message "Log rotated"
    fi
fi

# 마지막 전송 상태 저장 (디버깅용)
echo "$FORMATTED_STATUS" > "/home/proxy/logs/last_push_status.json"

# 자동 토글 기능 제거됨
# 외부 웹 API 명령으로만 토글 제어
