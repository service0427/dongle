#!/bin/bash
#
# 프록시 상태를 mkt.techb.kr로 전송하고 USB 허브 상태 확인
# 1분마다 크론으로 실행
#

LOG_FILE="/home/proxy/logs/push_status.log"
AUTO_TOGGLE_LOG="/home/proxy/logs/auto_toggle.log"
CONFIG_FILE="/home/proxy/config/dongle_config.json"

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

# 메인 인터페이스 IP 동적으로 가져오기
MAIN_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
if [ -z "$MAIN_IP" ]; then
    # 실패시 eno1 인터페이스 직접 확인
    MAIN_IP=$(ip addr show eno1 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
fi
# 여전히 없으면 기본값
if [ -z "$MAIN_IP" ]; then
    MAIN_IP="0.0.0.0"
fi

# 로컬 API에서 상태 가져오기
PROXY_STATUS=$(curl -s http://localhost/status)

# 상태 확인 - API가 다운되었으면 재시작
if [ -z "$PROXY_STATUS" ]; then
    log_message "WARNING: API is down, attempting restart..."
    sudo systemctl restart dongle-toggle-api
    sleep 2
    
    # 재시도
    PROXY_STATUS=$(curl -s http://localhost/status)
    if [ -z "$PROXY_STATUS" ]; then
        log_message "ERROR: Failed to get proxy status after restart"
        exit 1
    fi
    log_message "INFO: API restarted successfully"
fi

# USB 허브 상태 확인 (uhubctl 사용)
USB_STATUS=$(sudo uhubctl 2>/dev/null | grep "HUAWEI_MOBILE" || echo "")

# dongle_config.json 읽기 (있으면)
EXPECTED_COUNT=0
if [ -f "$CONFIG_FILE" ]; then
    EXPECTED_COUNT=$(cat "$CONFIG_FILE" | grep '"expected_count"' | grep -oE '[0-9]+' | head -1)
fi

# 서버가 기대하는 형식으로 변환 (Python 스크립트 통합)
FORMATTED_STATUS=$(echo "$PROXY_STATUS" | \
    MAIN_IP="$MAIN_IP" \
    USB_STATUS="$USB_STATUS" \
    EXPECTED_COUNT="$EXPECTED_COUNT" \
    CONFIG_FILE="$CONFIG_FILE" \
    python3 -c "
import json, sys, os
from datetime import datetime
import re

try:
    data = json.loads(sys.stdin.read())
    main_ip = os.environ.get('MAIN_IP', '0.0.0.0')
    usb_status = os.environ.get('USB_STATUS', '')
    expected_count = int(os.environ.get('EXPECTED_COUNT', '0'))
    config_file = os.environ.get('CONFIG_FILE', '')
    
    # USB 상태 파싱 - 각 허브/포트별 동글 감지
    connected_ports = set()
    for line in usb_status.split('\\n'):
        if 'HUAWEI_MOBILE' in line:
            # 포트 번호 추출 (예: Port 1, Port 2)
            port_match = re.search(r'Port ([0-9]+):', line)
            # 허브 정보도 함께 추출 가능
            if port_match:
                # 실제 subnet 매핑이 필요하면 추가 로직 구현
                pass
    
    # 물리적 동글 개수
    physical_count = len(usb_status.split('HUAWEI_MOBILE')) - 1 if usb_status else 0
    
    # 프록시 정보 분석 (connected는 이미 toggle_api.js에서 제공됨)
    proxies = data.get('available_proxies', [])
    connected_count = 0
    disconnected_ports = []
    
    for proxy in proxies:
        # connected 상태 카운트 (이미 존재하는 필드 사용)
        if proxy.get('connected', False):
            connected_count += 1
        else:
            # proxy_url에서 포트 번호 추출
            if 'proxy_url' in proxy:
                port = proxy['proxy_url'].split(':')[-1]
                disconnected_ports.append(port)
        
        # proxy_url의 IP를 메인 IP로 업데이트
        if 'proxy_url' in proxy and main_ip != '0.0.0.0':
            parts = proxy['proxy_url'].split(':')
            if len(parts) == 3:
                proxy['proxy_url'] = f'{parts[0]}:{parts[1].split(\"//\")[0]}//{main_ip}:{parts[2]}'
    
    # 서버가 기대하는 형식으로 변환
    formatted = {
        'status': data.get('status', 'ready'),
        'timestamp': data.get('timestamp', ''),
        'last_heartbeat_at': datetime.now().isoformat(),
        'server_ip': main_ip,
        'available_proxies': proxies,
        'proxy_count': len(proxies),
        'dongle_check': {
            'expected': expected_count,
            'physical': physical_count,
            'connected': connected_count,
            'disconnected_ports': disconnected_ports
        }
    }
    
    # 설정 파일 정보 추가 (있으면)
    if config_file and os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
                formatted['dongle_check']['hub_info'] = config.get('hub_info', {})
        except:
            pass
    
    print(json.dumps(formatted))
except Exception as e:
    # 변환 실패시 원본 데이터에 최소 정보 추가
    try:
        data = json.loads(sys.stdin.read())
    except:
        data = {}
    data['server_ip'] = os.environ.get('MAIN_IP', '0.0.0.0')
    print(json.dumps(data))
" 2>/dev/null)

# 변환된 데이터 사용, 실패시 원본 사용
if [ -z "$FORMATTED_STATUS" ]; then
    # 최소한 server_ip는 추가
    FORMATTED_STATUS=$(echo "$PROXY_STATUS" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
data['server_ip'] = '$MAIN_IP'
print(json.dumps(data))
" 2>/dev/null || echo "$PROXY_STATUS")
fi

# mkt.techb.kr로 상태 전송
RESPONSE=$(curl -s -X POST http://61.84.75.37:3001/api/proxy \
  -H "Content-Type: application/json" \
  -d "$FORMATTED_STATUS" \
  -w "\nHTTP_CODE:%{http_code}")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

# 프록시 개수 추출
PROXY_COUNT=$(echo "$FORMATTED_STATUS" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    connected = sum(1 for p in data.get('available_proxies', []) if p.get('connected', False))
    total = len(data.get('available_proxies', []))
    print(f'{connected}/{total}')
except:
    print('0/0')
" 2>/dev/null)

# 허브서버 응답 출력 (수동 실행시)
# 크론이 아닌 직접 실행인지 확인 (크론은 환경변수가 다름)
if [ -z "$CRON_JOB" ] && [ "$0" != "/bin/bash" ]; then
    echo "==================== HUB SERVER RESPONSE ===================="
    echo "HTTP Code: $HTTP_CODE"
    echo "Server IP: $MAIN_IP"
    echo "Response Body:"
    if [ -n "$BODY" ] && [ "$BODY" != "" ]; then
        echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    else
        echo "(Empty response body)"
    fi
    echo "Active Proxies: $PROXY_COUNT (connected/total)"
    
    # USB 상태 요약
    PHYSICAL=$(sudo uhubctl | grep -c "HUAWEI_MOBILE" || echo 0)
    echo "Physical Dongles: $PHYSICAL"
    if [ "$EXPECTED_COUNT" -gt 0 ]; then
        echo "Expected Dongles: $EXPECTED_COUNT"
        if [ "$PHYSICAL" -ne "$EXPECTED_COUNT" ]; then
            echo "WARNING: Physical dongle count mismatch!"
        fi
    fi
    echo "============================================================="
fi

# 결과 로깅
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    log_message "SUCCESS: Status pushed (HTTP $HTTP_CODE) - Active: $PROXY_COUNT, IP: $MAIN_IP"
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

# 동글 개수 불일치 경고
if [ "$EXPECTED_COUNT" -gt 0 ]; then
    PHYSICAL=$(sudo uhubctl | grep -c "HUAWEI_MOBILE" || echo 0)
    if [ "$PHYSICAL" -ne "$EXPECTED_COUNT" ]; then
        log_message "WARNING: Dongle count mismatch - Expected: $EXPECTED_COUNT, Physical: $PHYSICAL"
    fi
fi