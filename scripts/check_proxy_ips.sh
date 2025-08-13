#!/bin/bash
#
# 프록시별 외부 IP 체크 스크립트
# 각 SOCKS5 프록시를 통해 실제 외부 IP 확인
#

echo "========================================="
echo "    프록시 외부 IP 체크"
echo "    $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo ""

# 색상 코드
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 결과 카운터
total=0
working=0
failed=0

# IP 체크 URL
CHECK_URL="http://techb.kr/ip.php"

# 서버 외부 IP 동적으로 가져오기
SERVER_IP=$(curl -s -m 3 http://techb.kr/ip.php 2>/dev/null | head -1)
if [ -z "$SERVER_IP" ]; then
    # 실패시 메인 인터페이스 IP 사용
    SERVER_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
fi
# 여전히 없으면 기본값 사용
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="0.0.0.0"
fi

# 헤더 출력
printf "%-8s %-15s %-20s %-15s %-10s\n" "동글" "포트" "외부 IP" "응답시간" "상태"
echo "---------------------------------------------------------------------------"

# 11-30번 동글 체크
for subnet in {11..30}; do
    port=$((10000 + subnet))
    
    # 포트가 열려있는지 먼저 확인
    if ! netstat -tln 2>/dev/null | grep -q ":$port "; then
        continue
    fi
    
    total=$((total + 1))
    
    # 시작 시간
    start_time=$(date +%s%N)
    
    # SOCKS5 프록시를 통해 IP 체크
    result=$(timeout 5 curl -s --socks5 127.0.0.1:$port "$CHECK_URL" 2>/dev/null)
    exit_code=$?
    
    # 종료 시간 및 응답 시간 계산
    end_time=$(date +%s%N)
    response_time=$(echo "scale=3; ($end_time - $start_time) / 1000000000" | bc)
    
    # 결과 처리
    if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
        # IP 주소 추출 (숫자와 점으로 이루어진 패턴)
        ip=$(echo "$result" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        
        if [ -n "$ip" ]; then
            working=$((working + 1))
            printf "%-8s %-15s ${GREEN}%-20s${NC} %-15s ${GREEN}%-10s${NC}\n" \
                "동글$subnet" "127.0.0.1:$port" "$ip" "${response_time}초" "✓ 정상"
        else
            failed=$((failed + 1))
            printf "%-8s %-15s ${YELLOW}%-20s${NC} %-15s ${YELLOW}%-10s${NC}\n" \
                "동글$subnet" "127.0.0.1:$port" "응답 파싱 실패" "${response_time}초" "⚠ 경고"
        fi
    elif [ $exit_code -eq 124 ]; then
        failed=$((failed + 1))
        printf "%-8s %-15s ${RED}%-20s${NC} %-15s ${RED}%-10s${NC}\n" \
            "동글$subnet" "127.0.0.1:$port" "타임아웃" ">5.000초" "✗ 실패"
    else
        failed=$((failed + 1))
        printf "%-8s %-15s ${RED}%-20s${NC} %-15s ${RED}%-10s${NC}\n" \
            "동글$subnet" "127.0.0.1:$port" "연결 실패" "-" "✗ 실패"
    fi
done

# 요약 정보
echo ""
echo "========================================="
echo "    체크 완료"
echo "========================================="
echo "  전체 프록시: $total 개"
echo -e "  ${GREEN}정상 작동: $working 개${NC}"
if [ $failed -gt 0 ]; then
    echo -e "  ${RED}실패: $failed 개${NC}"
fi

# 성공률 계산
if [ $total -gt 0 ]; then
    success_rate=$(echo "scale=1; $working * 100 / $total" | bc)
    echo "  성공률: ${success_rate}%"
fi

echo ""

# 외부 접속용 정보 (정상 작동하는 프록시만)
if [ $working -gt 0 ]; then
    echo "외부 접속용 프록시 주소:"
    echo "---------------------------------------------------------------------------"
    for subnet in {11..30}; do
        port=$((10000 + subnet))
        if ! netstat -tln 2>/dev/null | grep -q ":$port "; then
            continue
        fi
        
        # 정상 작동 확인
        result=$(timeout 3 curl -s --socks5 127.0.0.1:$port "$CHECK_URL" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$result" ]; then
            ip=$(echo "$result" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            if [ -n "$ip" ]; then
                echo "  socks5://$SERVER_IP:$port -> $ip"
            fi
        fi
    done
    echo ""
fi

# 문제가 있을 경우 조치 사항
if [ $failed -gt 0 ]; then
    echo "⚠ 조치 필요:"
    echo "  1. 실패한 동글의 연결 상태 확인: ping 192.168.XX.1"
    echo "  2. SOCKS5 서비스 재시작: sudo systemctl restart dongle-socks5"
    echo "  3. 라우팅 재설정: sudo /home/proxy/v1/scripts/manual_setup.sh"
    echo ""
fi