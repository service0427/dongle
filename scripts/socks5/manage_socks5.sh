#!/bin/bash

# SOCKS5 개별/전체 관리 스크립트
# 사용법:
#   manage_socks5.sh start 11      # 11번만 시작
#   manage_socks5.sh stop 11        # 11번만 중지
#   manage_socks5.sh restart 11     # 11번만 재시작
#   manage_socks5.sh start all      # 전체 시작
#   manage_socks5.sh stop all       # 전체 중지
#   manage_socks5.sh restart all    # 전체 재시작
#   manage_socks5.sh status         # 전체 상태 확인
#   manage_socks5.sh status 11      # 11번 상태 확인

CONFIG_FILE="/home/proxy/config/dongle_config.json"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 설정된 모든 서브넷 가져오기
get_all_subnets() {
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE" | jq -r '.interface_mapping | keys[]' 2>/dev/null
    else
        # 기본값: 11-18
        seq 11 18
    fi
}

# 서비스 상태 확인
check_service_status() {
    local subnet=$1
    local service_name="dongle-socks5-${subnet}"
    
    if systemctl is-active --quiet "$service_name"; then
        echo -e "${GREEN}✓${NC} Dongle $subnet: ${GREEN}active${NC}"
        return 0
    else
        echo -e "${RED}✗${NC} Dongle $subnet: ${RED}inactive${NC}"
        return 1
    fi
}

# 서비스 시작
start_service() {
    local subnet=$1
    local service_name="dongle-socks5-${subnet}"
    
    echo -n "Starting SOCKS5 for dongle $subnet... "
    if systemctl start "$service_name" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

# 서비스 중지
stop_service() {
    local subnet=$1
    local service_name="dongle-socks5-${subnet}"
    
    echo -n "Stopping SOCKS5 for dongle $subnet... "
    if systemctl stop "$service_name" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

# 서비스 재시작
restart_service() {
    local subnet=$1
    local service_name="dongle-socks5-${subnet}"
    
    echo -n "Restarting SOCKS5 for dongle $subnet... "
    if systemctl restart "$service_name" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
}

# 명령 처리
case "$1" in
    start)
        if [ "$2" == "all" ] || [ -z "$2" ]; then
            echo -e "${YELLOW}Starting all SOCKS5 services...${NC}"
            for subnet in $(get_all_subnets); do
                start_service "$subnet"
            done
        else
            start_service "$2"
        fi
        ;;
        
    stop)
        if [ "$2" == "all" ] || [ -z "$2" ]; then
            echo -e "${YELLOW}Stopping all SOCKS5 services...${NC}"
            for subnet in $(get_all_subnets); do
                stop_service "$subnet"
            done
        else
            stop_service "$2"
        fi
        ;;
        
    restart)
        if [ "$2" == "all" ] || [ -z "$2" ]; then
            echo -e "${YELLOW}Restarting all SOCKS5 services...${NC}"
            for subnet in $(get_all_subnets); do
                restart_service "$subnet"
            done
        else
            restart_service "$2"
        fi
        ;;
        
    status)
        if [ -z "$2" ]; then
            echo -e "${YELLOW}=== SOCKS5 Service Status ===${NC}"
            for subnet in $(get_all_subnets); do
                check_service_status "$subnet"
            done
        else
            check_service_status "$2"
        fi
        ;;
        
    *)
        echo "Usage: $0 {start|stop|restart|status} [subnet|all]"
        echo "Examples:"
        echo "  $0 start 11      # Start SOCKS5 for dongle 11"
        echo "  $0 restart all   # Restart all SOCKS5 services"
        echo "  $0 status        # Check status of all services"
        exit 1
        ;;
esac