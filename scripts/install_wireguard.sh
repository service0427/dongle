#!/bin/bash

# WireGuard 설치 스크립트

echo "=== WireGuard 설치 ==="

# 1. WireGuard 설치
echo "WireGuard 패키지 설치 중..."
dnf install -y epel-release elrepo-release
dnf install -y kmod-wireguard wireguard-tools

# 2. 키 생성
echo "WireGuard 키 생성 중..."
mkdir -p /etc/wireguard
cd /etc/wireguard

# 서버 키
wg genkey | tee server_private.key | wg pubkey > server_public.key
chmod 600 server_private.key

# 클라이언트 키 (예시용)
wg genkey | tee client_private.key | wg pubkey > client_public.key
chmod 600 client_private.key

echo "서버 Public Key: $(cat server_public.key)"
echo "클라이언트 Public Key: $(cat client_public.key)"

# 3. 기본 설정 파일 생성
SERVER_PRIVATE_KEY=$(cat server_private.key)
CLIENT_PUBLIC_KEY=$(cat client_public.key)

cat > /etc/wireguard/wg0.conf << EOF
[Interface]
# 서버 설정
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE_KEY

# 라우팅 설정
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o enp0s21f0u3u4u4 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o enp0s21f0u3u4u4 -j MASQUERADE

[Peer]
# 클라이언트 설정
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
EOF

echo "WireGuard 설정 완료!"
echo ""
echo "클라이언트 설정 예시:"
echo "------------------------"
cat << EOF
[Interface]
PrivateKey = $(cat client_private.key)
Address = 10.8.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $(cat server_public.key)
Endpoint = 112.161.54.7:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo ""
echo "사용법:"
echo "  시작: wg-quick up wg0"
echo "  중지: wg-quick down wg0"
echo "  상태: wg show"