#!/bin/bash

# 시스템 메트릭 수집 스크립트
# 매분 실행되어 JSON 형태로 로그 저장
# 나중에 문제 발생 시간대 분석용

# PID 파일로 중복 실행 방지
PIDFILE="/var/run/collect_system_metrics.pid"

# 이미 실행 중인지 확인
if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        # 프로세스가 실행 중이면 종료
        exit 0
    else
        # PID 파일은 있지만 프로세스가 없으면 파일 삭제
        rm -f "$PIDFILE"
    fi
fi

# 현재 PID 저장
echo $$ > "$PIDFILE"

# 스크립트 종료시 PID 파일 삭제
trap "rm -f $PIDFILE" EXIT

# 로그 디렉토리 설정
LOG_BASE="/home/proxy/logs/metrics"
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H-%M)
TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)
LOG_DIR="$LOG_BASE/$DATE"

# 디렉토리 생성
mkdir -p "$LOG_DIR"

# JSON 시작
cat > "$LOG_DIR/metrics_$TIME.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "system": {
EOF

# 1. 시스템 메모리 정보
MEM_TOTAL=$(free -b | grep Mem | awk '{print $2}')
MEM_USED=$(free -b | grep Mem | awk '{print $3}')
MEM_AVAILABLE=$(free -b | grep Mem | awk '{print $7}')
MEM_PERCENT=$(echo "scale=2; $MEM_USED * 100 / $MEM_TOTAL" | bc)

cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
    "memory": {
      "total": $MEM_TOTAL,
      "used": $MEM_USED,
      "available": $MEM_AVAILABLE,
      "percent": $MEM_PERCENT
    },
EOF

# 2. CPU 정보
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
LOAD_1=$(echo $LOAD_AVG | cut -d, -f1 | tr -d ' ')
LOAD_5=$(echo $LOAD_AVG | cut -d, -f2 | tr -d ' ')
LOAD_15=$(echo $LOAD_AVG | cut -d, -f3 | tr -d ' ')

cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
    "cpu": {
      "usage": $CPU_USAGE,
      "load_1m": $LOAD_1,
      "load_5m": $LOAD_5,
      "load_15m": $LOAD_15
    }
  },
EOF

# 3. Conntrack 정보
if [ -f /proc/sys/net/netfilter/nf_conntrack_count ]; then
    CONNTRACK_COUNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count)
    CONNTRACK_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
    TIME_WAIT=$(cat /proc/net/nf_conntrack 2>/dev/null | grep TIME_WAIT | wc -l)
    ESTABLISHED=$(cat /proc/net/nf_conntrack 2>/dev/null | grep ESTABLISHED | wc -l)
    SYN_SENT=$(cat /proc/net/nf_conntrack 2>/dev/null | grep SYN_SENT | wc -l)
    FIN_WAIT=$(cat /proc/net/nf_conntrack 2>/dev/null | grep FIN_WAIT | wc -l)
    CLOSE_WAIT=$(cat /proc/net/nf_conntrack 2>/dev/null | grep CLOSE_WAIT | wc -l)
else
    CONNTRACK_COUNT=0
    CONNTRACK_MAX=0
    TIME_WAIT=0
    ESTABLISHED=0
    SYN_SENT=0
    FIN_WAIT=0
    CLOSE_WAIT=0
fi

cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
  "conntrack": {
    "count": $CONNTRACK_COUNT,
    "max": $CONNTRACK_MAX,
    "time_wait": $TIME_WAIT,
    "established": $ESTABLISHED,
    "syn_sent": $SYN_SENT,
    "fin_wait": $FIN_WAIT,
    "close_wait": $CLOSE_WAIT
  },
EOF

# 4. Ephemeral 포트 사용률
PORT_RANGE_START=$(cat /proc/sys/net/ipv4/ip_local_port_range | awk '{print $1}')
PORT_RANGE_END=$(cat /proc/sys/net/ipv4/ip_local_port_range | awk '{print $2}')
PORT_RANGE_SIZE=$((PORT_RANGE_END - PORT_RANGE_START))
USED_PORTS=$(ss -an | grep -E ":[0-9]+\s" | awk '{print $4}' | cut -d: -f2 | awk -v start=$PORT_RANGE_START -v end=$PORT_RANGE_END '$1 >= start && $1 <= end' | sort -u | wc -l)
PORT_USAGE_PERCENT=$(echo "scale=2; $USED_PORTS * 100 / $PORT_RANGE_SIZE" | bc)

cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
  "ephemeral_ports": {
    "range_start": $PORT_RANGE_START,
    "range_end": $PORT_RANGE_END,
    "total": $PORT_RANGE_SIZE,
    "used": $USED_PORTS,
    "percent": $PORT_USAGE_PERCENT
  },
EOF

# 5. SOCKS5 프로세스 정보
echo '  "socks5_processes": [' >> "$LOG_DIR/metrics_$TIME.json"

FIRST=true
for subnet in {11..23}; do
    PID=$(pgrep -f "socks5_single.py $subnet" | head -1)
    if [ -n "$PID" ]; then
        # 메모리 정보
        RSS=$(ps -o rss= -p $PID 2>/dev/null | tr -d ' ' || echo 0)
        RSS_MB=$((RSS / 1024))
        
        # 스레드 수
        THREADS=$(ps -o nlwp= -p $PID 2>/dev/null | tr -d ' ' || echo 0)
        
        # 파일 디스크립터
        FDS=$(ls /proc/$PID/fd 2>/dev/null | wc -l || echo 0)
        
        # 포트 연결 수
        PORT=$((10000 + subnet))
        CONNECTIONS=$(ss -tn | grep ":$PORT" | wc -l)
        
        if [ "$FIRST" = false ]; then
            echo "," >> "$LOG_DIR/metrics_$TIME.json"
        fi
        FIRST=false
        
        cat >> "$LOG_DIR/metrics_$TIME.json" <<PROCEOF
    {
      "subnet": $subnet,
      "pid": $PID,
      "memory_mb": $RSS_MB,
      "threads": $THREADS,
      "fds": $FDS,
      "connections": $CONNECTIONS
    }
PROCEOF
    fi
done

echo '' >> "$LOG_DIR/metrics_$TIME.json"
cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
  ],
EOF

# 6. 네트워크 인터페이스 에러
echo '  "network_errors": {' >> "$LOG_DIR/metrics_$TIME.json"

FIRST=true
for i in {11..23}; do
    IFACE=$(ip addr | grep "192.168.$i.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ' 2>/dev/null)
    if [ -n "$IFACE" ]; then
        # 네트워크 인터페이스 통계 가져오기
        RX_ERR=0
        RX_DROP=0
        TX_ERR=0
        TX_DROP=0
        
        # ip -s link show 결과 파싱
        STATS=$(ip -s link show $IFACE 2>/dev/null)
        if [ -n "$STATS" ]; then
            RX_LINE=$(echo "$STATS" | grep -A1 "RX:" | tail -1)
            TX_LINE=$(echo "$STATS" | grep -A1 "TX:" | tail -1)
            
            RX_ERR=$(echo "$RX_LINE" | awk '{print $3}' | grep -E '^[0-9]+$' || echo 0)
            RX_DROP=$(echo "$RX_LINE" | awk '{print $4}' | grep -E '^[0-9]+$' || echo 0)
            TX_ERR=$(echo "$TX_LINE" | awk '{print $3}' | grep -E '^[0-9]+$' || echo 0)
            TX_DROP=$(echo "$TX_LINE" | awk '{print $4}' | grep -E '^[0-9]+$' || echo 0)
        fi
        
        # 숫자가 아니면 0으로 설정
        RX_ERR=${RX_ERR:-0}
        RX_DROP=${RX_DROP:-0}
        TX_ERR=${TX_ERR:-0}
        TX_DROP=${TX_DROP:-0}
        
        if [ "$RX_ERR" != "0" ] || [ "$RX_DROP" != "0" ] || [ "$TX_ERR" != "0" ] || [ "$TX_DROP" != "0" ] || [ "$FIRST" = true ]; then
            
            if [ "$FIRST" = false ]; then
                echo "," >> "$LOG_DIR/metrics_$TIME.json"
            fi
            FIRST=false
            
            cat >> "$LOG_DIR/metrics_$TIME.json" <<NETEOF
    "$i": {
      "interface": "$IFACE",
      "rx_errors": ${RX_ERR:-0},
      "rx_drops": ${RX_DROP:-0},
      "tx_errors": ${TX_ERR:-0},
      "tx_drops": ${TX_DROP:-0}
    }
NETEOF
        fi
    fi
done

echo '' >> "$LOG_DIR/metrics_$TIME.json"
cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
  },
