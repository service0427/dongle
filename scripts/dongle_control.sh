#!/bin/bash

# USB 동글 제어 스크립트
# 서브넷 번호로 동글을 제어할 수 있는 간편한 인터페이스

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

# 사용법 출력
usage() {
    echo "사용법: $0 <서브넷> <동작>"
    echo ""
    echo "서브넷: 11, 12, 13, 14, 15, 16, 18"
    echo "동작:"
    echo "  status  - 동글 상태 확인"
    echo "  on      - 동글 전원 켜기"
    echo "  off     - 동글 전원 끄기"
    echo "  cycle   - 동글 재시작"
    echo "  info    - 동글 정보 표시"
    echo ""
    echo "예시:"
    echo "  $0 11 cycle   # 서브넷 11 동글 재시작"
    echo "  $0 16 status  # 서브넷 16 동글 상태 확인"
    echo "  $0 all status # 모든 동글 상태 확인"
    exit 1
}

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
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "이 작업은 root 권한이 필요합니다"
        echo "사용법: sudo $0 $@"
        exit 1
    fi
}

# 단일 동글 제어
control_dongle() {
    local subnet=$1
    local action=$2
    
    if [ -z "${SUBNET_TO_USB[$subnet]}" ]; then
        log_error "알 수 없는 서브넷: $subnet"
        return 1
    fi
    
    IFS=':' read -r hub port <<< "${SUBNET_TO_USB[$subnet]}"
    
    case $action in
        status)
            echo -e "${GREEN}서브넷 $subnet${NC} (Hub $hub, Port $port) 상태:"
            sudo uhubctl -l $hub -p $port 2>/dev/null | grep "Port $port"
            
            # 네트워크 인터페이스 상태도 확인
            iface=$(ip addr | grep "192.168.$subnet.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
            if [ ! -z "$iface" ]; then
                echo "  네트워크: $iface (192.168.$subnet.100)"
                # ping 테스트
                if ping -c 1 -W 1 192.168.$subnet.1 &>/dev/null; then
                    echo -e "  연결 상태: ${GREEN}정상${NC}"
                else
                    echo -e "  연결 상태: ${RED}응답 없음${NC}"
                fi
            else
                echo -e "  네트워크: ${RED}인터페이스 없음${NC}"
            fi
            ;;
            
        on)
            log_info "서브넷 $subnet 동글 전원 켜기..."
            sudo uhubctl -l $hub -p $port -a on
            ;;
            
        off)
            log_warning "서브넷 $subnet 동글 전원 끄기..."
            sudo uhubctl -l $hub -p $port -a off
            ;;
            
        cycle)
            log_info "서브넷 $subnet 동글 재시작..."
            sudo uhubctl -l $hub -p $port -a cycle
            log_info "네트워크 재연결 대기 중 (15초)..."
            sleep 15
            
            # 재연결 확인
            if ping -c 1 -W 2 192.168.$subnet.1 &>/dev/null; then
                log_info "동글이 성공적으로 재연결되었습니다"
            else
                log_warning "동글이 아직 재연결되지 않았습니다. 추가 대기가 필요할 수 있습니다"
            fi
            ;;
            
        info)
            echo "========================================="
            echo "서브넷 $subnet 동글 정보"
            echo "========================================="
            echo "USB 허브: $hub"
            echo "USB 포트: $port"
            echo "IP 주소: 192.168.$subnet.100"
            echo "SOCKS5 포트: 100$subnet"
            echo "uhubctl 명령: sudo uhubctl -l $hub -p $port"
            
            # 현재 상태
            iface=$(ip addr | grep "192.168.$subnet.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
            if [ ! -z "$iface" ]; then
                echo "네트워크 인터페이스: $iface"
                if ping -c 1 -W 1 192.168.$subnet.1 &>/dev/null; then
                    echo -e "연결 상태: ${GREEN}정상${NC}"
                else
                    echo -e "연결 상태: ${RED}응답 없음${NC}"
                fi
            else
                echo -e "네트워크 인터페이스: ${RED}없음${NC}"
            fi
            ;;
            
        *)
            log_error "알 수 없는 동작: $action"
            return 1
            ;;
    esac
}

# 모든 동글 상태 확인
all_status() {
    echo "========================================="
    echo "모든 동글 상태"
    echo "========================================="
    echo ""
    
    for subnet in 11 12 13 14 15 16 18; do
        control_dongle $subnet status
        echo ""
    done
}

# 메인 로직
if [ $# -lt 2 ]; then
    usage
fi

SUBNET=$1
ACTION=$2

# 전원 제어 동작은 root 권한 필요
if [ "$ACTION" = "on" ] || [ "$ACTION" = "off" ] || [ "$ACTION" = "cycle" ]; then
    check_root
fi

if [ "$SUBNET" = "all" ]; then
    if [ "$ACTION" = "status" ]; then
        all_status
    else
        log_error "all은 status 동작만 지원합니다"
        exit 1
    fi
else
    control_dongle $SUBNET $ACTION
fi