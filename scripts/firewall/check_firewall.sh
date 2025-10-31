#!/bin/bash

#############################################
# SOCKS5 방화벽 상태 확인 스크립트
# - 현재 방화벽 규칙 확인
# - Whitelist 정보 출력
# - 차단 통계 표시
#############################################

CONFIG_FILE="/home/proxy/config/firewall_config.json"
DONGLE_CONFIG="/home/proxy/config/dongle_config.json"
WHITELIST_FILE="/home/proxy/config/whitelist_ips.txt"
BLOCKED_LOG="/var/log/messages"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  SOCKS5 방화벽 상태"
echo "=========================================="
echo ""

# 1. 설정 파일 확인
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}ERROR: 설정 파일이 없습니다.${NC}"
    echo "먼저 init_firewall.sh를 실행하세요."
    exit 1
fi

# 2. 방화벽 활성화 상태
ENABLED=$(jq -r '.enabled' "$CONFIG_FILE" 2>/dev/null)
if [ "$ENABLED" = "true" ]; then
    echo -e "방화벽 상태: ${GREEN}활성화${NC}"
else
    echo -e "방화벽 상태: ${RED}비활성화${NC}"
    exit 0
fi

# 3. Whitelist URL
WHITELIST_URL=$(jq -r '.whitelist_url' "$CONFIG_FILE" 2>/dev/null)
echo "Whitelist URL: $WHITELIST_URL"
echo ""

# 4. 활성 포트 확인
AUTO_DETECT=$(jq -r '.auto_detect_ports' "$CONFIG_FILE" 2>/dev/null)
if [ "$AUTO_DETECT" = "true" ]; then
    if [ -f "$DONGLE_CONFIG" ]; then
        ACTIVE_PORTS=$(jq -r '.interface_mapping[].socks5_port' "$DONGLE_CONFIG" 2>/dev/null | sort -n | tr '\n' ' ')
        PORT_COUNT=$(echo $ACTIVE_PORTS | wc -w)
        echo -e "활성 SOCKS5 포트: ${GREEN}$PORT_COUNT개${NC}"
        echo "  포트 목록: $ACTIVE_PORTS"
    else
        echo -e "${YELLOW}WARNING: dongle_config.json을 찾을 수 없습니다.${NC}"
    fi
else
    ACTIVE_PORTS=$(jq -r '.manual_ports[]' "$CONFIG_FILE" 2>/dev/null | sort -n | tr '\n' ' ')
    PORT_COUNT=$(echo $ACTIVE_PORTS | wc -w)
    echo -e "수동 설정 포트: ${BLUE}$PORT_COUNT개${NC}"
    echo "  포트 목록: $ACTIVE_PORTS"
fi
echo ""

# 5. Whitelist IP 정보
if [ -f "$WHITELIST_FILE" ]; then
    IP_COUNT=$(grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' "$WHITELIST_FILE" | wc -l)
    echo -e "허용된 IP 개수: ${GREEN}$IP_COUNT개${NC}"

    LAST_UPDATE=$(stat -c %y "$WHITELIST_FILE" 2>/dev/null | cut -d'.' -f1)
    echo "마지막 업데이트: $LAST_UPDATE"

    echo ""
    echo "허용된 IP 목록:"
    cat "$WHITELIST_FILE" | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | nl
else
    echo -e "${RED}ERROR: Whitelist 파일이 없습니다.${NC}"
fi
echo ""

# 6. iptables 규칙 확인
RULE_COUNT=$(iptables -L INPUT -n | grep "SOCKS5-WHITELIST" | wc -l)
if [ "$RULE_COUNT" -gt 0 ]; then
    echo -e "적용된 iptables 규칙: ${GREEN}$RULE_COUNT개${NC}"
else
    echo -e "${YELLOW}WARNING: iptables 규칙이 적용되지 않았습니다.${NC}"
fi
echo ""

# 7. localhost 허용 여부
ALLOW_LOCALHOST=$(jq -r '.allow_localhost' "$CONFIG_FILE" 2>/dev/null)
echo "localhost 허용: $ALLOW_LOCALHOST"

# 8. 차단 로그 활성화 여부
LOG_BLOCKED=$(jq -r '.log_blocked' "$CONFIG_FILE" 2>/dev/null)
echo "차단 로그: $LOG_BLOCKED"
echo ""

# 9. 차단 통계 (최근 1시간)
if [ "$LOG_BLOCKED" = "true" ] && [ -f "$BLOCKED_LOG" ]; then
    echo "=========================================="
    echo "  차단 통계 (최근 1시간)"
    echo "=========================================="

    ONE_HOUR_AGO=$(date -d '1 hour ago' '+%b %e %H:%M' 2>/dev/null)
    if [ -n "$ONE_HOUR_AGO" ]; then
        BLOCKED_COUNT=$(grep "SOCKS5-BLOCKED" "$BLOCKED_LOG" 2>/dev/null | \
                       awk -v since="$ONE_HOUR_AGO" '$0 >= since' | wc -l)

        if [ "$BLOCKED_COUNT" -gt 0 ]; then
            echo -e "차단된 시도: ${RED}$BLOCKED_COUNT건${NC}"
            echo ""
            echo "차단된 IP (Top 10):"
            grep "SOCKS5-BLOCKED" "$BLOCKED_LOG" 2>/dev/null | \
                awk -v since="$ONE_HOUR_AGO" '$0 >= since' | \
                grep -oP 'SRC=\K[0-9.]+' | sort | uniq -c | sort -rn | head -10 | \
                awk '{printf "  %s회: %s\n", $1, $2}'
        else
            echo -e "${GREEN}차단된 시도 없음${NC}"
        fi
    fi
    echo ""
fi

# 10. 현재 SOCKS5 연결 상태
echo "=========================================="
echo "  현재 SOCKS5 연결"
echo "=========================================="

for port in $ACTIVE_PORTS; do
    CONN_COUNT=$(ss -tn state established "( dport = :$port or sport = :$port )" 2>/dev/null | grep -v "State" | wc -l)
    if [ "$CONN_COUNT" -gt 0 ]; then
        echo -e "포트 $port: ${GREEN}$CONN_COUNT개 연결${NC}"
    else
        echo "포트 $port: 연결 없음"
    fi
done

echo ""
echo "=========================================="

# 11. 상세 iptables 규칙 보기 (선택)
if [ "$1" = "--detailed" ] || [ "$1" = "-d" ]; then
    echo ""
    echo "=========================================="
    echo "  상세 iptables 규칙"
    echo "=========================================="
    iptables -L INPUT -n -v --line-numbers | grep -A 5 -B 5 "SOCKS5"
fi

exit 0