EOF

# 7. 파일 디스크립터 전체
SYSTEM_FDS=$(cat /proc/sys/fs/file-nr | awk '{print $1}')
MAX_FDS=$(cat /proc/sys/fs/file-nr | awk '{print $3}')

cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
  "file_descriptors": {
    "system_used": $SYSTEM_FDS,
    "system_max": $MAX_FDS
  },
EOF

# 8. TCP 소켓 상태
TCP_LISTEN=$(ss -tn state listening | wc -l)
TCP_ESTAB=$(ss -tn state established | wc -l)
TCP_TIME_WAIT=$(ss -tn state time-wait | wc -l)
TCP_CLOSE_WAIT=$(ss -tn state close-wait | wc -l)

cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
  "tcp_sockets": {
    "listen": $TCP_LISTEN,
    "established": $TCP_ESTAB,
    "time_wait": $TCP_TIME_WAIT,
    "close_wait": $TCP_CLOSE_WAIT
  },
EOF

# 9. TCP/TLS 관련 설정 및 통계
# TCP 설정값들
TCP_TIMESTAMPS=$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null || echo 0)
TCP_CONGESTION=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
TCP_TW_REUSE=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo 0)
TCP_FIN_TIMEOUT=$(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null || echo 0)

# TCP 재전송 통계 (netstat -s에서 추출)
TCP_RETRANS=$(netstat -s | grep -i "segments retransmited" | awk '{print $1}' | head -1 || echo 0)
TCP_FAST_RETRANS=$(netstat -s | grep -i "fast retransmits" | awk '{print $1}' | head -1 || echo 0)

# HTTPS(443) 연결 수 통계
HTTPS_ESTABLISHED=$(ss -tn state established '( dport = :443 or sport = :443 )' | wc -l)
HTTPS_TIME_WAIT=$(ss -tn state time-wait '( dport = :443 or sport = :443 )' | wc -l)

# 동글별 HTTPS 연결 수
echo '  "tcp_tls_metrics": {' >> "$LOG_DIR/metrics_$TIME.json"
echo '    "settings": {' >> "$LOG_DIR/metrics_$TIME.json"
cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
      "timestamps": $TCP_TIMESTAMPS,
      "congestion_control": "$TCP_CONGESTION",
      "tw_reuse": $TCP_TW_REUSE,
      "fin_timeout": $TCP_FIN_TIMEOUT
    },
    "statistics": {
      "retransmissions": $TCP_RETRANS,
      "fast_retransmissions": $TCP_FAST_RETRANS,
      "https_established": $HTTPS_ESTABLISHED,
      "https_time_wait": $HTTPS_TIME_WAIT
    },
    "dongle_https": {
EOF

FIRST=true
for subnet in {11..23}; do
    IFACE=$(ip addr | grep "192.168.$subnet.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ' 2>/dev/null)
    if [ -n "$IFACE" ]; then
        # 해당 인터페이스의 HTTPS 연결 수
        HTTPS_COUNT=$(ss -tn state established "( dport = :443 or sport = :443 )" | grep "192.168.$subnet" | wc -l)
        
        if [ "$FIRST" = false ]; then
            echo "," >> "$LOG_DIR/metrics_$TIME.json"
        fi
        FIRST=false
        
        echo -n "      \"$subnet\": $HTTPS_COUNT" >> "$LOG_DIR/metrics_$TIME.json"
    fi
done

echo '' >> "$LOG_DIR/metrics_$TIME.json"
cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
    }
  },
EOF

