#!/bin/bash

# SOCKS5 메모리 사용량 확인 스크립트

echo "========================================="
echo "SOCKS5 Memory Usage Report"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo ""

TOTAL_MEMORY=0
HIGH_MEMORY_COUNT=0

# proxy_state.json에서 활성 동글 확인
if [ -f /home/proxy/proxy_state.json ]; then
    SUBNETS=$(python3 -c "
import json
with open('/home/proxy/proxy_state.json') as f:
    data = json.load(f)
    print(' '.join(data.keys()))
" 2>/dev/null)
else
    SUBNETS="11 12 13 14 15 16 17 18 19 20 21 22 23"
fi

# 헤더 출력
printf "%-8s %-10s %-12s %-10s %s\n" "Subnet" "PID" "Memory(MB)" "Threads" "Status"
echo "---------------------------------------------------------"

for subnet in $SUBNETS; do
    # PID 찾기
    pid=$(pgrep -f "socks5_single.py $subnet" | head -1)
    
    if [ -z "$pid" ]; then
        printf "%-8s %-10s %-12s %-10s %s\n" "$subnet" "-" "-" "-" "NOT RUNNING"
        continue
    fi
    
    # 메모리 사용량 (MB)
    memory_kb=$(ps -o rss= -p $pid 2>/dev/null | tr -d ' ')
    if [ -z "$memory_kb" ]; then
        printf "%-8s %-10s %-12s %-10s %s\n" "$subnet" "$pid" "-" "-" "ERROR"
        continue
    fi
    
    memory_mb=$((memory_kb / 1024))
    TOTAL_MEMORY=$((TOTAL_MEMORY + memory_mb))
    
    # 스레드 수
    threads=$(ps -o nlwp= -p $pid 2>/dev/null | tr -d ' ')
    
    # 상태 판단
    status="OK"
    if [ $memory_mb -gt 500 ]; then
        status="HIGH MEMORY!"
        HIGH_MEMORY_COUNT=$((HIGH_MEMORY_COUNT + 1))
    elif [ $memory_mb -gt 300 ]; then
        status="WARNING"
    fi
    
    if [ "$threads" -gt 150 ]; then
        status="$status, HIGH THREADS!"
    fi
    
    # 출력
    printf "%-8s %-10s %-12s %-10s %s\n" "$subnet" "$pid" "${memory_mb} MB" "$threads" "$status"
done

echo "---------------------------------------------------------"
echo ""
echo "Summary:"
echo "  Total Memory: ${TOTAL_MEMORY} MB"
echo "  Average Memory: $((TOTAL_MEMORY / $(echo $SUBNETS | wc -w))) MB per process"
echo "  High Memory Count: $HIGH_MEMORY_COUNT"
echo ""

if [ $HIGH_MEMORY_COUNT -gt 0 ]; then
    echo "⚠️  WARNING: $HIGH_MEMORY_COUNT processes exceed 500MB memory limit!"
    echo "  Consider restarting: /home/proxy/scripts/socks5/manage_socks5.sh restart all"
fi