#!/bin/bash

# 동글 설정 초기화 스크립트 v1.2
# lsusb로 물리적 동글 확인 → 네트워크 인터페이스 비교 → 자동 복구
# 각 서버별로 다른 USB 허브 구성을 자동으로 감지하여 저장

CONFIG_DIR="/home/proxy/config"
CONFIG_FILE="$CONFIG_DIR/dongle_config.json"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# config 디렉토리 생성
mkdir -p "$CONFIG_DIR"

echo -e "${GREEN}=== 동글 설정 초기화 시작 ===${NC}"

# 1. lsusb로 물리적 동글 개수 확인 (최우선)
echo -e "\n${YELLOW}물리적 동글 감지 중...${NC}"
if command -v lsusb >/dev/null 2>&1; then
    EXPECTED_COUNT=$(lsusb 2>/dev/null | grep -ci "huawei" || echo "0")
    EXPECTED_COUNT=$(echo "$EXPECTED_COUNT" | grep -oE '[0-9]+' | head -1)
    if [ -z "$EXPECTED_COUNT" ]; then
        EXPECTED_COUNT=0
    fi
else
    echo -e "${RED}lsusb 명령을 찾을 수 없습니다${NC}"
    exit 1
fi
echo -e "lsusb로 감지된 물리적 동글: ${GREEN}${EXPECTED_COUNT}개${NC}"

# 2. 현재 네트워크 인터페이스 확인
echo -e "\n${YELLOW}네트워크 인터페이스 확인 중...${NC}"
INTERFACE_COUNT=$(ip addr show | grep -c "192.168.[0-9][0-9].100")
echo -e "활성 네트워크 인터페이스: ${GREEN}${INTERFACE_COUNT}개${NC}"

# 3. 개수 비교 및 자동 복구
if [ "$EXPECTED_COUNT" -gt 0 ] && [ "$INTERFACE_COUNT" -lt "$EXPECTED_COUNT" ]; then
    echo -e "\n${RED}경고: 네트워크 인터페이스(${INTERFACE_COUNT})가 물리적 동글(${EXPECTED_COUNT})보다 적습니다${NC}"
    echo -e "${YELLOW}USB 허브 재시작을 시도합니다...${NC}"
    
    # 메인 허브 찾기
    MAIN_HUB=$(sudo uhubctl | grep "hub 1-" | grep -v "\." | grep -oE "1-[0-9]+" | head -1)
    if [ -z "$MAIN_HUB" ]; then
        MAIN_HUB="1-3"  # 기본값
    fi
    
    # 서브 허브 찾기
    SUB_HUBS=$(sudo uhubctl | grep "hub ${MAIN_HUB}\." | grep -oE "${MAIN_HUB}\.[0-9]+" | sort -u)
    
    # USB 허브 재시작
    echo -e "${BLUE}허브 재시작 중: ${MAIN_HUB} (서브허브: $(echo $SUB_HUBS | tr '\n' ' '))${NC}"
    
    # 각 서브 허브를 순차적으로 재시작
    for hub in $SUB_HUBS; do
        echo -e "  ${hub} 재시작 중..."
        sudo uhubctl -a cycle -l $hub -p 1,2,3,4 2>/dev/null
        sleep 2
    done
    
    # 네트워크 인터페이스가 올라올 때까지 대기 (최대 60초)
    echo -e "\n${YELLOW}네트워크 인터페이스 복구 대기 중...${NC}"
    MAX_WAIT=60
    WAIT_COUNT=0
    
    while [ "$INTERFACE_COUNT" -lt "$EXPECTED_COUNT" ] && [ "$WAIT_COUNT" -lt "$MAX_WAIT" ]; do
        sleep 2
        INTERFACE_COUNT=$(ip addr show | grep -c "192.168.[0-9][0-9].100")
        WAIT_COUNT=$((WAIT_COUNT + 2))
        echo -ne "\r  진행상황: ${INTERFACE_COUNT}/${EXPECTED_COUNT} 인터페이스 활성화 (${WAIT_COUNT}초 경과)"
    done
    echo ""
    
    if [ "$INTERFACE_COUNT" -eq "$EXPECTED_COUNT" ]; then
        echo -e "${GREEN}✓ 네트워크 인터페이스 복구 완료!${NC}"
    else
        echo -e "${YELLOW}⚠ 일부 인터페이스가 아직 활성화되지 않았습니다 (${INTERFACE_COUNT}/${EXPECTED_COUNT})${NC}"
        echo -e "${YELLOW}  수동으로 확인이 필요할 수 있습니다${NC}"
    fi
