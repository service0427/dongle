#!/bin/bash
#
# uhubctl 설치 스크립트
# USB 허브 포트별 전원 제어 도구
#

set -e

echo "========================================="
echo "    uhubctl 설치 스크립트"
echo "========================================="
echo ""

# 색상 코드
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

# OS 확인
if [ -f /etc/redhat-release ]; then
    OS="RHEL"
    PKG_MANAGER="dnf"
elif [ -f /etc/debian_version ]; then
    OS="DEBIAN"
    PKG_MANAGER="apt"
else
    log_error "지원하지 않는 OS입니다"
    exit 1
fi

log_info "OS 감지: $OS (패키지 관리자: $PKG_MANAGER)"

# 1. 필수 패키지 설치
log_info "필수 패키지 설치 중..."

if [ "$OS" = "RHEL" ]; then
    $PKG_MANAGER install -y git gcc make libusb1-devel || {
        # 패키지 이름 차이 처리
        $PKG_MANAGER install -y git gcc make libusbx-devel
    }
elif [ "$OS" = "DEBIAN" ]; then
    $PKG_MANAGER update
    $PKG_MANAGER install -y git gcc make libusb-1.0-0-dev
fi

if [ $? -eq 0 ]; then
    log_info "필수 패키지 설치 완료"
else
    log_error "패키지 설치 실패"
    exit 1
fi

# 2. 기존 설치 확인
if command -v uhubctl &> /dev/null; then
    INSTALLED_VERSION=$(uhubctl -v 2>/dev/null || echo "unknown")
    log_warning "uhubctl이 이미 설치되어 있습니다 (버전: $INSTALLED_VERSION)"
    read -p "재설치하시겠습니까? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "설치 취소됨"
        exit 0
    fi
fi

# 3. 소스 코드 다운로드
INSTALL_DIR="/tmp/uhubctl_install_$$"
log_info "소스 코드 다운로드 중... ($INSTALL_DIR)"

# 임시 디렉토리 생성
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

git clone https://github.com/mvp/uhubctl.git || {
    log_error "소스 코드 다운로드 실패"
    exit 1
}

cd uhubctl

# 4. 컴파일
log_info "컴파일 중..."
make || {
    log_error "컴파일 실패"
    exit 1
}

# 5. 설치
log_info "설치 중..."
make install || {
    log_error "설치 실패"
    exit 1
}

# 6. 설치 확인
if command -v uhubctl &> /dev/null; then
    VERSION=$(uhubctl -v)
    log_info "uhubctl 설치 완료 (버전: $VERSION)"
else
    log_error "설치는 완료되었으나 uhubctl을 찾을 수 없습니다"
    exit 1
fi

# 7. 정리
log_info "임시 파일 정리 중..."
cd /
rm -rf "$INSTALL_DIR"

# 8. USB 허브 스캔
echo ""
echo "========================================="
echo "    USB 허브 스캔 결과"
echo "========================================="
echo ""

uhubctl || {
    log_warning "USB 허브 스캔 실패. sudo로 다시 시도하세요: sudo uhubctl"
}

# 9. 사용 예시 출력
echo ""
echo "========================================="
echo "    사용 예시"
echo "========================================="
echo ""
echo "# 모든 허브 상태 확인:"
echo "  sudo uhubctl"
echo ""
echo "# 특정 포트 전원 끄기:"
echo "  sudo uhubctl -l 1-3.4 -p 1 -a off"
echo ""
echo "# 특정 포트 전원 켜기:"
echo "  sudo uhubctl -l 1-3.4 -p 1 -a on"
echo ""
echo "# 포트 재시작 (전원 껐다 켜기):"
echo "  sudo uhubctl -l 1-3.4 -p 1 -a cycle"
echo ""
echo "# 여러 포트 동시 제어:"
echo "  sudo uhubctl -l 1-3.4 -p 1,2,3,4 -a cycle"
echo ""
echo "========================================="

log_info "설치가 완료되었습니다!"
echo ""
echo "주의: USB 동글이 연결된 포트의 전원을 끄면 연결이 끊어집니다."
echo "      필요한 경우에만 신중하게 사용하세요."