#!/bin/bash
#
# USB 허브 전체 재시작 스크립트
# 자동 생성됨: 2025-08-16 18:48:48
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
MAIN_HUB="1-3"
SUB_HUBS=(1-3.1 1-3.3 1-3.4)

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

# 각 서브 허브 재시작
for hub in "${SUB_HUBS[@]}"; do
    if [ ! -z "$hub" ]; then
        echo -e "  ${hub} 재시작..."
        sudo uhubctl -a cycle -l "$hub" -p 1,2,3,4 2>/dev/null
        sleep 2
    fi
done

# 재연결 대기
echo -e "\n${YELLOW}동글 재연결 대기 중...${NC}"
MAX_WAIT=60
WAIT_COUNT=0
EXPECTED_COUNT=8

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
sleep 5

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
echo -e "상태 확인: curl http://localhost:8080/status"
