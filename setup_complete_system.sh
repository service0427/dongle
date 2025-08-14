#!/bin/bash

#============================================================
# Rocky Linux 9 Dongle Proxy System Complete Setup Script
# 
# 이 스크립트는 Rocky Linux 9 최소 설치 환경에서
# 완전한 동글 프록시 시스템을 구축합니다.
#
# 실행 방법:
#   cd /home
#   git clone https://github.com/service0427/dongle.git proxy
#   cd proxy
#   sudo bash setup_complete_system.sh
#
# 작성일: 2025-08-14
#============================================================

set -e  # 에러 발생 시 즉시 종료

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 파일
LOG_FILE="/var/log/proxy_setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# 프로젝트 경로 (git clone된 디렉토리)
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}    $1${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
}

# root 권한 확인
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "이 스크립트는 root 권한이 필요합니다"
        echo "사용법: sudo bash $0"
        exit 1
    fi
}

# 시스템 정보 출력
print_system_info() {
    log_section "시스템 정보"
    log_info "운영체제: $(cat /etc/redhat-release)"
    log_info "커널: $(uname -r)"
    log_info "아키텍처: $(uname -m)"
    log_info "호스트명: $(hostname)"
    log_info "프로젝트 경로: $PROJECT_DIR"
}

# 1. 시스템 업데이트 및 기본 패키지 설치
install_base_packages() {
    log_section "시스템 업데이트 및 기본 패키지 설치"
    
    log_info "시스템 업데이트 중..."
    dnf update -y
    dnf upgrade -y
    
    log_info "EPEL 저장소 추가..."
    dnf install -y epel-release
    
    log_info "기본 패키지 설치 중..."
    dnf install -y \
        git gcc make \
        usb_modeswitch usbutils \
        NetworkManager net-tools curl wget \
        iptables-services \
        python3-pip python3-devel \
        tar unzip nano vim htop tmux \
        bind-utils \
        chrony \
        firewalld \
        iproute \
        bc
    
    # libusb 패키지 (이름이 다를 수 있음)
    dnf install -y libusb1-devel || dnf install -y libusbx-devel
    
    log_info "기본 패키지 설치 완료"
}

# 2. DNS 설정 고정
setup_dns() {
    log_section "DNS 설정"
    
    log_info "기존 DNS 설정 백업..."
    cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # immutable 플래그 제거
    if lsattr /etc/resolv.conf 2>/dev/null | grep -q "i"; then
        log_info "기존 immutable 플래그 제거..."
        chattr -i /etc/resolv.conf
    fi
    
    log_info "DNS 서버 설정..."
    cat > /etc/resolv.conf <<EOF
# Fixed DNS configuration
# KT DNS (Primary)
nameserver 168.126.63.1
# Google DNS (Secondary)
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    
    log_info "DNS 설정 파일 보호 (immutable 플래그 설정)..."
    chattr +i /etc/resolv.conf
    
    # DNS 테스트
    log_info "DNS 확인 중..."
    if nslookup google.com >/dev/null 2>&1; then
        log_info "DNS 설정 성공"
    else
        log_warning "DNS 테스트 실패. 네트워크 연결을 확인하세요."
    fi
}

# 3. Node.js 23 설치
install_nodejs() {
    log_section "Node.js 23 설치"
    
    if command -v node &> /dev/null; then
        CURRENT_VERSION=$(node -v)
        log_info "Node.js가 이미 설치되어 있습니다 (버전: $CURRENT_VERSION)"
        
        # 버전 23인지 확인
        if [[ "$CURRENT_VERSION" == v23.* ]]; then
            log_info "Node.js 23이 이미 설치되어 있습니다. 설치 건너뛰기"
            return
        else
            log_info "기존 Node.js 버전을 23으로 업데이트합니다"
        fi
    fi
    
    log_info "NodeSource 저장소 추가..."
    curl -fsSL https://rpm.nodesource.com/setup_23.x | bash -
    
    log_info "Node.js 설치..."
    dnf install -y nodejs
    
    log_info "Node.js 버전 확인..."
    node -v
    npm -v
    
    log_info "PM2 글로벌 설치..."
    npm install -g pm2
    
    log_info "Node.js 23 설치 완료"
}

