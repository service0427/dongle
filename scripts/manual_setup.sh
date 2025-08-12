#!/bin/bash
#
# 동글 초기 설정 스크립트 (v1 - 안정화 버전)
# 사용법: sudo ./manual_setup.sh
#

echo "========================================="
echo "    동글 라우팅 초기 설정 (v1)"
echo "========================================="

# 1. IP 포워딩 활성화
echo "1. IP 포워딩 활성화..."
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

# 2. 메인 인터페이스 메트릭 설정
echo "2. 메인 인터페이스 메트릭 조정..."
MAIN_DEV=$(ip route show | grep "^default" | grep -v "192.168" | head -1 | awk '{print $5}')
MAIN_GW=$(ip route show | grep "^default" | grep -v "192.168" | head -1 | awk '{print $3}')

if [ -n "$MAIN_GW" ] && [ -n "$MAIN_DEV" ]; then
    # 메인 인터페이스 메트릭 확인
    CURRENT_METRIC=$(ip route show | grep "^default via $MAIN_GW" | grep -o "metric [0-9]*" | awk '{print $2}')
    if [ "$CURRENT_METRIC" != "100" ]; then
        ip route del default via $MAIN_GW dev $MAIN_DEV 2>/dev/null
        ip route add default via $MAIN_GW dev $MAIN_DEV metric 100
        echo "   메인 게이트웨이: $MAIN_GW ($MAIN_DEV) - metric 100 설정"
    else
        echo "   메인 게이트웨이: $MAIN_GW ($MAIN_DEV) - metric 100 유지"
    fi
fi

# 3. 연결된 동글 설정
echo "3. 동글 라우팅 설정..."
dongles_found=0
dongles_configured=0
dongles_skipped=0

for subnet in {11..30}; do
    # 인터페이스 찾기
    interface=$(ip addr show | grep "192.168.$subnet.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
    
    if [ -n "$interface" ]; then
        dongles_found=$((dongles_found + 1))
        
        # 이미 설정되어 있는지 확인
        if ip route show table dongle$subnet 2>/dev/null | grep -q "default via 192.168.$subnet.1"; then
            echo "   동글 $subnet ($interface) - 이미 설정됨 [건너뜀]"
            dongles_skipped=$((dongles_skipped + 1))
            continue
        fi
        
        echo "   동글 $subnet ($interface) - 새로 설정"
        dongles_configured=$((dongles_configured + 1))
        
        # 메인 테이블에서 동글 default route 제거
        ip route del default via 192.168.$subnet.1 dev $interface 2>/dev/null
        
        # 동글 전용 라우팅 테이블 설정
        ip route flush table dongle$subnet 2>/dev/null
        ip route add default via 192.168.$subnet.1 dev $interface table dongle$subnet
        ip route add 192.168.$subnet.0/24 dev $interface src 192.168.$subnet.100 table dongle$subnet
        
        # IP rule 설정 (중복 제거 후 추가)
        while ip rule del from 192.168.$subnet.100 table dongle$subnet 2>/dev/null; do :; done
        ip rule add from 192.168.$subnet.100 table dongle$subnet
        
        # NAT 설정 (중복 제거 후 추가)
        iptables -t nat -D POSTROUTING -s 192.168.$subnet.0/24 -j MASQUERADE 2>/dev/null
        iptables -t nat -A POSTROUTING -s 192.168.$subnet.0/24 -j MASQUERADE
    fi
done

echo ""
echo "========================================="
echo "설정 완료"
echo "  - 전체 동글: $dongles_found 개"
echo "  - 새로 설정: $dongles_configured 개"
echo "  - 기존 유지: $dongles_skipped 개"
echo "========================================="

# 4. 연결 테스트 (선택사항)
if [ "$dongles_configured" -gt 0 ]; then
    echo ""
    echo "새로 설정된 동글 테스트 중..."
    for subnet in {11..30}; do
        interface=$(ip addr show | grep "192.168.$subnet.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
        if [ -n "$interface" ]; then
            # 라우팅 테이블이 방금 설정되었는지 확인
            if [ "$dongles_configured" -gt 0 ]; then
                result=$(curl --interface 192.168.$subnet.100 -s -m 3 http://ipinfo.io/ip 2>/dev/null)
                if [ -n "$result" ]; then
                    echo "   ✓ 동글 $subnet: $result"
                else
                    echo "   ✗ 동글 $subnet: 연결 확인 실패"
                fi
            fi
        fi
    done
fi