# 10. 네트워크 버퍼 및 패킷 드롭 정보
# 메인 인터페이스 통계
MAIN_IFACE="eno1"
if [ -n "$MAIN_IFACE" ]; then
    # netstat -i 에서 패킷 드롭 정보 가져오기
    NETSTAT_LINE=$(netstat -i | grep "^$MAIN_IFACE" | head -1)
    if [ -n "$NETSTAT_LINE" ]; then
        RX_DRP=$(echo "$NETSTAT_LINE" | awk '{print $5}')
        RX_OVR=$(echo "$NETSTAT_LINE" | awk '{print $6}')
        TX_DRP=$(echo "$NETSTAT_LINE" | awk '{print $9}')
        TX_OVR=$(echo "$NETSTAT_LINE" | awk '{print $10}')
    else
        RX_DRP=0
        RX_OVR=0
        TX_DRP=0
        TX_OVR=0
    fi
    
    # Ring buffer 크기 (ethtool -g)
    RING_INFO=$(ethtool -g $MAIN_IFACE 2>/dev/null | grep "^RX:\|^TX:" | head -2)
    RING_RX=$(echo "$RING_INFO" | grep "^RX:" | awk '{print $2}')
    RING_TX=$(echo "$RING_INFO" | grep "^TX:" | awk '{print $2}')
    RING_RX=${RING_RX:-0}
    RING_TX=${RING_TX:-0}
else
    RX_DRP=0
    RX_OVR=0
    TX_DRP=0
    TX_OVR=0
    RING_RX=0
    RING_TX=0
fi

# 네트워크 백로그 설정
NETDEV_BACKLOG=$(sysctl -n net.core.netdev_max_backlog 2>/dev/null || echo 0)
NETDEV_BUDGET=$(sysctl -n net.core.netdev_budget 2>/dev/null || echo 0)

# softnet_stat (CPU별 패킷 처리 통계)
# 첫 번째 값: 처리된 패킷 수, 두 번째: 드롭된 패킷 수
SOFTNET_CPU0=$(cat /proc/net/softnet_stat | head -1)
SOFTNET_PROCESSED=$(echo $SOFTNET_CPU0 | awk '{print strtonum("0x"$1)}')
SOFTNET_DROPPED=$(echo $SOFTNET_CPU0 | awk '{print strtonum("0x"$2)}')
SOFTNET_SQUEEZED=$(echo $SOFTNET_CPU0 | awk '{print strtonum("0x"$3)}')

# 동글 인터페이스들의 총 드롭 수
DONGLE_DROPS=0
for i in {11..23}; do
    IFACE=$(ip addr | grep "192.168.$i.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ' 2>/dev/null)
    if [ -n "$IFACE" ]; then
        DROPS=$(netstat -i | grep "^$IFACE" | awk '{print $5}' | head -1)
        DONGLE_DROPS=$((DONGLE_DROPS + ${DROPS:-0}))
    fi
done

cat >> "$LOG_DIR/metrics_$TIME.json" <<EOF
  "network_buffers": {
    "main_interface": {
      "name": "$MAIN_IFACE",
      "rx_dropped": $RX_DRP,
      "rx_overruns": $RX_OVR,
      "tx_dropped": $TX_DRP,
      "tx_overruns": $TX_OVR,
      "ring_rx": $RING_RX,
      "ring_tx": $RING_TX
    },
    "dongle_total_drops": $DONGLE_DROPS,
    "netdev_max_backlog": $NETDEV_BACKLOG,
    "netdev_budget": $NETDEV_BUDGET,
    "softnet_stat": {
      "processed": $SOFTNET_PROCESSED,
      "dropped": $SOFTNET_DROPPED,
      "squeezed": $SOFTNET_SQUEEZED
    }
  }
}
EOF

# 오래된 로그 정리 (7일 이상)
find "$LOG_BASE" -type f -name "*.json" -mtime +7 -delete 2>/dev/null
find "$LOG_BASE" -type d -empty -delete 2>/dev/null

# 디스크 사용량 체크 (5GB 초과시 오래된 것부터 삭제)
LOG_SIZE=$(du -sb "$LOG_BASE" 2>/dev/null | cut -f1)
MAX_SIZE=$((5 * 1024 * 1024 * 1024))  # 5GB

if [ "$LOG_SIZE" -gt "$MAX_SIZE" ]; then
    # 가장 오래된 날짜 디렉토리 삭제
    OLDEST_DIR=$(ls -dt "$LOG_BASE"/*/ 2>/dev/null | tail -1)
    if [ -n "$OLDEST_DIR" ]; then
        rm -rf "$OLDEST_DIR"
    fi
fi