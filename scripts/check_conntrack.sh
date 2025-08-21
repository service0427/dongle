#!/bin/bash

# nf_conntrack 모니터링 스크립트
# netfilter connection tracking 테이블 상태 확인

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BOLD}Netfilter Connection Tracking Status${NC}"
echo -e "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}=========================================${NC}"
echo ""

# 1. 전체 conntrack 통계
echo -e "${BOLD}Overall Statistics:${NC}"
if [ -f /proc/sys/net/netfilter/nf_conntrack_count ]; then
    CURRENT=$(cat /proc/sys/net/netfilter/nf_conntrack_count)
    MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
    USAGE=$(echo "scale=2; $CURRENT * 100 / $MAX" | bc)
    
    # 색상 설정
    if (( $(echo "$USAGE > 80" | bc -l) )); then
        COLOR=$RED
    elif (( $(echo "$USAGE > 50" | bc -l) )); then
        COLOR=$YELLOW
    else
        COLOR=$GREEN
    fi
    
    echo -e "  Current Connections: ${COLOR}${CURRENT}${NC} / ${MAX}"
    echo -e "  Usage: ${COLOR}${USAGE}%${NC}"
    echo ""
else
    echo "  conntrack not available"
    exit 1
fi

# 2. 상태별 연결 수
echo -e "${BOLD}Connection States:${NC}"
if [ -f /proc/net/nf_conntrack ]; then
    # TCP 상태별 카운트
    echo "  TCP States:"
    cat /proc/net/nf_conntrack | grep "^ipv4.*tcp" | \
        awk '{for(i=1;i<=NF;i++) if($i~/^[A-Z_]+$/ && $i!="ASSURED") print $i}' | \
        sort | uniq -c | sort -rn | \
        while read count state; do
            printf "    %-15s: %6d" "$state" "$count"
            # 경고 표시
            if [ "$state" = "TIME_WAIT" ] && [ $count -gt 1000 ]; then
                echo -e " ${YELLOW}(High)${NC}"
            elif [ "$state" = "ESTABLISHED" ]; then
                echo -e " ${GREEN}✓${NC}"
            else
                echo ""
            fi
        done
    
    # UDP 연결
    UDP_COUNT=$(cat /proc/net/nf_conntrack | grep "^ipv4.*udp" | wc -l)
    echo "  UDP Connections: $UDP_COUNT"
    echo ""
else
    echo "  Unable to read conntrack table"
fi

# 3. 동글별 연결 추적
echo -e "${BOLD}Dongle Connections:${NC}"
echo -e "  ${BOLD}Subnet   Outgoing  Incoming  Top Destinations${NC}"
echo "  --------------------------------------------------------"

for subnet in {11..23}; do
    if [ -f /proc/net/nf_conntrack ]; then
        # 해당 동글의 연결 확인
        OUTGOING=$(cat /proc/net/nf_conntrack | grep "src=192.168.$subnet.100 " | wc -l)
        INCOMING=$(cat /proc/net/nf_conntrack | grep "dst=192.168.$subnet.100 " | grep -v "src=192.168.$subnet.100" | wc -l)
        
        if [ $OUTGOING -gt 0 ] || [ $INCOMING -gt 0 ]; then
            # Top 목적지 찾기
            TOP_DEST=$(cat /proc/net/nf_conntrack | grep "src=192.168.$subnet.100 " | \
                awk '{for(i=1;i<=NF;i++) if($i~/^dst=/) print substr($i,5)}' | \
                sort | uniq -c | sort -rn | head -3 | \
                awk '{printf "%s(%d) ", $2, $1}' | sed 's/ $//')
            
            printf "  %-8s %-9d %-9d %s\n" "$subnet" "$OUTGOING" "$INCOMING" "${TOP_DEST:0:40}"
        fi
    fi
done
echo ""

# 4. SOCKS5 프록시 포트 연결
echo -e "${BOLD}SOCKS5 Proxy Connections:${NC}"
echo -e "  ${BOLD}Port    Clients  Status${NC}"
echo "  ------------------------"