fi

# 4. 허브별 동글 정보 수집 (정보 수집용)
echo -e "\n${YELLOW}허브별 동글 정보 수집 중...${NC}"

# 메인 허브 확인
MAIN_HUB=$(sudo uhubctl | grep "hub 1-" | grep -v "\." | grep -oE "1-[0-9]+" | head -1)
if [ -z "$MAIN_HUB" ]; then
    MAIN_HUB="1-3"  # 기본값
fi
echo -e "메인 허브: ${GREEN}${MAIN_HUB}${NC}"

# 서브 허브 확인
SUB_HUBS=$(sudo uhubctl | grep "hub ${MAIN_HUB}\." | grep -oE "${MAIN_HUB}\.[0-9]+" | sort -u)
echo -e "서브 허브: ${GREEN}$(echo $SUB_HUBS | tr '\n' ' ')${NC}"

# 5. uhubctl로 실제 연결 상태 확인
PHYSICAL_COUNT=$(sudo uhubctl | grep "HUAWEI_MOBILE" | wc -l)
echo -e "uhubctl로 감지된 동글: ${GREEN}${PHYSICAL_COUNT}개${NC}"

# 각 허브의 동글 연결 포트 확인
declare -A HUB_PORTS

for hub in $SUB_HUBS; do
    ports=$(sudo uhubctl | grep -A4 "hub $hub" | grep "HUAWEI_MOBILE" | grep -oE "Port [0-9]+" | grep -oE "[0-9]+")
    if [ ! -z "$ports" ]; then
        port_array=$(echo $ports | tr ' ' ',')
        HUB_PORTS[$hub]=$port_array
        echo -e "  ${hub}: 포트 [${GREEN}${port_array}${NC}]에 동글 연결됨"
    else
        HUB_PORTS[$hub]=""
        echo -e "  ${hub}: 연결된 동글 없음"
    fi
done

# 6. 네트워크 인터페이스별 포트 매핑 및 USB 포트 매핑
echo -e "\n${YELLOW}네트워크 인터페이스 매핑 중...${NC}"

# 인터페이스 정보 수집
INTERFACE_MAPPING=""
PORT_MAPPING=""
ACTIVE_SUBNETS=$(ip addr show | grep -oE "192.168.([1-3][0-9]).100" | cut -d. -f3 | sort -u)

