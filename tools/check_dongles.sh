#!/bin/bash

echo "=== 동글 연결 상태 체크 ==="
echo "시간: $(date)"
echo

connected=0
for i in 11 12 14 15 16 17 18 19; do
    if ip addr | grep -q "192.168.${i}.100"; then
        iface=$(ip addr | grep -B2 "192.168.${i}.100" | head -1 | cut -d: -f2 | tr -d ' ')
        echo "동글 ${i}: 연결됨 (${iface})"
        ((connected++))
    else
        echo "동글 ${i}: 미연결"
    fi
done

echo
echo "총 연결된 동글: ${connected} / 9"
echo

echo "=== 라우팅 테이블 확인 ==="
for i in 11 12 14 15 16 17 18 19; do
    if ip rule | grep -q "from 192.168.${i}.0/24 lookup dongle${i}"; then
        echo "동글 ${i} 라우팅: 설정됨"
    fi
done

echo
echo "=== 최근 hotplug 이벤트 ==="
tail -10 /home/proxy/network-monitor/logs/hotplug.log 2>/dev/null | grep -E "add|remove|Dongle|ERROR" | tail -5