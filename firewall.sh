#!/bin/bash

#############################################
# SOCKS5 방화벽 통합 관리 스크립트
#
# 사용법:
#   sudo ./firewall.sh        # 방화벽 설정/업데이트
#   sudo ./firewall.sh off    # 방화벽 비활성화
#   sudo ./firewall.sh status # 방화벽 상태 확인
#############################################

SCRIPT_DIR="/home/proxy/scripts/firewall"
CONFIG_FILE="/home/proxy/config/firewall_config.json"
WHITELIST_FILE="/home/proxy/config/whitelist_ips.txt"
LOG_FILE="/home/proxy/logs/firewall/firewall.log"
DEFAULT_URL="https://raw.githubusercontent.com/service0427/dongle/refs/heads/main/config/socks5-whitelist.txt"

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

# 로그 디렉토리 생성
mkdir -p /home/proxy/logs/firewall
mkdir -p /home/proxy/config

#############################################
# 방화벽 OFF
#############################################
if [ "$1" = "off" ]; then
    echo "=========================================="
    echo "  SOCKS5 방화벽 비활성화"
    echo "=========================================="
    echo ""

    if [ -f "$CONFIG_FILE" ]; then
        jq '.enabled = false' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo -e "${YELLOW}방화벽을 비활성화합니다...${NC}"
        "$SCRIPT_DIR/apply_firewall.sh"
        echo -e "${GREEN}✓ 방화벽 비활성화 완료${NC}"
        echo ""
        echo "방화벽 규칙이 제거되었습니다."
        echo "다시 활성화: sudo ./firewall.sh"
    else
        echo -e "${YELLOW}방화벽이 설정되어 있지 않습니다.${NC}"
    fi
    exit 0
fi

#############################################
# 방화벽 상태 확인
#############################################
if [ "$1" = "status" ]; then
    if [ -x "$SCRIPT_DIR/check_firewall.sh" ]; then
        "$SCRIPT_DIR/check_firewall.sh"
    else
        echo -e "${RED}ERROR: check_firewall.sh를 찾을 수 없습니다.${NC}"
        exit 1
    fi
    exit 0
fi

#############################################
# 방화벽 설정/업데이트
#############################################
echo "=========================================="
echo "  SOCKS5 방화벽 설정/업데이트"
echo "=========================================="
echo ""

# 1. 설정 파일 확인 및 생성
if [ ! -f "$CONFIG_FILE" ]; then
    echo "첫 설정입니다. 방화벽을 초기화합니다..."
    echo ""

    cat > "$CONFIG_FILE" <<EOF
{
  "enabled": true,
  "whitelist_url": "$DEFAULT_URL",
  "allow_localhost": true,
  "log_blocked": true,
  "auto_detect_ports": true,
  "manual_ports": [],
  "save_rules": false,
  "created_at": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF

    echo -e "${GREEN}✓ 설정 파일 생성${NC}"

    # systemd 서비스 생성
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

    echo -e "${GREEN}✓ systemd 서비스 등록 완료${NC}"
else
    echo "기존 설정을 업데이트합니다..."
    # enabled 상태 확인
    ENABLED=$(jq -r '.enabled' "$CONFIG_FILE" 2>/dev/null)
    if [ "$ENABLED" != "true" ]; then
        echo -e "${YELLOW}방화벽이 비활성화되어 있습니다.${NC}"
        echo "활성화하려면 아래 명령어를 실행하세요:"
        echo "  sudo ./firewall.sh"
        exit 0
    fi
fi

# 2. Whitelist 다운로드
echo ""
echo -e "${GREEN}Whitelist 업데이트 확인 중...${NC}"
if [ -x "$SCRIPT_DIR/update_whitelist.sh" ]; then
    "$SCRIPT_DIR/update_whitelist.sh"
    UPDATE_RESULT=$?

    if [ $UPDATE_RESULT -eq 1 ]; then
        echo -e "${RED}ERROR: Whitelist 업데이트 실패${NC}"
        exit 1
    elif [ $UPDATE_RESULT -eq 2 ]; then
        echo -e "${YELLOW}✓ Whitelist 변경사항 없음 (방화벽 재적용 스킵)${NC}"
        echo ""
        echo "=========================================="
        echo -e "  ${GREEN}이미 최신 상태입니다!${NC}"
        echo "=========================================="
        exit 0
    fi
else
    echo -e "${RED}ERROR: update_whitelist.sh를 찾을 수 없습니다.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Whitelist 업데이트 완료${NC}"

# 3. 방화벽 규칙 적용 (변경사항 있을 때만)
echo ""
echo -e "${GREEN}방화벽 규칙 적용 중...${NC}"
if [ -x "$SCRIPT_DIR/apply_firewall.sh" ]; then
    "$SCRIPT_DIR/apply_firewall.sh"
    if [ $? -ne 0 ]; then
        echo -e "${RED}ERROR: 방화벽 규칙 적용 실패${NC}"
        exit 1
    fi
else
    echo -e "${RED}ERROR: apply_firewall.sh를 찾을 수 없습니다.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 방화벽 규칙 적용 완료${NC}"

# 4. systemd 서비스 상태 확인
if ! systemctl is-active --quiet socks5-firewall.service; then
    # 서비스가 실행 중이 아니면 활성화만 (start 하지 않음, 이미 규칙 적용됨)
    systemctl enable socks5-firewall.service 2>/dev/null || true
fi

# 5. 완료 메시지
echo ""
echo "=========================================="
echo -e "  ${GREEN}방화벽 설정 완료!${NC}"
echo "=========================================="
echo ""

# Whitelist 정보 표시
if [ -f "$WHITELIST_FILE" ]; then
    IP_COUNT=$(grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' "$WHITELIST_FILE" | wc -l)
    echo -e "허용된 IP: ${GREEN}${IP_COUNT}개${NC}"
fi

# 활성 포트 표시
DONGLE_CONFIG="/home/proxy/config/dongle_config.json"
if [ -f "$DONGLE_CONFIG" ]; then
    ACTIVE_PORTS=$(jq -r '.interface_mapping[].socks5_port' "$DONGLE_CONFIG" 2>/dev/null | sort -n | tr '\n' ' ')
    PORT_COUNT=$(echo $ACTIVE_PORTS | wc -w)
    echo -e "보호된 포트: ${GREEN}${PORT_COUNT}개${NC} ($ACTIVE_PORTS)"
fi

echo ""
echo "관리 명령어:"
echo "  sudo ./firewall.sh        # Whitelist 업데이트 및 방화벽 재적용"
echo "  sudo ./firewall.sh status # 방화벽 상태 확인"
echo "  sudo ./firewall.sh off    # 방화벽 비활성화"
echo ""

exit 0