# USB 포트 매핑 함수
get_usb_port_for_subnet() {
    local subnet=$1
    local interface=$(ip addr | grep "192.168.${subnet}.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
    
    # 인터페이스 이름에서 USB 경로 추출 (예: enp0s21f0u3u4u1 → 3u4u1)
    local usb_path=$(echo "$interface" | grep -oE "u[0-9]+u[0-9]+(u[0-9]+)?" | tail -1)
    
    # uhubctl 출력에서 해당 동글의 허브와 포트 찾기
    local hub=""
    local port=""
    
    # 각 서브허브를 확인
    for sub_hub in $SUB_HUBS; do
        local hub_ports=$(sudo uhubctl | grep -A10 "hub $sub_hub" | grep "HUAWEI_MOBILE" | grep -oE "Port [0-9]+" | grep -oE "[0-9]+")
        for p in $hub_ports; do
            # 해당 포트에 동글이 있는지 확인 (간단한 매핑)
            if [ ! -z "$hub_ports" ]; then
                if [ -z "$hub" ]; then
                    hub="$sub_hub"
                    port="$p"
                    break
                fi
            fi
        done
    done
    
    # 기본값 설정 (찾지 못한 경우)
    if [ -z "$hub" ]; then
        # 서브넷 번호로 추정
        if [ "$subnet" -ge 11 ] && [ "$subnet" -le 14 ]; then
            hub="1-3.4"
            port=$((subnet - 10))
        elif [ "$subnet" -ge 15 ] && [ "$subnet" -le 18 ]; then
            hub="1-3.1"
            port=$((subnet - 14))
        else
            hub="1-3.3"
            port=1
        fi
    fi
    
    echo "$hub:$port"
}

for subnet in $ACTIVE_SUBNETS; do
    interface=$(ip addr | grep "192.168.${subnet}.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
    socks_port=$((10000 + subnet))
    
    # USB 포트 정보 가져오기
    usb_info=$(get_usb_port_for_subnet $subnet)
    hub=$(echo $usb_info | cut -d: -f1)
    port=$(echo $usb_info | cut -d: -f2)
    
    if [ ! -z "$INTERFACE_MAPPING" ]; then
        INTERFACE_MAPPING="$INTERFACE_MAPPING,
"
    fi
    
    if [ ! -z "$PORT_MAPPING" ]; then
        PORT_MAPPING="$PORT_MAPPING,
"
    fi
    
    INTERFACE_MAPPING="$INTERFACE_MAPPING    \"${subnet}\": {
      \"interface\": \"${interface}\",
      \"ip\": \"192.168.${subnet}.100\",
      \"gateway\": \"192.168.${subnet}.1\",
      \"socks5_port\": ${socks_port}
    }"
    
    PORT_MAPPING="$PORT_MAPPING    \"${subnet}\": {
      \"hub\": \"${hub}\",
      \"port\": ${port}
    }"
    
    echo -e "  동글${subnet}: ${GREEN}${interface}${NC} (192.168.${subnet}.100) → SOCKS5 포트 ${GREEN}${socks_port}${NC} [Hub: ${hub}, Port: ${port}]"
done

# 7. 최종 상태 확인
echo -e "\n${YELLOW}최종 상태:${NC}"
INTERFACE_COUNT=$(ip addr show | grep -c "192.168.[0-9][0-9].100")
echo -e "  예상 동글 개수 (lsusb): ${GREEN}${EXPECTED_COUNT}개${NC}"
echo -e "  활성 네트워크 인터페이스: ${GREEN}${INTERFACE_COUNT}개${NC}"
echo -e "  uhubctl 감지 동글: ${GREEN}${PHYSICAL_COUNT}개${NC}"

if [ "$EXPECTED_COUNT" -eq "$INTERFACE_COUNT" ]; then
    echo -e "\n${GREEN}✓ 초기 설정 완료! 모든 동글이 정상 작동 중입니다.${NC}"
else
    echo -e "\n${YELLOW}⚠ 일부 동글이 아직 활성화되지 않았습니다${NC}"
    echo -e "  개별 동글 제어가 필요한 경우 수동으로 관리하세요"
fi

# 8. JSON 설정 파일 생성
echo -e "\n${YELLOW}설정 파일 생성 중...${NC}"

# 서브 허브 배열 생성
SUB_HUB_JSON=""
for hub in $SUB_HUBS; do
    if [ -z "$SUB_HUB_JSON" ]; then
        SUB_HUB_JSON="\"$hub\""
    else
        SUB_HUB_JSON="$SUB_HUB_JSON, \"$hub\""
    fi
done

# 물리적 동글 정보 생성
PHYSICAL_DONGLES_JSON=""
for hub in $SUB_HUBS; do
    ports="${HUB_PORTS[$hub]}"
    if [ ! -z "$PHYSICAL_DONGLES_JSON" ]; then
        PHYSICAL_DONGLES_JSON="$PHYSICAL_DONGLES_JSON,
