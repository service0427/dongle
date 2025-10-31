#!/bin/bash

#############################################
# SOCKS5 방화벽 규칙 적용 스크립트
# - dongle_config.json에서 활성 포트 감지
# - Whitelist IP만 접근 허용
# - 나머지는 완전 차단
#############################################

CONFIG_FILE="/home/proxy/config/firewall_config.json"
DONGLE_CONFIG="/home/proxy/config/dongle_config.json"
WHITELIST_FILE="/home/proxy/config/whitelist_ips.txt"
LOG_FILE="/home/proxy/logs/firewall/firewall.log"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log "ERROR: Root 권한이 필요합니다. sudo로 실행하세요."
    exit 1
fi

# 설정 파일 확인
if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: 설정 파일 없음: $CONFIG_FILE"
    exit 1
fi

# 방화벽 활성화 여부 확인
ENABLED=$(jq -r '.enabled' "$CONFIG_FILE" 2>/dev/null)
if [ "$ENABLED" != "true" ]; then
    log "INFO: 방화벽이 비활성화되어 있습니다."
    # 기존 규칙 제거
    log "INFO: 기존 SOCKS5 방화벽 규칙 제거"
    iptables-save | grep -v "SOCKS5-WHITELIST" | iptables-restore
    exit 0
fi

# Whitelist 파일 확인
if [ ! -f "$WHITELIST_FILE" ]; then
    log "ERROR: Whitelist 파일 없음: $WHITELIST_FILE"
    exit 1
fi

# 활성 포트 감지
AUTO_DETECT=$(jq -r '.auto_detect_ports' "$CONFIG_FILE" 2>/dev/null)
if [ "$AUTO_DETECT" = "true" ]; then
    if [ ! -f "$DONGLE_CONFIG" ]; then
        log "ERROR: dongle_config.json 없음. init_dongle_config.sh를 먼저 실행하세요."
        exit 1
    fi

    # dongle_config.json에서 socks5_port 추출
    ACTIVE_PORTS=$(jq -r '.interface_mapping[].socks5_port' "$DONGLE_CONFIG" 2>/dev/null | sort -n | tr '\n' ' ')

    if [ -z "$ACTIVE_PORTS" ]; then
        log "ERROR: 활성 SOCKS5 포트를 찾을 수 없습니다."
        exit 1
    fi

    log "INFO: 자동 감지된 포트: $ACTIVE_PORTS"
else
    # 수동 설정 포트 사용
    ACTIVE_PORTS=$(jq -r '.manual_ports[]' "$CONFIG_FILE" 2>/dev/null | sort -n | tr '\n' ' ')
    log "INFO: 수동 설정 포트: $ACTIVE_PORTS"
fi

# Whitelist IP 로드
WHITELIST_IPS=$(cat "$WHITELIST_FILE" | grep -v '^#' | grep -v '^$')
IP_COUNT=$(echo "$WHITELIST_IPS" | wc -l)

if [ -z "$WHITELIST_IPS" ]; then
    log "ERROR: Whitelist가 비어있습니다."
    exit 1
fi

log "INFO: Whitelist IP 개수: $IP_COUNT"

# localhost 허용 여부
ALLOW_LOCALHOST=$(jq -r '.allow_localhost' "$CONFIG_FILE" 2>/dev/null)

# 차단 로그 활성화 여부
LOG_BLOCKED=$(jq -r '.log_blocked' "$CONFIG_FILE" 2>/dev/null)

log "INFO: 방화벽 규칙 적용 시작"

# 1. 기존 SOCKS5 관련 규칙 제거 (모든 규칙 삭제)
log "INFO: 기존 SOCKS5 방화벽 규칙 제거"

# SOCKS5-WHITELIST 코멘트가 있는 모든 규칙 제거
while iptables -D INPUT -m comment --comment "SOCKS5-WHITELIST" -j ACCEPT 2>/dev/null; do :; done
while iptables -D INPUT -m comment --comment "SOCKS5-WHITELIST" -j DROP 2>/dev/null; do :; done
while iptables -D INPUT -m comment --comment "SOCKS5-WHITELIST-LOG" -j LOG 2>/dev/null; do :; done

# 2. 각 포트별로 규칙 적용
for port in $ACTIVE_PORTS; do
    log "INFO: 포트 $port 방화벽 설정"

    # 2-1. localhost 허용 (최우선)
    if [ "$ALLOW_LOCALHOST" = "true" ]; then
        iptables -I INPUT -p tcp -s 127.0.0.1 --dport $port -m comment --comment "SOCKS5-WHITELIST" -j ACCEPT
        iptables -I INPUT -p tcp -s ::1 --dport $port -m comment --comment "SOCKS5-WHITELIST" -j ACCEPT 2>/dev/null
    fi

    # 2-2. Whitelist IP 허용
    while IFS= read -r ip; do
        if [ -n "$ip" ]; then
            iptables -I INPUT -p tcp -s "$ip" --dport $port -m comment --comment "SOCKS5-WHITELIST" -j ACCEPT
        fi
    done <<< "$WHITELIST_IPS"

    # 2-3. 차단 로그 (선택)
    if [ "$LOG_BLOCKED" = "true" ]; then
        iptables -A INPUT -p tcp --dport $port -m limit --limit 10/min -m comment --comment "SOCKS5-WHITELIST-LOG" -j LOG --log-prefix "SOCKS5-BLOCKED: " --log-level 4
    fi

    # 2-4. 나머지 모두 차단
    iptables -A INPUT -p tcp --dport $port -m comment --comment "SOCKS5-WHITELIST" -j DROP
done

log "SUCCESS: 방화벽 규칙 적용 완료"
log "  - 보호된 포트: $ACTIVE_PORTS"
log "  - 허용된 IP: $IP_COUNT 개"
log "  - localhost 허용: $ALLOW_LOCALHOST"
log "  - 차단 로그: $LOG_BLOCKED"

# 3. 적용된 규칙 저장 (선택)
SAVE_RULES=$(jq -r '.save_rules' "$CONFIG_FILE" 2>/dev/null)
if [ "$SAVE_RULES" = "true" ]; then
    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        log "INFO: iptables 규칙 저장됨"
    fi
fi

exit 0