# 4. Python 패키지 설치
install_python_packages() {
    log_section "Python 패키지 설치"
    
    log_info "pip 업그레이드..."
    python3 -m pip install --upgrade pip
    
    log_info "필수 Python 패키지 설치..."
    /usr/local/bin/pip3 install \
        aiohttp>=3.8.0 \
        requests>=2.28.0 \
        psutil>=5.9.0 \
        huawei-lte-api>=1.6.0 || \
    python3 -m pip install \
        aiohttp>=3.8.0 \
        requests>=2.28.0 \
        psutil>=5.9.0 \
        huawei-lte-api>=1.6.0
    
    log_info "Python 패키지 설치 완료"
}

# 5. uhubctl 설치
install_uhubctl() {
    log_section "uhubctl 설치"
    
    if command -v uhubctl &> /dev/null; then
        log_warning "uhubctl이 이미 설치되어 있습니다"
        uhubctl -v
        return
    fi
    
    log_info "uhubctl 소스 다운로드..."
    TEMP_DIR="/tmp/uhubctl_build_$$"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    git clone https://github.com/mvp/uhubctl.git
    cd uhubctl
    
    log_info "uhubctl 컴파일..."
    make
    
    log_info "uhubctl 설치..."
    make install
    
    # udev 규칙 복사
    if [ -f udev/rules.d/52-usb.rules ]; then
        log_info "udev 규칙 설치..."
        cp udev/rules.d/52-usb.rules /etc/udev/rules.d/
        udevadm control --reload-rules
    fi
    
    # 임시 디렉토리 정리
    cd "$PROJECT_DIR"
    rm -rf "$TEMP_DIR"
    
    log_info "uhubctl 설치 완료"
    uhubctl -v
}

# 6. 네트워크 시스템 설정
setup_network() {
    log_section "네트워크 시스템 설정"
    
    # IP 포워딩 설정
    log_info "IP 포워딩 설정..."
    cat > /etc/sysctl.d/99-proxy.conf <<EOF
# Proxy system network settings
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.accept_source_route = 1
net.ipv4.conf.default.accept_source_route = 1
EOF
    sysctl -p /etc/sysctl.d/99-proxy.conf
    
    # 라우팅 테이블 추가
    log_info "라우팅 테이블 설정..."
    
    # rt_tables 파일이 없으면 생성
    if [ ! -f /etc/iproute2/rt_tables ]; then
        log_info "rt_tables 파일 생성..."
        mkdir -p /etc/iproute2
        cat > /etc/iproute2/rt_tables <<EOF
#
# reserved values
#
255	local
254	main
253	default
0	unspec
#
# local
#
#1	inr.ruhep
EOF
    fi
    
    if ! grep -q "dongle11" /etc/iproute2/rt_tables; then
        echo "" >> /etc/iproute2/rt_tables
        echo "# Dongle routing tables" >> /etc/iproute2/rt_tables
        for i in {11..30}; do
            echo "$((100+$i)) dongle$i" >> /etc/iproute2/rt_tables
        done
        log_info "라우팅 테이블 추가 완료"
    else
        log_info "라우팅 테이블이 이미 존재합니다"
    fi
    
    # NetworkManager 메인 인터페이스 설정
    log_info "메인 네트워크 인터페이스 설정..."
    MAIN_IFACE=$(ip route | grep default | head -1 | awk '{print $5}')
    if [ ! -z "$MAIN_IFACE" ]; then
        log_info "메인 인터페이스: $MAIN_IFACE"
        
        # 메트릭 설정
        if nmcli con show | grep -q "$MAIN_IFACE"; then
            CONNECTION_NAME=$(nmcli -t -f NAME,DEVICE con show | grep ":$MAIN_IFACE" | cut -d: -f1)
            if [ ! -z "$CONNECTION_NAME" ]; then
                log_info "NetworkManager 연결 '$CONNECTION_NAME'의 메트릭을 1로 설정..."
                nmcli con mod "$CONNECTION_NAME" ipv4.route-metric 1
                nmcli con up "$CONNECTION_NAME"
            fi
        fi
    else
        log_warning "메인 네트워크 인터페이스를 찾을 수 없습니다"
    fi
    
    # firewalld 설정
    log_info "방화벽 설정..."
    systemctl start firewalld
    systemctl enable firewalld
    
    # 포트 개방
    firewall-cmd --permanent --add-port=8080/tcp  # API
    firewall-cmd --permanent --add-port=10011-10030/tcp  # SOCKS5
    firewall-cmd --permanent --add-masquerade  # NAT
    firewall-cmd --reload
    
    log_info "네트워크 설정 완료"
}

