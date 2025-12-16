#!/bin/bash
#
# USB 허브 전체 재시작 스크립트
# 자동 생성됨: 2025-11-23 10:27:03
#

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== USB 허브 전체 재시작 ===${NC}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 시작"

# 허브 정보
MAIN_HUBS_WITH_DONGLES=""
SUB_HUBS=(1-3.4)

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

# USB 컨트롤러 강제 리셋 함수 (uhubctl 실패 시 사용)
reset_usb_controller() {
    local PCI_ID=$(lspci -D 2>/dev/null | grep -i xhci | awk '{print $1}' | head -1)
    if [ -n "$PCI_ID" ]; then
        echo -e "${YELLOW}USB 컨트롤러 강제 리셋: $PCI_ID${NC}"
        echo -n "$PCI_ID" > /sys/bus/pci/drivers/xhci_hcd/unbind 2>/dev/null
        sleep 2
        echo -n "$PCI_ID" > /sys/bus/pci/drivers/xhci_hcd/bind 2>/dev/null
        sleep 10
        return 0
    else
        echo -e "${RED}USB 컨트롤러를 찾을 수 없습니다 (lspci 설치 필요)${NC}"
        return 1
    fi
}

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
EXPECTED_COUNT=1

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
    echo -e "${YELLOW}USB 컨트롤러 강제 리셋 시도...${NC}"
    reset_usb_controller

    # 리셋 후 다시 대기
    sleep 15
    CURRENT_COUNT=$(lsusb | grep -ci "huawei" || echo "0")
    echo -e "리셋 후 동글 수: ${CURRENT_COUNT}/${EXPECTED_COUNT}"
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
