#!/bin/bash
#
# v1 시스템 설치 스크립트
# 최소한의 안정적인 기능만 설치
#

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "    동글 프록시 시스템 v1 설치"
echo "========================================="

# 0. 필요한 디렉토리 생성
echo "0. 디렉토리 구조 생성..."
mkdir -p /home/proxy/config
mkdir -p /home/proxy/logs
mkdir -p /home/proxy/scripts/socks5
mkdir -p /home/proxy/scripts/utils
echo "   디렉토리 생성 완료"

# 1. rt_tables 설정
echo "1. 라우팅 테이블 설정..."
if ! grep -q "dongle11" /etc/iproute2/rt_tables; then
    echo "" >> /etc/iproute2/rt_tables
    echo "# Dongle routing tables" >> /etc/iproute2/rt_tables
    for i in {11..30}; do
        echo "$((100+$i)) dongle$i" >> /etc/iproute2/rt_tables
    done
    echo "   라우팅 테이블 추가 완료"
else
    echo "   라우팅 테이블 이미 존재"
fi

# 2. systemd 서비스 파일 생성
echo "2. 서비스 파일 생성..."

# Toggle API 서비스
cat > /etc/systemd/system/dongle-toggle-api.service <<EOF
[Unit]
Description=Dongle Toggle API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/proxy/scripts
ExecStart=/usr/bin/node /home/proxy/scripts/toggle_api.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# SOCKS5 서비스는 init_dongle_config.sh에서 개별 생성됨

# 3. 스크립트 실행 권한 설정
echo "3. 실행 권한 설정..."
chmod +x /home/proxy/scripts/*.sh 2>/dev/null
chmod +x /home/proxy/scripts/*.py 2>/dev/null
chmod +x /home/proxy/scripts/socks5/*.sh 2>/dev/null
chmod +x /home/proxy/scripts/socks5/*.py 2>/dev/null
chmod +x /home/proxy/scripts/utils/*.sh 2>/dev/null
chmod +x /home/proxy/scripts/utils/*.py 2>/dev/null
chmod +x /home/proxy/*.sh 2>/dev/null

# 4. 서비스 재로드
echo "4. 서비스 등록..."
systemctl daemon-reload

# 5. 크론 설정
echo "5. 상태 푸시 크론 설정..."
# 임시 파일로 크론 설정
CRON_TEMP="/tmp/cron_temp_$$"
crontab -l 2>/dev/null > "$CRON_TEMP" || true
# 기존 크론 제거
grep -v "/home/proxy/scripts/push_proxy_status.sh" "$CRON_TEMP" > "${CRON_TEMP}.new" || true
# 새 크론 추가 (mkt.techb.kr로 상태 전송)
echo "* * * * * /home/proxy/scripts/push_proxy_status.sh >/dev/null 2>&1" >> "${CRON_TEMP}.new"
crontab "${CRON_TEMP}.new"
rm -f "$CRON_TEMP" "${CRON_TEMP}.new"
echo "   상태 푸시 크론 등록 완료 (1분마다 mkt.techb.kr로 전송)"

# 6. uhubctl 설치 확인
echo "6. uhubctl 설치 확인..."
if ! command -v uhubctl &> /dev/null; then
    echo -e "   ${YELLOW}uhubctl이 설치되지 않았습니다. 설치 중...${NC}"
    /home/proxy/scripts/utils/install_uhubctl.sh
else
    echo "   uhubctl 설치 확인 완료"
fi

# 7. dongle_config.json 확인 및 초기 설정 안내
echo "7. 초기 설정 확인..."
if [ ! -f "/home/proxy/config/dongle_config.json" ]; then
    echo ""
    echo -e "${RED}========================================="
    echo "    ⚠️  초기 설정 필요"
    echo "=========================================${NC}"
    echo ""
    echo "1. 모든 USB 동글을 연결하세요"
    echo "2. 동글 연결 확인: lsusb | grep -i huawei"
    echo "3. 초기 설정 실행:"
    echo -e "   ${GREEN}sudo /home/proxy/init_dongle_config.sh${NC}"
    echo ""
    echo "이 명령은 한 번만 실행하면 됩니다."
    echo "========================================="
else
    echo "   dongle_config.json 파일 발견 - 초기 설정 완료"
fi

echo ""
echo "========================================="
echo "설치 완료!"
echo ""
echo "사용법:"
echo "  1. 서비스 시작:"
echo "     sudo systemctl start dongle-toggle-api"
echo ""
echo "  2. 서비스 자동 시작 설정:"
echo "     sudo systemctl enable dongle-toggle-api"
echo ""
echo "  3. 토글 API:"
echo "     curl http://localhost/toggle/11"
echo ""
echo "  4. SOCKS5 프록시:"
echo "     포트 10011-10030 (개별 서비스)"
echo "     /home/proxy/scripts/socks5/manage_socks5.sh status"
echo ""
echo "  5. 상태 확인:"
echo "     curl http://localhost/status"
echo ""
echo "  6. 허브 전체 재시작:"
echo "     sudo /home/proxy/scripts/restart_all_hubs.sh"
echo "========================================="