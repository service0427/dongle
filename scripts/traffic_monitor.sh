#!/bin/bash

# 실시간 트래픽 모니터링 스크립트

echo "=== 동글 트래픽 모니터링 ==="
echo "업데이트 간격: 2초"
echo "종료: Ctrl+C"
echo ""

while true; do
    clear
    echo "=== 동글 트래픽 현황 - $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo ""
    
    # 각 동글별 트래픽 통계
    for i in 11 16 17 18 19; do
        if ip addr show | grep -q "192.168.$i.100"; then
            interface=$(ip addr show | grep "192.168.$i.100" | awk '{print $NF}')
            
            # 인터페이스 통계 가져오기
            if [ ! -z "$interface" ]; then
                stats=$(ip -s link show $interface 2>/dev/null)
                if [ ! -z "$stats" ]; then
                    rx_bytes=$(echo "$stats" | grep -A1 "RX:" | tail -1 | awk '{print $1}')
                    tx_bytes=$(echo "$stats" | grep -A1 "TX:" | tail -1 | awk '{print $1}')
                    
                    # 바이트를 MB/GB로 변환
                    rx_mb=$(echo "scale=2; $rx_bytes/1024/1024" | bc 2>/dev/null || echo "0")
                    tx_mb=$(echo "scale=2; $tx_bytes/1024/1024" | bc 2>/dev/null || echo "0")
                    
                    echo "동글 $i ($interface):"
                    echo "  다운로드: ${rx_mb} MB"
                    echo "  업로드: ${tx_mb} MB"
                    echo ""
                fi
            fi
        fi
    done
    
    echo "----------------------------------------"
    echo "SOCKS5 프록시 연결 상태:"
    echo ""
    
    # 각 포트별 활성 연결 수
    for port in 10011 10016; do
        connections=$(ss -tn | grep ":$port" | grep ESTAB | wc -l)
        echo "포트 $port: $connections 활성 연결"
    done
    
    echo ""
    echo "최근 연결된 IP들:"
    ss -tn | grep -E ":1001[16]" | grep ESTAB | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5
    
    sleep 2
done