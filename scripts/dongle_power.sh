#!/bin/bash

# USB 동글 전체 전원 제어 스크립트

# 색상 코드
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 서브넷과 USB 위치 매핑
declare -A SUBNET_TO_USB
SUBNET_TO_USB[11]="1-3.4:4"
SUBNET_TO_USB[12]="1-3.4:1"
SUBNET_TO_USB[13]="1-3.4:3"
SUBNET_TO_USB[14]="1-3.1:1"
SUBNET_TO_USB[15]="1-3.1:3"
SUBNET_TO_USB[16]="1-3.3:4"
SUBNET_TO_USB[18]="1-3.3:3"

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# root 권한 확인
if [ "$EUID" -ne 0 ]; then 
    log_error "이 스크립트는 root 권한이 필요합니다"
    echo "사용법: sudo $0 [on|off]"
    exit 1
fi

# 사용법 확인
if [ $# -ne 1 ]; then
    echo "사용법: $0 [on|off]"
    echo ""
    echo "  on  - 모든 동글 전원 켜기"
    echo "  off - 모든 동글 전원 끄기"
    exit 1
fi

ACTION=$1

case $ACTION in
    off)
        log_warning "모든 동글 전원을 끕니다..."
        echo ""
        
        for subnet in 11 12 13 14 15 16 18; do
            IFS=':' read -r hub port <<< "${SUBNET_TO_USB[$subnet]}"
            echo -e "${YELLOW}서브넷 $subnet${NC} (Hub $hub, Port $port) 전원 끄는 중..."
            sudo uhubctl -l $hub -p $port -a off 2>&1 | grep -E "Sent power off|New status.*off" || true
            sleep 1  # 각 동글 사이 1초 대기
        done
        
        echo ""
        log_info "모든 동글 전원이 꺼졌습니다"
        ;;
        
    on)
        log_info "모든 동글 전원을 켭니다..."
        echo ""
        
        for subnet in 11 12 13 14 15 16 18; do
            IFS=':' read -r hub port <<< "${SUBNET_TO_USB[$subnet]}"
            echo -e "${GREEN}서브넷 $subnet${NC} (Hub $hub, Port $port) 전원 켜는 중..."
            sudo uhubctl -l $hub -p $port -a on 2>&1 | grep -E "Sent power on|New status.*power" || true
            sleep 2  # 각 동글 사이 2초 대기 (안정적인 연결을 위해)
        done
        
        echo ""
        log_info "모든 동글 전원이 켜졌습니다"
        echo ""
        log_info "네트워크 재연결 대기 중 (15초)..."
        sleep 15
        
        echo ""
        echo "========================================="
        echo "네트워크 연결 상태 확인"
        echo "========================================="
        
        for subnet in 11 12 13 14 15 16 18; do
            if ping -c 1 -W 2 192.168.$subnet.1 &>/dev/null; then
                echo -e "서브넷 $subnet: ${GREEN}연결됨${NC}"
            else
                echo -e "서브넷 $subnet: ${RED}응답 없음${NC}"
            fi
        done
        
        echo ""
        log_info "전원 켜기 완료. 프록시 재시작이 필요할 수 있습니다."
        echo "프록시 재시작: curl http://localhost:8080/toggle/<서브넷번호>"
        ;;
        
    *)
        log_error "잘못된 명령: $ACTION"
        echo "사용법: $0 [on|off]"
        exit 1
        ;;
esac