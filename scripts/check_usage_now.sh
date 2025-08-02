#!/bin/bash

# 현재 데이터 사용량 즉시 확인

echo "=== 동글별 일일 데이터 사용량 ==="
echo "날짜: $(date +%Y-%m-%d)"
echo ""

for i in 11 16 17 18 19; do
    if ip addr show | grep -q "192.168.$i.100"; then
        interface=$(ip addr show | grep "192.168.$i.100" | awk '{print $NF}')
        
        # 현재 통계
        rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes)
        total_bytes=$((rx_bytes + tx_bytes))
        
        # GB로 변환
        total_gb=$(echo "scale=2; $total_bytes/1024/1024/1024" | bc)
        
        echo "동글 $i ($interface):"
        echo "  총 사용량: ${total_gb} GB"
        
        # 경고 표시
        if (( $(echo "$total_gb > 2" | bc -l) )); then
            echo "  ⚠️  경고: 2GB 초과! 속도 제한 가능"
        elif (( $(echo "$total_gb > 1.5" | bc -l) )); then
            echo "  ⚠️  주의: 1.5GB 초과"
        fi
        
        # 간단한 속도 테스트
        rx1=$rx_bytes
        sleep 1
        rx2=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        speed_bps=$((rx2 - rx1))
        speed_mbps=$(echo "scale=2; $speed_bps*8/1024/1024" | bc)
        
        echo "  현재 속도: ${speed_mbps} Mbps"
        
        if (( $(echo "$speed_mbps < 6" | bc -l) )); then
            echo "  🚫 속도 제한 의심 (5Mbps 이하)"
        fi
        
        echo ""
    fi
done

# 데이터 사용량 모니터 실행 옵션
echo "----------------------------------------"
echo "실시간 모니터링: python3 /home/proxy/network-monitor/scripts/data_usage_monitor.py"
echo "서비스로 실행: systemctl start data-usage-monitor"