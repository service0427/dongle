#!/bin/bash

# TCP 설정을 모바일 네트워크와 유사하게 최적화
# 쿠팡 등의 사이트에서 프록시 탐지를 회피하기 위한 설정

echo "모바일 네트워크 환경 모방을 위한 TCP 최적화 시작..."

# 1. TCP 타임스탬프 비활성화 (일부 모바일 네트워크에서 사용 안함)
sysctl -w net.ipv4.tcp_timestamps=0

# 2. TCP 재사용 설정 (모바일처럼 동작)
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_fin_timeout=30

# 3. TCP 연결 제한 설정 (동시 연결 수 제한)
sysctl -w net.ipv4.tcp_max_syn_backlog=256
sysctl -w net.core.somaxconn=256

# 4. TCP Keep-Alive 설정 (모바일 네트워크 특성 모방)
sysctl -w net.ipv4.tcp_keepalive_time=600
sysctl -w net.ipv4.tcp_keepalive_intvl=60
sysctl -w net.ipv4.tcp_keepalive_probes=3

# 5. TCP Window Scaling 조정
sysctl -w net.ipv4.tcp_window_scaling=1
sysctl -w net.core.rmem_default=87380
sysctl -w net.core.wmem_default=65536

# 6. TCP 혼잡 제어 알고리즘 변경 (모바일 네트워크에 적합한 BBR)
modprobe tcp_bbr 2>/dev/null
sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || \
sysctl -w net.ipv4.tcp_congestion_control=cubic

# 7. SYN 쿠키 활성화 (DDoS 방어 및 연결 패턴 정규화)
sysctl -w net.ipv4.tcp_syncookies=1

# 8. 포트 범위 조정 (모바일 디바이스처럼)
sysctl -w net.ipv4.ip_local_port_range="32768 60999"

# 9. TCP 재전송 설정
sysctl -w net.ipv4.tcp_retries2=10
sysctl -w net.ipv4.tcp_syn_retries=3

# 10. TCP MTU 프로빙 (모바일 네트워크 MTU 감지)
sysctl -w net.ipv4.tcp_mtu_probing=1
sysctl -w net.ipv4.tcp_base_mss=1024

# 영구 적용을 위한 설정 파일 생성
cat > /etc/sysctl.d/99-mobile-tcp-optimization.conf <<EOF
# TCP 모바일 네트워크 최적화 설정
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_syn_backlog = 256
net.core.somaxconn = 256
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_window_scaling = 1
net.core.rmem_default = 87380
net.core.wmem_default = 65536
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_local_port_range = 32768 60999
net.ipv4.tcp_retries2 = 10
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024
EOF

echo "TCP 최적화 완료!"
echo ""
echo "적용된 주요 변경사항:"
echo "- TCP 타임스탬프 비활성화 (프록시 탐지 회피)"
echo "- 연결 재사용 및 타임아웃 최적화"
echo "- 동시 연결 수 제한 (모바일 디바이스 모방)"
echo "- BBR 혼잡 제어 알고리즘 적용"
echo "- MTU 프로빙 활성화"
echo ""
echo "SOCKS5 서비스 재시작 권장:"
echo "/home/proxy/scripts/socks5/manage_socks5.sh restart all"