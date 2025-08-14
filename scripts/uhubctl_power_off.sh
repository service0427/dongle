#!/bin/bash

#============================================================
# uhubctl 모든 동글 전원 끄기 스크립트
# 
# USB 허브의 모든 포트 전원을 순차적으로 끕니다.
# 
# 사용법: ./uhubctl_power_off.sh
#============================================================

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo "사용법: sudo $0"
    exit 1
fi

# uhubctl 명령 확인
if ! command -v uhubctl &> /dev/null; then
    log_error "uhubctl이 설치되지 않았습니다"
    exit 1
fi

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}    uhubctl 모든 동글 전원 끄기${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

log_warning "모든 USB 동글의 전원을 끕니다..."
echo ""

# Hub 1-3.1의 모든 포트 (서브넷 14, 15)
log_info "Hub 1-3.1 포트 전원 끄는 중..."
sudo uhubctl -l 1-3.1 -p 1,2,3,4 -a off
echo ""

# Hub 1-3.3의 모든 포트 (서브넷 16, 18)  
log_info "Hub 1-3.3 포트 전원 끄는 중..."
sudo uhubctl -l 1-3.3 -p 1,2,3,4 -a off
echo ""

# Hub 1-3.4의 모든 포트 (서브넷 11, 12, 13)
log_info "Hub 1-3.4 포트 전원 끄는 중..."
sudo uhubctl -l 1-3.4 -p 1,2,3,4 -a off
echo ""

echo -e "${BLUE}=========================================${NC}"
log_info "모든 USB 동글 전원이 꺼졌습니다"
echo ""

log_warning "주의: 네트워크 연결이 모두 끊어졌습니다"
log_info "전원을 다시 켜려면: sudo ./uhubctl_power_on.sh"

echo -e "${BLUE}=========================================${NC}"
echo ""

# 상태 확인
log_info "현재 USB 허브 상태:"
echo ""
sudo uhubctl | grep -A5 -B1 "1-3\.[134]"