for subnet in {11..23}; do
    PORT=$((10000 + subnet))
    if [ -f /proc/net/nf_conntrack ]; then
        # 해당 포트로의 연결 수
        CONNECTIONS=$(cat /proc/net/nf_conntrack | grep "dport=$PORT " | grep -v TIME_WAIT | wc -l)
        
        # 유니크 클라이언트 IP 수
        UNIQUE_CLIENTS=$(cat /proc/net/nf_conntrack | grep "dport=$PORT " | \
            awk '{for(i=1;i<=NF;i++) if($i~/^src=/ && $i!~/^src=192.168/) print substr($i,5)}' | \
            sort -u | wc -l)
        
        if [ $CONNECTIONS -gt 0 ] || [ $UNIQUE_CLIENTS -gt 0 ]; then
            STATUS="${GREEN}Active${NC}"
        else
            STATUS="Idle"
        fi
        
        if systemctl is-active --quiet dongle-socks5-$subnet 2>/dev/null; then
            printf "  %-7d %-8d %b\n" "$PORT" "$UNIQUE_CLIENTS" "$STATUS"
        fi
    fi
done
echo ""

# 5. Top 외부 연결
echo -e "${BOLD}Top External Connections:${NC}"
if [ -f /proc/net/nf_conntrack ]; then
    echo "  Top Source IPs (incoming to SOCKS5):"
    cat /proc/net/nf_conntrack | grep -E "dport=100[0-9][0-9] " | \
        awk '{for(i=1;i<=NF;i++) if($i~/^src=/ && $i!~/^src=192.168/) print substr($i,5)}' | \
        sort | uniq -c | sort -rn | head -5 | \
        while read count ip; do
            printf "    %-20s: %4d connections\n" "$ip" "$count"
        done
    
    echo ""
    echo "  Top Destination IPs (from dongles):"
    cat /proc/net/nf_conntrack | grep -E "src=192.168\.[0-9]+\.100 " | \
        awk '{for(i=1;i<=NF;i++) if($i~/^dst=/ && $i!~/^dst=192.168/) print substr($i,5)}' | \
        sort | uniq -c | sort -rn | head -5 | \
        while read count ip; do
            # DNS 역조회 시도 (빠른 타임아웃)
            HOST=$(timeout 0.5 host $ip 2>/dev/null | grep "domain name pointer" | awk '{print $NF}' | sed 's/\.$//' | head -1)
            if [ -n "$HOST" ]; then
                printf "    %-20s: %4d connections (%s)\n" "$ip" "$count" "$HOST"
            else
                printf "    %-20s: %4d connections\n" "$ip" "$count"
            fi
        done
fi
echo ""

# 6. 권장사항
echo -e "${BOLD}Recommendations:${NC}"

if (( $(echo "$USAGE > 80" | bc -l) )); then
    echo -e "  ${RED}⚠ Connection table usage is high ($USAGE%)${NC}"
    echo -e "  Consider increasing nf_conntrack_max:"
    echo -e "    echo 524288 > /proc/sys/net/netfilter/nf_conntrack_max"
fi

TIME_WAIT_COUNT=$(cat /proc/net/nf_conntrack 2>/dev/null | grep TIME_WAIT | wc -l)
if [ $TIME_WAIT_COUNT -gt 2000 ]; then
    echo -e "  ${YELLOW}⚠ High TIME_WAIT connections ($TIME_WAIT_COUNT)${NC}"
    echo -e "  Consider reducing TCP timeouts:"
    echo -e "    sysctl -w net.ipv4.tcp_fin_timeout=30"
    echo -e "    sysctl -w net.ipv4.tcp_tw_reuse=1"
fi

if (( $(echo "$USAGE < 20" | bc -l) )) && [ $TIME_WAIT_COUNT -lt 1000 ]; then
    echo -e "  ${GREEN}✓ Connection tracking is healthy${NC}"
fi

# 7. 튜닝 가능한 파라미터
echo ""
echo -e "${BOLD}Current Tuning Parameters:${NC}"
echo "  TCP Timeouts:"
echo "    ESTABLISHED: $(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established 2>/dev/null || echo 'N/A') seconds"
echo "    TIME_WAIT: $(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait 2>/dev/null || echo 'N/A') seconds"
echo "    CLOSE_WAIT: $(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_close_wait 2>/dev/null || echo 'N/A') seconds"
echo "    FIN_WAIT: $(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_fin_wait 2>/dev/null || echo 'N/A') seconds"
echo ""
echo "  Hashtable:"
echo "    Buckets: $(cat /proc/sys/net/netfilter/nf_conntrack_buckets 2>/dev/null || echo 'N/A')"
echo "    Max Entries: $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 'N/A')"