# 7. 프로젝트 디렉토리 설정
setup_project_directories() {
    log_section "프로젝트 디렉토리 설정"
    
    cd "$PROJECT_DIR"
    
    # 필요한 디렉토리 생성
    log_info "디렉토리 생성..."
    mkdir -p logs
    mkdir -p config
    mkdir -p scripts
    mkdir -p backup
    
    # 실행 권한 설정
    log_info "스크립트 실행 권한 설정..."
    find . -name "*.sh" -type f -exec chmod +x {} \;
    find scripts -name "*.py" -type f -exec chmod +x {} \;
    find scripts -name "*.js" -type f -exec chmod +x {} \;
    
    log_info "프로젝트 디렉토리 설정 완료"
}

# 8. systemd 서비스 생성
create_systemd_services() {
    log_section "systemd 서비스 생성"
    
    # Toggle API 서비스
    log_info "Toggle API 서비스 생성..."
    cat > /etc/systemd/system/dongle-toggle-api.service <<EOF
[Unit]
Description=Dongle Toggle API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR/scripts
ExecStart=/usr/bin/node $PROJECT_DIR/scripts/toggle_api.js
Restart=always
RestartSec=10
StandardOutput=append:$PROJECT_DIR/logs/toggle_api.log
StandardError=append:$PROJECT_DIR/logs/toggle_api_error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # SOCKS5 프록시 서비스
    log_info "SOCKS5 프록시 서비스 생성..."
    cat > /etc/systemd/system/dongle-socks5.service <<EOF
[Unit]
Description=SOCKS5 Proxy Server
After=network.target dongle-toggle-api.service

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR/scripts
ExecStart=/usr/bin/python3 $PROJECT_DIR/scripts/socks5_proxy.py
Restart=always
RestartSec=10
StandardOutput=append:$PROJECT_DIR/logs/socks5_proxy.log
StandardError=append:$PROJECT_DIR/logs/socks5_proxy_error.log

[Install]
WantedBy=multi-user.target
EOF
    
    
    # systemd 리로드
    log_info "systemd 데몬 리로드..."
    systemctl daemon-reload
    
    # 서비스 활성화
    log_info "서비스 활성화..."
    systemctl enable dongle-toggle-api.service
    systemctl enable dongle-socks5.service
    
    log_info "systemd 서비스 생성 완료"
}