"
    fi
    
    if [ -z "$ports" ]; then
        PHYSICAL_DONGLES_JSON="$PHYSICAL_DONGLES_JSON    \"$hub\": []"
    else
        port_json=$(echo "$ports" | sed 's/,/, /g')
        PHYSICAL_DONGLES_JSON="$PHYSICAL_DONGLES_JSON    \"$hub\": [$port_json]"
    fi
done

# JSON 파일 생성 (expected_count를 lsusb 기준으로)
cat > "$CONFIG_FILE" << EOF
{
  "expected_count": ${EXPECTED_COUNT},
  "hub_info": {
    "main_hub": "${MAIN_HUB}",
    "sub_hubs": [${SUB_HUB_JSON}],
    "ports_per_hub": 4
  },
  "physical_dongles": {
${PHYSICAL_DONGLES_JSON}
  },
  "interface_mapping": {
${INTERFACE_MAPPING}
  },
  "port_mapping": {
${PORT_MAPPING}
  },
  "status": {
    "lsusb_count": ${EXPECTED_COUNT},
    "interface_count": ${INTERFACE_COUNT},
    "uhubctl_count": ${PHYSICAL_COUNT}
  },
  "created_at": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF

echo -e "${GREEN}설정 파일이 생성되었습니다: ${CONFIG_FILE}${NC}"

# 9. 설정 파일 내용 표시
echo -e "\n${YELLOW}=== 설정 파일 내용 ===${NC}"
cat "$CONFIG_FILE"

# 10. 서버 정보 표시
echo -e "\n${YELLOW}=== 서버 정보 ===${NC}"
echo -e "서버 IP: ${GREEN}$(hostname -I | awk '{print $1}')${NC}"
echo -e "예상 동글 개수 (lsusb): ${GREEN}${EXPECTED_COUNT}개${NC}"
echo -e "활성 네트워크 인터페이스: ${GREEN}${INTERFACE_COUNT}개${NC}"
echo -e "uhubctl 감지 동글: ${GREEN}${PHYSICAL_COUNT}개${NC}"

# 활성 프록시 정보 표시
echo -e "\n${YELLOW}=== 활성 프록시 정보 ===${NC}"
SERVER_IP=$(hostname -I | awk '{print $1}')
for subnet in $ACTIVE_SUBNETS; do
    socks_port=$((10000 + subnet))
    echo -e "  ${GREEN}socks5://${SERVER_IP}:${socks_port}${NC} (동글${subnet})"
done

# 11. SOCKS5 개별 서비스 생성
echo -e "\n${YELLOW}=== SOCKS5 개별 서비스 설정 중 ===${NC}"

# 기존 통합 서비스 중지 및 비활성화
if systemctl is-active --quiet dongle-socks5; then
    echo -e "기존 통합 SOCKS5 서비스 중지..."
    sudo systemctl stop dongle-socks5
    sudo systemctl disable dongle-socks5 2>/dev/null
fi

# 개별 서비스 파일 생성
for subnet in $ACTIVE_SUBNETS; do
    SERVICE_FILE="/etc/systemd/system/dongle-socks5-${subnet}.service"
    
    echo -n "  동글${subnet} SOCKS5 서비스 생성... "
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=SOCKS5 Proxy for Dongle ${subnet}
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/proxy/scripts/socks5
ExecStart=/usr/bin/python3 /home/proxy/scripts/socks5/socks5_single.py ${subnet}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 서비스 활성화 및 시작
    sudo systemctl daemon-reload
    sudo systemctl enable dongle-socks5-${subnet} 2>/dev/null
    sudo systemctl restart dongle-socks5-${subnet}
    
    if systemctl is-active --quiet dongle-socks5-${subnet}; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
done

echo -e "\n${GREEN}=== 설정 초기화 완료! ===${NC}"