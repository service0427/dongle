#!/bin/bash

# TIME_WAIT 최적화 스크립트
# SOCKS5 프록시 환경에 맞춰 TIME_WAIT 관련 설정 최적화

echo "TIME_WAIT 최적화 시작..."
echo ""
echo "현재 상태:"
echo "TIME_WAIT 연결: $(cat /proc/net/nf_conntrack | grep TIME_WAIT | wc -l)개"
echo "현재 타임아웃: $(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait)초"
echo ""

# 1. TIME_WAIT 타임아웃 단축 (120초 -> 30초)
echo "1. TIME_WAIT 타임아웃 단축 (120초 -> 30초)"
echo 30 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait
sysctl -w net.ipv4.tcp_fin_timeout=30

# 2. TIME_WAIT 소켓 재사용 활성화
echo "2. TIME_WAIT 소켓 재사용 활성화"
sysctl -w net.ipv4.tcp_tw_reuse=1

# 3. FIN_WAIT 타임아웃 단축
echo "3. FIN_WAIT 타임아웃 단축"
echo 30 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_fin_wait

# 4. CLOSE_WAIT 타임아웃 단축
echo "4. CLOSE_WAIT 타임아웃 단축"
echo 30 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_close_wait

# 5. 최대 TIME_WAIT 버킷 크기 제한
echo "5. TIME_WAIT 버킷 크기 제한"
sysctl -w net.ipv4.tcp_max_tw_buckets=50000

# 6. TCP keepalive 조정 (빠른 연결 정리)
echo "6. TCP keepalive 조정"
sysctl -w net.ipv4.tcp_keepalive_time=300
sysctl -w net.ipv4.tcp_keepalive_intvl=30
sysctl -w net.ipv4.tcp_keepalive_probes=3

# 영구 적용을 위한 설정 파일 생성
cat > /etc/sysctl.d/99-time-wait-optimization.conf <<EOF
# TIME_WAIT 최적화 설정
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 50000
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
EOF

# conntrack 설정 영구 적용
cat > /etc/sysctl.d/99-conntrack-timeouts.conf <<EOF
# Conntrack 타임아웃 설정
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 30
EOF

echo ""
echo "최적화 완료!"
echo ""
echo "변경된 설정:"
echo "- TIME_WAIT 타임아웃: 30초"
echo "- TIME_WAIT 재사용: 활성화"
echo "- 최대 TIME_WAIT: 50,000개"
echo ""
echo "10초 후 현재 상태:"
sleep 10
echo "TIME_WAIT 연결: $(cat /proc/net/nf_conntrack | grep TIME_WAIT | wc -l)개"
echo ""
echo "주의: 설정이 너무 공격적이면 연결 문제가 발생할 수 있습니다."
echo "문제 발생시 기본값으로 복구:"
echo "  echo 120 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait"
echo "  sysctl -w net.ipv4.tcp_fin_timeout=60"