#!/bin/bash

# Network Monitor 설치 스크립트

set -e

echo "=== Network Monitor Installation ==="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root"
    exit 1
fi

# Node.js 확인
if ! command -v node &> /dev/null; then
    log_warn "Node.js is not installed. Please install Node.js first."
    echo "For Rocky Linux 9:"
    echo "  dnf module install nodejs:18/common"
    exit 1
fi

# 필요한 패키지 확인
REQUIRED_PACKAGES="curl iproute NetworkManager"
MISSING_PACKAGES=""

for pkg in $REQUIRED_PACKAGES; do
    if ! rpm -q $pkg &> /dev/null; then
        MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
    fi
done

if [ ! -z "$MISSING_PACKAGES" ]; then
    log_info "Installing required packages:$MISSING_PACKAGES"
    dnf install -y $MISSING_PACKAGES
fi

# 로그 디렉토리 생성
log_info "Creating log directory..."
mkdir -p /home/proxy/network-monitor/logs

# systemd 서비스 파일 복사
log_info "Installing systemd services..."
cp /home/proxy/network-monitor/systemd/network-monitor.service /etc/systemd/system/
cp /home/proxy/network-monitor/systemd/network-monitor-health.service /etc/systemd/system/

# systemd 리로드
systemctl daemon-reload

# 서비스 활성화
log_info "Enabling services..."
systemctl enable network-monitor.service
systemctl enable network-monitor-health.service

# NetworkManager dispatcher 설치
log_info "Installing NetworkManager dispatcher..."
if [ -f /home/proxy/network-monitor/scripts/nm-dispatcher/99-dongle-routing ]; then
    mkdir -p /etc/NetworkManager/dispatcher.d
    cp /home/proxy/network-monitor/scripts/nm-dispatcher/99-dongle-routing /etc/NetworkManager/dispatcher.d/
    chmod +x /etc/NetworkManager/dispatcher.d/99-dongle-routing
    log_info "  ✓ NetworkManager dispatcher installed"
else
    log_info "  ✗ NetworkManager dispatcher script not found"
fi

# 방화벽 규칙 추가 (헬스체크 포트)
if systemctl is-active --quiet firewalld; then
    log_info "Adding firewall rule for health check port..."
    firewall-cmd --permanent --add-port=8080/tcp
    firewall-cmd --reload
fi

# Fix any missing routes for already connected dongles
if [ -f /home/proxy/network-monitor/scripts/fix_missing_routes.sh ]; then
    log_info "Checking for missing routes..."
    /home/proxy/network-monitor/scripts/fix_missing_routes.sh
fi

echo ""
log_info "Installation completed!"
echo ""
echo "To start the services:"
echo "  systemctl start network-monitor"
echo "  systemctl start network-monitor-health"
echo ""
echo "To check status:"
echo "  systemctl status network-monitor"
echo "  systemctl status network-monitor-health"
echo ""
echo "To view logs:"
echo "  journalctl -u network-monitor -f"
echo "  journalctl -u network-monitor-health -f"
echo ""
echo "Health check URL: http://$(hostname -I | awk '{print $1}'):8080/"