#!/bin/bash

# WireGuard 설정 스크립트 (동글과 함께 사용)

echo "=== WireGuard 설정 ==="

# 현재 동글 확인
MAIN_INTERFACE="eno1"
DONGLE_INTERFACE=""

# 활성 동글 찾기
for i in {11..20}; do
    if ip addr show | grep -q "192.168.$i.100"; then
        DONGLE_INTERFACE=$(ip addr show | grep "192.168.$i.100" | awk '{print $NF}')
        echo "활성 동글 발견: $DONGLE_INTERFACE (192.168.$i.100)"
        break
    fi
done

# 키 확인
if [ ! -f /etc/wireguard/server_private.key ]; then
    echo "WireGuard 키가 없습니다. 생성 중..."
    cd /etc/wireguard
    wg genkey | tee server_private.key | wg pubkey > server_public.key
    chmod 600 server_private.key
    
    wg genkey | tee client_private.key | wg pubkey > client_public.key
    chmod 600 client_private.key
fi

SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/client_public.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)

# WireGuard 설정 생성
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
# 서버 설정
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE_KEY

# 기본 라우팅은 메인 인터페이스로
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE

# 동글이 있으면 특정 트래픽만 동글로
EOF

if [ ! -z "$DONGLE_INTERFACE" ]; then
    cat >> /etc/wireguard/wg0.conf << EOF
# 네이버 트래픽은 동글로
PostUp = iptables -t mangle -A PREROUTING -i wg0 -d 223.130.195.0/24 -j MARK --set-mark 0x100
PostUp = ip rule add fwmark 0x100 table 100
PostUp = ip route add default via 192.168.$i.1 table 100
PostDown = iptables -t mangle -D PREROUTING -i wg0 -d 223.130.195.0/24 -j MARK --set-mark 0x100
PostDown = ip rule del fwmark 0x100 table 100
PostDown = ip route del default via 192.168.$i.1 table 100
EOF
fi

cat >> /etc/wireguard/wg0.conf << EOF

[Peer]
# 클라이언트 설정
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
EOF

echo "WireGuard 설정 완료!"
echo ""
echo "=== 클라이언트 설정 ==="
echo "아래 내용을 클라이언트 WireGuard 설정에 사용하세요:"
echo ""
cat > /home/proxy/network-monitor/wireguard_client.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/client_private.key)
Address = 10.8.0.2/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = 112.161.54.7:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

cat /home/proxy/network-monitor/wireguard_client.conf

echo ""
echo "=== 방화벽 설정 ==="
firewall-cmd --add-port=51820/udp --permanent
firewall-cmd --reload

echo ""
echo "=== 사용법 ==="
echo "시작: wg-quick up wg0"
echo "중지: wg-quick down wg0"
echo "상태: wg show"
echo "자동 시작: systemctl enable wg-quick@wg0"