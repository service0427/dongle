#!/bin/bash

#############################################
# SOCKS5 방화벽 초기 설정 스크립트
# - 대화형으로 설정 생성
# - Whitelist 다운로드
# - 방화벽 규칙 적용
# - systemd 서비스 등록
# - cron 작업 등록
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/home/proxy/config/firewall_config.json"
WHITELIST_FILE="/home/proxy/config/whitelist_ips.txt"
LOG_FILE="/home/proxy/logs/firewall/firewall.log"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Root 권한이 필요합니다. sudo로 실행하세요.${NC}"
    exit 1
fi

echo "=========================================="
echo "  SOCKS5 방화벽 초기 설정"
echo "=========================================="
echo ""

# 옵션 처리
if [ "$1" = "--disable" ]; then
    if [ -f "$CONFIG_FILE" ]; then
        jq '.enabled = false' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo -e "${YELLOW}방화벽을 비활성화했습니다.${NC}"
        "$SCRIPT_DIR/apply_firewall.sh"
        exit 0
    else
        echo -e "${RED}ERROR: 설정 파일이 없습니다.${NC}"
        exit 1
    fi
fi

if [ "$1" = "--enable" ]; then
    if [ -f "$CONFIG_FILE" ]; then
        jq '.enabled = true' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo -e "${GREEN}방화벽을 활성화했습니다.${NC}"
        "$SCRIPT_DIR/apply_firewall.sh"
        exit 0
    else
        echo -e "${RED}ERROR: 설정 파일이 없습니다.${NC}"
        exit 1
    fi
fi

# 기존 설정 확인
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}기존 설정 파일이 발견되었습니다.${NC}"
    echo "기존 설정:"
    cat "$CONFIG_FILE" | jq .
    echo ""
    read -p "기존 설정을 덮어쓰시겠습니까? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "설정을 취소했습니다."
        exit 0
    fi
fi

# 1. Whitelist URL 설정 (자동)
DEFAULT_URL="https://raw.githubusercontent.com/service0427/dongle/refs/heads/main/config/socks5-whitelist.txt"

if [ -f "$CONFIG_FILE" ]; then
    EXISTING_URL=$(jq -r '.whitelist_url' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$EXISTING_URL" ] && [ "$EXISTING_URL" != "null" ]; then
        WHITELIST_URL="$EXISTING_URL"
        echo "기존 Whitelist URL 사용: $WHITELIST_URL"
    else
        WHITELIST_URL="$DEFAULT_URL"
        echo "Whitelist URL: $WHITELIST_URL"
    fi
else
    WHITELIST_URL="$DEFAULT_URL"
    echo "Whitelist URL: $WHITELIST_URL"
fi

# 2. 기본 옵션 설정
ALLOW_LOCALHOST="true"
LOG_BLOCKED="true"
echo "localhost 접근: 허용"
echo "차단 로그: 활성화"
echo "자동 업데이트: 비활성화 (수동 관리)"

# 4. 설정 파일 생성
echo ""
echo -e "${GREEN}설정 파일 생성 중...${NC}"

cat > "$CONFIG_FILE" <<EOF
{
  "enabled": true,
  "whitelist_url": "$WHITELIST_URL",
  "allow_localhost": $ALLOW_LOCALHOST,
  "log_blocked": $LOG_BLOCKED,
  "auto_detect_ports": true,
  "manual_ports": [],
  "save_rules": false,
  "created_at": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF

echo -e "${GREEN}✓ 설정 파일 생성 완료${NC}"

# 5. Whitelist 다운로드
echo ""
echo -e "${GREEN}Whitelist 다운로드 중...${NC}"
"$SCRIPT_DIR/update_whitelist.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: Whitelist 다운로드 실패${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Whitelist 다운로드 완료${NC}"

# 6. 방화벽 규칙 적용
echo ""
echo -e "${GREEN}방화벽 규칙 적용 중...${NC}"
"$SCRIPT_DIR/apply_firewall.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}ERROR: 방화벽 규칙 적용 실패${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 방화벽 규칙 적용 완료${NC}"

# 7. systemd 서비스 생성
echo ""
echo -e "${GREEN}systemd 서비스 등록 중...${NC}"

cat > /etc/systemd/system/socks5-firewall.service <<EOF
[Unit]
Description=SOCKS5 Firewall Whitelist
After=network.target dongle-toggle-api.service
Wants=dongle-toggle-api.service

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/apply_firewall.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable socks5-firewall.service
systemctl start socks5-firewall.service

echo -e "${GREEN}✓ systemd 서비스 등록 완료${NC}"

# 8. 완료 메시지
echo ""
echo "=========================================="
echo -e "  ${GREEN}방화벽 설정 완료!${NC}"
echo "=========================================="
echo ""
echo "설정 요약:"
echo "  - Whitelist URL: $WHITELIST_URL"
echo "  - localhost 허용: $ALLOW_LOCALHOST"
echo "  - 차단 로그: $LOG_BLOCKED"
echo "  - 자동 업데이트: 비활성화 (수동 관리)"
echo ""
echo "관리 명령어:"
echo "  - 상태 확인: sudo $SCRIPT_DIR/check_firewall.sh"
echo "  - 수동 업데이트: sudo $SCRIPT_DIR/update_whitelist.sh"
echo "  - 비활성화: sudo $SCRIPT_DIR/init_firewall.sh --disable"
echo "  - 활성화: sudo $SCRIPT_DIR/init_firewall.sh --enable"
echo ""
echo "로그 파일:"
echo "  - $LOG_FILE"
echo "  - /var/log/messages (차단 로그)"
echo ""
echo "참고:"
echo "  - Whitelist 변경: GitHub에서 config/socks5-whitelist.txt 수정 후"
echo "  - 적용: sudo $SCRIPT_DIR/update_whitelist.sh 실행"
echo ""

exit 0
