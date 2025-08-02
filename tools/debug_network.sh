#!/bin/bash

# 네트워크 문제 디버깅 스크립트

echo "========== Network Debug Report =========="
echo "Date: $(date)"
echo ""

echo "=== 1. 라우팅 테이블 (Default Routes) ==="
ip route | grep default | head -10
echo ""

echo "=== 2. 메인 인터페이스 (eno1) 상태 ==="
ip addr show eno1 2>/dev/null | grep -E "state|inet "
echo ""

echo "=== 3. 동글 인터페이스 상태 ==="
for i in {11..19}; do
    if ip addr show 2>/dev/null | grep -q "192.168.$i.100"; then
        iface=$(ip addr | grep "192.168.$i.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
        echo "Dongle $i ($iface): $(ip addr show $iface 2>/dev/null | grep state | awk '{print $9}')"
    fi
done
echo ""

echo "=== 4. IP 포워딩 상태 ==="
cat /proc/sys/net/ipv4/ip_forward
echo ""

echo "=== 5. 정책 라우팅 규칙 ==="
ip rule list | grep -E "dongle|main" | head -10
echo ""

echo "=== 6. NAT 규칙 (MASQUERADE) ==="
iptables -t nat -L POSTROUTING -n | grep MASQ | wc -l
echo "Total MASQUERADE rules"
echo ""

echo "=== 7. 외부 연결 테스트 ==="
echo -n "eno1 외부 IP: "
timeout 5 curl --interface eno1 -s https://ipinfo.io/ip 2>/dev/null || echo "FAILED"
echo ""

echo "=== 8. DNS 테스트 ==="
echo -n "DNS 응답: "
timeout 3 nslookup google.com 8.8.8.8 2>&1 | grep -q "Address" && echo "OK" || echo "FAILED"
echo ""

echo "=== 9. 게이트웨이 핑 테스트 ==="
gw=$(ip route | grep default | grep eno1 | awk '{print $3}' | head -1)
if [ ! -z "$gw" ]; then
    echo -n "Gateway $gw: "
    ping -c 1 -W 2 $gw >/dev/null 2>&1 && echo "OK" || echo "FAILED"
fi
echo ""

echo "=== 10. 서비스 상태 ==="
systemctl is-active network-monitor
systemctl is-active network-monitor-startup
echo ""

echo "=== 11. 최근 startup 로그 ==="
tail -5 /home/proxy/network-monitor/logs/startup.log 2>/dev/null
echo ""

echo "========== End of Debug Report =========="