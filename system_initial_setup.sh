#!/bin/bash

# Rocky Linux 9.6 Network Monitor 시스템 전체 초기 설정 스크립트
# 이 스크립트는 새로운 시스템에서 한 번만 실행하면 됩니다

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

echo "=================================================="
echo "Rocky Linux 9.6 Network Monitor System Setup"
echo "=================================================="
echo

# 루트 권한 확인
if [ "$EUID" -ne 0 ]; then 
    log_error "This script must be run as root"
    exit 1
fi

# 1. 시스템 기본 설정
log_info "1. Setting system timezone..."
timedatectl set-timezone Asia/Seoul
log_info "   ✓ Timezone set to Asia/Seoul"

# 2. 저장소 설정
log_info "2. Setting up repositories..."
cd /home
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm 2>/dev/null || log_warn "EPEL already installed"
rpm -Uvh http://rpms.remirepo.net/enterprise/remi-release-9.rpm 2>/dev/null || log_warn "Remi already installed"
yum -y install epel-release >/dev/null 2>&1
log_info "   ✓ Repositories configured"

# 3. 시스템 업데이트
log_info "3. Updating system packages..."
yum -y update >/dev/null 2>&1
log_info "   ✓ System updated"

# 4. 필수 패키지 설치
log_info "4. Installing essential packages..."
yum -y install net-tools usbutils tar vim git usb_modeswitch usb_modeswitch-data python3 python3-pip >/dev/null 2>&1
pip3 install huawei-lte-api >/dev/null 2>&1
log_info "   ✓ Essential packages installed"

# 5. Node.js 설치
log_info "5. Installing Node.js..."
curl -fsSL https://rpm.nodesource.com/setup_23.x -o /tmp/nodesource_setup.sh
bash /tmp/nodesource_setup.sh >/dev/null 2>&1
yum install -y nodejs >/dev/null 2>&1
rm -f /tmp/nodesource_setup.sh
NODE_VERSION=$(node -v)
log_info "   ✓ Node.js installed: $NODE_VERSION"

# 6. PM2 설치
log_info "6. Installing PM2..."
npm install -g pm2@latest >/dev/null 2>&1
log_info "   ✓ PM2 installed"

# 7. GRUB 부팅 메뉴 설정
log_info "7. Configuring GRUB boot menu..."
cp /etc/default/grub /etc/default/grub.backup
sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
if ! grep -q "GRUB_TIMEOUT_STYLE" /etc/default/grub; then
    echo "GRUB_TIMEOUT_STYLE=hidden" >> /etc/default/grub
else
    sed -i 's/GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
fi
grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
log_info "   ✓ GRUB configured (boot menu hidden)"

# 8. 네트워크 설정 - eno1 메트릭 설정
log_info "8. Configuring network interface metrics..."
ENO1_CONN=$(nmcli -t -f NAME,DEVICE connection show | grep eno1 | cut -d: -f1 | head -1)
if [ ! -z "$ENO1_CONN" ]; then
    nmcli connection modify "$ENO1_CONN" ipv4.route-metric 0
    log_info "   ✓ eno1 metric set to 0"
else
    log_error "   ✗ eno1 connection not found!"
fi

# 9. DNS 설정 고정
log_info "9. Fixing DNS configuration..."
chattr -i /etc/resolv.conf 2>/dev/null
cat > /etc/resolv.conf <<EOF
# Fixed DNS configuration
nameserver 168.126.63.1
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
chattr +i /etc/resolv.conf
log_info "   ✓ DNS configuration fixed and locked"

# 10. 라우팅 테이블 설정
log_info "10. Setting up routing tables..."
cp /etc/iproute2/rt_tables /etc/iproute2/rt_tables.backup.$(date +%Y%m%d) 2>/dev/null || true

# 기존 동글 테이블 정리
sed -i '/^[0-9]\+ dongle[0-9]\+/d' /etc/iproute2/rt_tables

# 11~30번 동글 테이블 추가
for i in {11..30}; do
    echo "$((100 + i)) dongle$i" >> /etc/iproute2/rt_tables
done

log_info "   ✓ Routing tables configured (dongle11 ~ dongle30)"

# 11. IP 포워딩 영구 활성화
log_info "11. Enabling IP forwarding..."
# 99-sysctl.conf에 추가 (중복 방지)
if ! grep -q "^net.ipv4.ip_forward" /etc/sysctl.d/99-sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
log_info "   ✓ IP forwarding enabled"

echo
echo "=================================================="
echo "System Initial Setup Complete!"
echo "=================================================="
echo
echo "Next steps:"
echo "1. Install network-monitor: cd /home/proxy/network-monitor && sudo ./install.sh"
echo "2. Reboot the system: sudo reboot"
echo
echo "After reboot, the system will be ready with:"
echo "- Timezone: Asia/Seoul"
echo "- Node.js: $NODE_VERSION"
echo "- PM2 process manager"
echo "- Fixed DNS configuration"
echo "- Network routing prepared for dongles"
echo "- Boot menu hidden (GRUB timeout=0)"
echo