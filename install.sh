#!/bin/bash
#
# v1 시스템 설치 스크립트
# 최소한의 안정적인 기능만 설치
#

echo "========================================="
echo "    동글 프록시 시스템 v1 설치"
echo "========================================="

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

# SOCKS5 프록시 서비스
cat > /etc/systemd/system/dongle-socks5.service <<EOF
[Unit]
Description=SOCKS5 Proxy Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/proxy/scripts
ExecStart=/usr/bin/python3 /home/proxy/scripts/socks5_proxy.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 3. 스크립트 실행 권한 설정
echo "3. 실행 권한 설정..."
chmod +x /home/proxy/scripts/*.sh 2>/dev/null
chmod +x /home/proxy/scripts/*.py 2>/dev/null
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

echo ""
echo "========================================="
echo "설치 완료!"
echo ""
echo "사용법:"
echo "  1. 동글 연결 후 초기 설정:"
echo "     sudo /home/proxy/scripts/manual_setup.sh"
echo ""
echo "  2. 서비스 시작:"
echo "     sudo systemctl start dongle-toggle-api"
echo "     sudo systemctl start dongle-socks5"
echo ""
echo "  3. 서비스 자동 시작 설정:"
echo "     sudo systemctl enable dongle-toggle-api"
echo "     sudo systemctl enable dongle-socks5"
echo ""
echo "  4. 토글 API:"
echo "     curl http://localhost:8080/toggle/11"
echo ""
echo "  5. SOCKS5 프록시:"
echo "     포트 10011-10030 (동글 번호에 따라)"
echo ""
echo "  6. 상태 푸시 로그 확인:"
echo "     tail -f /home/proxy/logs/push_status.log"
echo "========================================="