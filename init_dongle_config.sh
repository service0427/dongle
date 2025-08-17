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

# 전역 변수로 사용된 포트 추적
declare -A USED_PORTS

# USB 포트 매핑 함수
get_usb_port_for_subnet() {
    local subnet=$1
    local interface=$(ip addr | grep "192.168.${subnet}.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
    
    # 인터페이스 이름에서 USB 경로 추출 (예: enp0s21f0u3u4u1 → 3u4u1)
    local usb_path=$(echo "$interface" | grep -oE "u[0-9]+u[0-9]+(u[0-9]+)?" | tail -1)
    
    # 기본 매핑 규칙 (인터페이스 이름 패턴 기반)
    local hub=""
    local port=""
    
    # 인터페이스 이름 패턴으로 허브 구분
    # enp0s21f0u3u4u* → hub 1-3.4
    # enp0s21f0u3u1u* → hub 1-3.1
    if [[ "$interface" =~ u3u4u([0-9]+) ]]; then
        hub="1-3.4"
        port="${BASH_REMATCH[1]}"
    elif [[ "$interface" =~ u3u1u([0-9]+) ]]; then
        hub="1-3.1"
        port="${BASH_REMATCH[1]}"
    elif [[ "$interface" =~ u3u3u([0-9]+) ]]; then
        hub="1-3.3"
        port="${BASH_REMATCH[1]}"
    else
        # 기본값: 서브넷 번호로 추정
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
    
    # 이미 사용된 포트인지 확인
    local key="${hub}:${port}"
    if [ ! -z "${USED_PORTS[$key]}" ]; then
        # 이미 사용된 경우 다음 사용 가능한 포트 찾기
        for try_port in 1 2 3 4; do
            key="${hub}:${try_port}"
            if [ -z "${USED_PORTS[$key]}" ]; then
                port=$try_port
                break
            fi
        done
    fi
    
    # 사용된 포트로 표시
    USED_PORTS["${hub}:${port}"]=1
    
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

# 12. 허브 전체 재시작 스크립트 생성
echo -e "\n${YELLOW}=== 허브 전체 재시작 스크립트 생성 중 ===${NC}"

# 동글이 연결된 메인 허브 감지
echo "동글이 연결된 메인 허브 감지 중..."
MAIN_HUBS_WITH_DONGLES=""

# 모든 메인 허브 찾기 (점이 없는 허브)
# "hub 1-3 " 같은 패턴을 찾되, "hub 1-3.1" 같은 서브 허브는 제외
ALL_MAIN_HUBS=$(sudo uhubctl | awk '/Current status for hub [0-9]+-[0-9]+[^.]/ {match($0, /[0-9]+-[0-9]+/); print substr($0, RSTART, RLENGTH)}' | sort -u)

for main_hub in $ALL_MAIN_HUBS; do
    # 해당 메인 허브의 서브 허브들 확인
    sub_hubs=$(sudo uhubctl | grep "hub ${main_hub}\." | grep -oE "${main_hub}\.[0-9]+" | sort -u)
    has_dongles=false
    
    # 서브 허브에 동글이 있는지 확인
    for sub_hub in $sub_hubs; do
        if sudo uhubctl | grep -A4 "hub $sub_hub" | grep -q "HUAWEI_MOBILE"; then
            has_dongles=true
            break
        fi
    done
    
    # 메인 허브 자체에 직접 연결된 동글 확인
    if sudo uhubctl | grep -A4 "hub $main_hub" | grep -q "HUAWEI_MOBILE"; then
        has_dongles=true
    fi
    
    if [ "$has_dongles" = true ]; then
        if [ -z "$MAIN_HUBS_WITH_DONGLES" ]; then
            MAIN_HUBS_WITH_DONGLES="$main_hub"
        else
            MAIN_HUBS_WITH_DONGLES="$MAIN_HUBS_WITH_DONGLES $main_hub"
        fi
        echo "  메인 허브 $main_hub 에 동글 발견"
    fi
done

echo "동글이 연결된 메인 허브: $MAIN_HUBS_WITH_DONGLES"

RESTART_SCRIPT="/home/proxy/scripts/restart_all_hubs.sh"

cat > "$RESTART_SCRIPT" << 'HUBSCRIPT'
#!/bin/bash
#
# USB 허브 전체 재시작 스크립트
# 자동 생성됨: CREATED_TIME
#

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== USB 허브 전체 재시작 ===${NC}"
echo -e "이 작업은 모든 동글의 연결을 일시적으로 끊습니다."
echo -n "계속하시겠습니까? (y/n): "
read -r answer

if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "취소되었습니다."
    exit 0
fi

# 허브 정보
MAIN_HUBS_WITH_DONGLES="MAIN_HUBS_PLACEHOLDER"
SUB_HUBS=(SUB_HUBS_PLACEHOLDER)

echo -e "\n${YELLOW}토글 API 서비스 중지...${NC}"
sudo systemctl stop dongle-toggle-api 2>/dev/null

echo -e "\n${YELLOW}SOCKS5 서비스 중지...${NC}"
for i in {11..30}; do
    if systemctl is-active --quiet dongle-socks5-$i; then
        sudo systemctl stop dongle-socks5-$i
        echo -e "  동글$i SOCKS5 중지됨"
    fi
done

echo -e "\n${YELLOW}USB 허브 재시작 중...${NC}"

# 동글이 연결된 메인 허브만 재시작
for main_hub in $MAIN_HUBS_WITH_DONGLES; do
    echo -e "  ${GREEN}메인 허브 ${main_hub} 재시작...${NC}"
    
    # USB 2.0 메인 허브 재시작 (1-x 형식)
    if [[ "$main_hub" =~ ^1- ]]; then
        sudo uhubctl -a cycle -l "$main_hub" -p 1,2,3,4 2>/dev/null || true
    fi
    
    # USB 3.0 메인 허브 재시작 (2-x 형식)
    if [[ "$main_hub" =~ ^2- ]]; then
        sudo uhubctl -a cycle -l "$main_hub" -p 1,2,3,4 2>/dev/null || true
    fi
    
    sleep 5  # 메인 허브 재시작 후 충분한 대기
done

# 재연결 대기
echo -e "\n${YELLOW}동글 재연결 대기 중...${NC}"
MAX_WAIT=60
WAIT_COUNT=0
EXPECTED_COUNT=EXPECTED_COUNT_PLACEHOLDER

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    CURRENT_COUNT=$(lsusb | grep -ci "huawei" || echo "0")
    echo -ne "\r  진행상황: ${CURRENT_COUNT}/${EXPECTED_COUNT} 동글 감지 (${WAIT_COUNT}초 경과)"
    
    if [ "$CURRENT_COUNT" -ge "$EXPECTED_COUNT" ]; then
        echo -e "\n${GREEN}✓ 모든 동글이 재연결되었습니다!${NC}"
        break
    fi
    
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ "$CURRENT_COUNT" -lt "$EXPECTED_COUNT" ]; then
    echo -e "\n${YELLOW}⚠ 일부 동글이 아직 연결되지 않았습니다 (${CURRENT_COUNT}/${EXPECTED_COUNT})${NC}"
fi

# 네트워크 인터페이스 대기
echo -e "\n${YELLOW}네트워크 인터페이스 활성화 대기 중...${NC}"

# DHCP 재요청으로 인터페이스 활성화
for i in {1..30}; do
    CURRENT_IF_COUNT=$(ip addr show | grep -c "192.168.[1-3][0-9].100")
    echo -ne "\r  인터페이스 활성화: ${CURRENT_IF_COUNT}/${EXPECTED_COUNT} ($((i*2))초 경과)"
    
    if [ "$CURRENT_IF_COUNT" -ge "$EXPECTED_COUNT" ]; then
        echo -e "\n${GREEN}✓ 모든 인터페이스 활성화됨${NC}"
        break
    fi
    
    # 인터페이스가 없는 동글에 DHCP 재요청
    for device in $(ls /sys/class/net/ | grep -E "^e"); do
        if ! ip addr show $device | grep -q "192.168"; then
            dhclient -r $device 2>/dev/null
            dhclient $device 2>/dev/null &
        fi
    done
    
    sleep 2
done

# 라우팅 재설정
echo -e "\n${YELLOW}라우팅 재설정 중...${NC}"
for subnet in {11..30}; do
    interface=$(ip addr | grep "192.168.$subnet.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
    if [ -n "$interface" ]; then
        sudo ip route add default via 192.168.$subnet.1 dev $interface table $subnet 2>/dev/null
        sudo ip rule add from 192.168.$subnet.100 table $subnet 2>/dev/null
        echo -e "  동글$subnet 라우팅 설정됨"
    fi
done

echo -e "\n${YELLOW}SOCKS5 서비스 재시작...${NC}"
for i in {11..30}; do
    if [ -f "/etc/systemd/system/dongle-socks5-$i.service" ]; then
        sudo systemctl start dongle-socks5-$i
        if systemctl is-active --quiet dongle-socks5-$i; then
            echo -e "  동글$i SOCKS5 ${GREEN}시작됨${NC}"
        fi
    fi
done

echo -e "\n${YELLOW}토글 API 서비스 재시작...${NC}"
sudo systemctl start dongle-toggle-api

echo -e "\n${GREEN}=== 허브 재시작 완료! ===${NC}"
echo -e "상태 확인: curl http://localhost/status"
HUBSCRIPT

# 플레이스홀더 교체
sed -i "s/CREATED_TIME/$(date '+%Y-%m-%d %H:%M:%S')/" "$RESTART_SCRIPT"
sed -i "s/MAIN_HUBS_PLACEHOLDER/$MAIN_HUBS_WITH_DONGLES/" "$RESTART_SCRIPT"
sed -i "s/SUB_HUBS_PLACEHOLDER/$(echo $SUB_HUBS | tr ' ' ' ')/" "$RESTART_SCRIPT"
sed -i "s/EXPECTED_COUNT_PLACEHOLDER/$EXPECTED_COUNT/" "$RESTART_SCRIPT"

chmod +x "$RESTART_SCRIPT"
echo -e "${GREEN}허브 재시작 스크립트 생성 완료: $RESTART_SCRIPT${NC}"

echo -e "\n${GREEN}=== 설정 초기화 완료! ===${NC}"