# 9. USB 동글 초기화 (선택적)
initialize_dongles() {
    log_section "USB 동글 초기화"
    
    log_info "연결된 USB 동글 확인..."
    lsusb | grep -i huawei || {
        log_warning "Huawei 동글이 감지되지 않았습니다. 나중에 연결해주세요."
        return
    }
    
    # Mass Storage Mode에서 Network Mode로 전환
    log_info "동글을 네트워크 모드로 전환 중..."
    for device in /sys/bus/usb/devices/*; do
        if [ -f "$device/idVendor" ] && [ -f "$device/idProduct" ]; then
            vendor=$(cat "$device/idVendor")
            product=$(cat "$device/idProduct")
            
            # Huawei 동글 확인 (12d1:1f01 = Mass Storage Mode)
            if [ "$vendor" = "12d1" ] && [ "$product" = "1f01" ]; then
                bus_num=$(basename "$device")
                log_info "Mass Storage Mode 동글 발견: $bus_num"
                usb_modeswitch -v 12d1 -p 1f01 -M "55534243123456780000000000000011062000000100000000000000000000"
                sleep 2
            fi
        fi
    done
    
    log_info "USB 동글 초기화 완료"
}

# 10. SELinux 설정
setup_selinux() {
    log_section "SELinux 설정"
    
    SELINUX_STATUS=$(getenforce)
    log_info "현재 SELinux 상태: $SELINUX_STATUS"
    
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        log_warning "SELinux가 Enforcing 모드입니다. 프록시 시스템 작동을 위해 Permissive 모드로 변경합니다."
        log_info "SELinux를 Permissive 모드로 설정..."
        setenforce 0
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
        log_info "SELinux 설정 완료 (재부팅 후 적용)"
    fi
}

# 11. 로그 관리 설정
setup_log_management() {
    log_section "로그 관리 설정"
    
    # logrotate 설정
    log_info "logrotate 설정 생성..."
    cat > /etc/logrotate.d/proxy-system <<EOF
$PROJECT_DIR/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
    
    # 로그 정리 cron
    log_info "로그 정리 cron 작업 추가..."
    cat > /etc/cron.daily/proxy-log-cleanup <<EOF
#!/bin/bash
# 7일 이상 된 로그 파일 삭제
find $PROJECT_DIR/logs -name "*.log.*" -mtime +7 -delete
EOF
    chmod +x /etc/cron.daily/proxy-log-cleanup
    
    # 프록시 상태 보고 cron 추가
    log_info "프록시 상태 보고 cron 추가..."
    
    # 기존 크론탭 백업
    crontab -l > /tmp/crontab_backup_$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # 현재 크론탭 가져오기
    CURRENT_CRON=$(crontab -l 2>/dev/null || echo "")
    
    # push_proxy_status.sh cron이 이미 있는지 확인
    if ! echo "$CURRENT_CRON" | grep -q "push_proxy_status.sh"; then
        log_info "프록시 상태 보고 cron 작업 추가 중..."
        # 새로운 cron 작업 추가
        (echo "$CURRENT_CRON"; echo "* * * * * CRON_JOB=1 $PROJECT_DIR/scripts/push_proxy_status.sh >/dev/null 2>&1") | crontab -
        log_info "프록시 상태 보고 cron 작업이 추가되었습니다"
    else
        log_info "프록시 상태 보고 cron 작업이 이미 존재합니다"
    fi
    
    log_info "로그 관리 설정 완료"
}

# 12. USB 매핑 초기화
initialize_usb_mapping() {
    log_section "USB 매핑 초기화"
    
    log_info "USB 디바이스 매핑 초기화 중..."
    
    # 매핑 파일이 없으면 기본값으로 생성
    if [ ! -f "$PROJECT_DIR/scripts/usb_mapping.json" ]; then
        log_info "USB 매핑 파일 생성..."
        cat > "$PROJECT_DIR/scripts/usb_mapping.json" <<'MAPPING_EOF'
{
  "11": {"hub": "1-3.4", "port": 4, "interface": null, "usb_path": null, "mac": null, "last_seen": null},
  "12": {"hub": "1-3.4", "port": 1, "interface": null, "usb_path": null, "mac": null, "last_seen": null},
  "13": {"hub": "1-3.4", "port": 3, "interface": null, "usb_path": null, "mac": null, "last_seen": null},
  "14": {"hub": "1-3.1", "port": 1, "interface": null, "usb_path": null, "mac": null, "last_seen": null},
  "15": {"hub": "1-3.1", "port": 3, "interface": null, "usb_path": null, "mac": null, "last_seen": null},
  "16": {"hub": "1-3.3", "port": 4, "interface": null, "usb_path": null, "mac": null, "last_seen": null},
  "18": {"hub": "1-3.3", "port": 3, "interface": null, "usb_path": null, "mac": null, "last_seen": null}
}
MAPPING_EOF
    fi
    
    # 현재 연결된 동글 정보로 매핑 업데이트
    log_info "연결된 동글 정보 수집 중..."
    for subnet in 11 12 13 14 15 16 18; do
        interface=$(ip addr show | grep "192.168.$subnet.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ' 2>/dev/null)
        
        if [ -n "$interface" ]; then
            # USB 경로 찾기
            usb_path=$(ls -la /sys/class/net/$interface/device/driver/ 2>/dev/null | grep $interface | awk '{print $9}' || echo "")
            # MAC 주소
            mac=$(cat /sys/class/net/$interface/address 2>/dev/null || echo "")
            
            if [ -n "$usb_path" ]; then
                log_info "동글 $subnet 매핑: $interface -> $usb_path"
                
                # JSON 업데이트
                python3 -c "
import json
try:
    with open('$PROJECT_DIR/scripts/usb_mapping.json', 'r') as f:
        mapping = json.load(f)
    
    if '$subnet' in mapping:
        mapping['$subnet']['interface'] = '$interface'
        mapping['$subnet']['usb_path'] = '$usb_path'
        mapping['$subnet']['mac'] = '$mac'
        mapping['$subnet']['last_seen'] = '$(date -Iseconds)'
    
    with open('$PROJECT_DIR/scripts/usb_mapping.json', 'w') as f:
        json.dump(mapping, f, indent=2)
        
    print('Updated mapping for subnet $subnet')
except Exception as e:
    print(f'Error updating mapping: {e}')
"
            fi
        fi
    done
    
    log_info "USB 매핑 초기화 완료"
}

# 13. 서비스 시작
start_services() {
    log_section "서비스 시작"
    
    log_info "네트워크 초기 설정 실행..."
    if [ -x "$PROJECT_DIR/scripts/manual_setup.sh" ]; then
        $PROJECT_DIR/scripts/manual_setup.sh
    fi
    
    log_info "서비스 시작 중..."
    systemctl start dongle-toggle-api.service
    sleep 2
    systemctl start dongle-socks5.service
    
    log_info "서비스 상태 확인..."
    systemctl status dongle-toggle-api.service --no-pager || true
    systemctl status dongle-socks5.service --no-pager || true
}

# 13. 설치 검증
verify_installation() {
    log_section "설치 검증"
    
    # 패키지 확인
    log_info "설치된 패키지 확인..."
    echo -n "Node.js: "; node -v || echo "설치 안됨"
    echo -n "Python3: "; python3 --version || echo "설치 안됨"
    echo -n "uhubctl: "; uhubctl -v 2>/dev/null || echo "설치 안됨"
    
    # DNS 확인
    log_info "DNS 설정 확인..."
    cat /etc/resolv.conf
    echo -n "immutable 플래그: "
    lsattr /etc/resolv.conf | cut -d' ' -f1
    
    # 네트워크 설정 확인
    log_info "IP 포워딩 확인..."
    sysctl net.ipv4.ip_forward
    
    # 서비스 확인
    log_info "서비스 상태 확인..."
    systemctl is-active dongle-toggle-api.service || true
    systemctl is-active dongle-socks5.service || true
    
    # API 테스트
    log_info "API 테스트..."
    sleep 3
    curl -s http://localhost:8080/status || echo "API 서버가 아직 시작되지 않았습니다"
    
    # USB 허브 확인
    log_info "USB 허브 확인..."
    uhubctl | head -20 || echo "USB 허브를 찾을 수 없습니다"
}

# 14. 설치 요약
print_summary() {
    log_section "설치 완료"
    
    echo -e "${GREEN}동글 프록시 시스템 설치가 완료되었습니다!${NC}"
    echo ""
    echo "========================================="
    echo "주요 명령어:"
    echo "========================================="
    echo ""
    echo "# 서비스 상태 확인"
    echo "systemctl status dongle-toggle-api"
    echo "systemctl status dongle-socks5"
    echo ""
    echo "# API 상태 확인"
    echo "curl http://localhost:8080/status"
    echo ""
    echo "# 프록시 정보 확인"
    echo "$PROJECT_DIR/scripts/check_proxy_ips.sh"
    echo ""
    echo "# 동글 제어"
    echo "$PROJECT_DIR/scripts/dongle_control.sh <서브넷> <동작>"
    echo "$PROJECT_DIR/scripts/dongle_power.sh [on|off]"
    echo ""
    echo "# 로그 확인"
    echo "tail -f $PROJECT_DIR/logs/toggle_api.log"
    echo "tail -f $PROJECT_DIR/logs/socks5_proxy.log"
    echo "tail -f $PROJECT_DIR/logs/push_status.log"
    echo ""
    echo "# 크론탭 확인"
    echo "crontab -l"
    echo ""
    echo "========================================="
    echo ""
    echo -e "${YELLOW}주의사항:${NC}"
    echo "1. USB 동글을 연결한 후 자동으로 네트워크 모드로 전환됩니다"
    echo "2. 각 동글은 192.168.XX.100 형태의 IP를 받습니다"
    echo "3. SOCKS5 프록시는 100XX 포트에서 실행됩니다"
    echo "4. 재부팅 후에도 자동으로 시작됩니다"
    echo ""
    log_info "설치 로그: $LOG_FILE"
}

# 메인 실행 함수
main() {
    clear
    echo ""
    echo "========================================="
    echo "   Rocky Linux 9 동글 프록시 시스템"
    echo "        완전 자동 설치 스크립트"
    echo "========================================="
    echo ""
    
    # root 권한 확인
    check_root
    
    # 시스템 정보 출력
    print_system_info
    
    # 설치 시작
    log_info "설치를 시작합니다..."
    
    # 각 단계 실행
    install_base_packages
    setup_dns
    install_nodejs
    install_python_packages
    install_uhubctl
    setup_network
    setup_project_directories
    create_systemd_services
    initialize_usb_mapping
    initialize_dongles
    setup_selinux
    setup_log_management
    start_services
    verify_installation
    
    # 설치 요약
    print_summary
    
    log_info "모든 설치가 완료되었습니다!"
}

# 스크립트 실행
main "$@"