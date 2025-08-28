#!/bin/bash
#
# 라우팅 우선순위 강제 설정 스크립트
# 재부팅 후 메인 인터페이스가 항상 최우선이 되도록 보장
#

echo "=== 라우팅 우선순위 수정 시작 ==="

# 메인 인터페이스 찾기 (USB가 아닌 첫 번째 인터페이스)
MAIN_IF=$(ip link show | grep -E "^[0-9]+: e" | grep -v "usb" | head -1 | cut -d: -f2 | tr -d ' ' | cut -d@ -f1)

if [ -z "$MAIN_IF" ]; then
    # 대체: eno 또는 eth로 시작하는 인터페이스
    MAIN_IF=$(ip link show | grep -E "^[0-9]+: (eno|eth)" | head -1 | cut -d: -f2 | tr -d ' ')
fi

if [ -z "$MAIN_IF" ]; then
    echo "ERROR: 메인 인터페이스를 찾을 수 없습니다"
    exit 1
fi

echo "메인 인터페이스: $MAIN_IF"

# 메인 인터페이스의 기본 게이트웨이 찾기
MAIN_GW=$(ip route | grep "^default.*dev $MAIN_IF" | awk '{print $3}' | head -1)

if [ -z "$MAIN_GW" ]; then
    echo "ERROR: 메인 게이트웨이를 찾을 수 없습니다"
    exit 1
fi

echo "메인 게이트웨이: $MAIN_GW"

# 1. 모든 기본 라우트 삭제
echo "기존 기본 라우트 삭제 중..."
ip route | grep "^default" | while read line; do
    ip route del $line 2>/dev/null
done

# 2. 메인 인터페이스를 metric 1로 재설정
echo "메인 인터페이스 라우트 설정 (metric 1)..."
ip route add default via $MAIN_GW dev $MAIN_IF metric 1

# 3. 동글 인터페이스들을 높은 metric으로 재설정
echo "동글 인터페이스 라우트 재설정..."
BASE_METRIC=200

for subnet in {11..30}; do
    # 인터페이스 찾기
    IFACE=$(ip addr | grep "192.168.$subnet.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ' 2>/dev/null)
    
    if [ -n "$IFACE" ]; then
        GW="192.168.$subnet.1"
        METRIC=$((BASE_METRIC + subnet))
        
        # 기본 라우트 추가 (높은 메트릭)
        ip route add default via $GW dev $IFACE metric $METRIC 2>/dev/null
        
        # 라우팅 테이블 설정
        ip route add default via $GW dev $IFACE table $subnet 2>/dev/null
        ip rule add from 192.168.$subnet.100 table $subnet 2>/dev/null
        
        echo "  Subnet $subnet ($IFACE): metric $METRIC 설정됨"
    fi
done

# 4. 결과 확인
echo ""
echo "=== 수정된 라우팅 테이블 ==="
ip route | grep "^default" | head -5

echo ""
echo "=== 메트릭 확인 ==="
ip route | grep "^default" | awk '{print $NF" - "$3}' | sort -n | head -5

echo ""
echo "완료! 메인 인터페이스($MAIN_IF)가 최우선 순위를 갖습니다."