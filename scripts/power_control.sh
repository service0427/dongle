#!/bin/bash

#============================================================
# USB 동글 통합 전원 제어 스크립트
# 
# 사용법:
#   ./power_control.sh off <subnet>    # 개별 동글 끄기
#   ./power_control.sh on <subnet>     # 개별 동글 켜기
#   ./power_control.sh off all         # 모든 동글 끄기
#   ./power_control.sh on all          # 모든 동글 켜기
#   ./power_control.sh status          # 전체 상태 확인
#============================================================

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 매핑 파일 경로
MAPPING_FILE="/home/proxy/scripts/usb_mapping.json"

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
        log_error "이 스크립트는 root 권한이 필요합니다"
        echo "사용법: sudo $0 $@"
        exit 1
    fi
}

# uhubctl 명령 확인
check_uhubctl() {
    if ! command -v uhubctl &> /dev/null; then
        log_error "uhubctl이 설치되지 않았습니다"
        echo "설치: sudo /home/proxy/scripts/utils/install_uhubctl.sh"
        exit 1
    fi
}

# USB 매핑 로드
load_mapping() {
    if [ ! -f "$MAPPING_FILE" ]; then
        log_error "USB 매핑 파일이 없습니다: $MAPPING_FILE"
        exit 1
    fi
}

# 개별 동글 전원 제어
control_single_dongle() {
    local action=$1
    local subnet=$2
    
    # JSON에서 허브와 포트 정보 추출
    local hub=$(python3 -c "
import json
with open('$MAPPING_FILE', 'r') as f:
    data = json.load(f)
    if '$subnet' in data:
        print(data['$subnet']['hub'])
    else:
        print('')
")
    
    local port=$(python3 -c "
import json
with open('$MAPPING_FILE', 'r') as f:
    data = json.load(f)
    if '$subnet' in data:
        print(data['$subnet']['port'])
    else:
        print('')
")
    
    if [ -z "$hub" ] || [ -z "$port" ]; then
        log_error "동글 $subnet의 매핑 정보를 찾을 수 없습니다"
        return 1
    fi
    
    log_info "동글 $subnet (Hub: $hub, Port: $port) 전원 ${action}..."
    
    if [ "$action" = "off" ]; then
        sudo uhubctl -l $hub -p $port -a off
    else
        sudo uhubctl -l $hub -p $port -a on
    fi
    
    if [ $? -eq 0 ]; then
        log_info "동글 $subnet 전원 $action 완료"
        return 0
    else
        log_error "동글 $subnet 전원 $action 실패"
        return 1
    fi
}

# 모든 동글 전원 제어
control_all_dongles() {
    local action=$1
    
    log_info "모든 USB 동글의 전원을 ${action}합니다..."
    echo ""
    
    # 각 허브별로 모든 포트 제어
    local hubs=("1-3.1" "1-3.3" "1-3.4")
    
    for hub in "${hubs[@]}"; do
        log_info "Hub $hub 포트 전원 ${action} 중..."
        if [ "$action" = "off" ]; then
            sudo uhubctl -l $hub -p 1,2,3,4 -a off
        else
            sudo uhubctl -l $hub -p 1,2,3,4 -a on
        fi
        echo ""
    done
    
    if [ "$action" = "on" ]; then
        log_warning "주의: 동글이 네트워크 모드로 전환될 때까지 약 30-60초 소요됩니다"
        log_info "네트워크 상태 확인: ip addr | grep -E 'usb|enx'"
    fi
}

# 상태 확인
show_status() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}    USB 허브 및 동글 상태${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    
    log_info "USB 허브 상태:"
    sudo uhubctl | grep -A5 -B1 "1-3\.[134]"
    
    echo ""
    log_info "동글 네트워크 인터페이스:"
    ip addr | grep -E "(usb|enx)" | grep -v "state DOWN" || echo "활성화된 네트워크 인터페이스가 없습니다"
    
    echo ""
    log_info "동글별 IP 할당 상태:"
    for subnet in 11 12 13 14 15 16 18; do
        interface=$(ip addr | grep "192.168.$subnet.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
        if [ -n "$interface" ]; then
            echo "  동글$subnet: $interface (192.168.$subnet.100)"
        fi
    done
}

# 사용법 출력
usage() {
    echo "사용법: $0 <action> [subnet|all]"
    echo ""
    echo "Actions:"
    echo "  on <subnet>     개별 동글 전원 켜기 (예: on 11)"
    echo "  off <subnet>    개별 동글 전원 끄기 (예: off 11)"
    echo "  on all          모든 동글 전원 켜기"
    echo "  off all         모든 동글 전원 끄기"
    echo "  status          전체 상태 확인"
    echo ""
    echo "Examples:"
    echo "  sudo $0 off 11          # 동글 11만 끄기"
    echo "  sudo $0 on all          # 모든 동글 켜기"
    echo "  $0 status               # 상태 확인"
}

# 메인 로직
main() {
    case "$1" in
        "on"|"off")
            check_root "$@"
            check_uhubctl
            load_mapping
            
            if [ "$2" = "all" ]; then
                control_all_dongles "$1"
            elif [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 11 ] && [ "$2" -le 30 ]; then
                control_single_dongle "$1" "$2"
            else
                log_error "유효하지 않은 서브넷: $2"
                usage
                exit 1
            fi
            ;;
        "status")
            check_uhubctl
            show_status
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"