#!/bin/bash

# 화웨이 동글 상태 진단 스크립트
# 각 동글의 상태를 체크하고 문제를 진단

LOG_FILE="/home/proxy/network-monitor/logs/dongle_status.log"
USERNAME="admin"
PASSWORD="KdjLch!@7024"

# 로깅 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# API 호출 함수
call_api() {
    local ip=$1
    local endpoint=$2
    local auth=$(echo -n "$USERNAME:$PASSWORD" | base64)
    
    curl -s -H "Authorization: Basic $auth" \
         -H "Content-Type: text/xml" \
         "http://$ip$endpoint" 2>/dev/null
}

# 동글 상태 체크
check_dongle() {
    local port=$1
    local ip="192.168.$port.1"
    
    echo "=== Checking Dongle $port ($ip) ==="
    
    # 1. 기본 연결 테스트
    if ! ping -c 1 -W 1 $ip >/dev/null 2>&1; then
        echo "  Status: NOT REACHABLE"
        return
    fi
    
    # 2. 웹 인터페이스 접근 테스트
    if ! curl -s -m 2 http://$ip >/dev/null 2>&1; then
        echo "  Status: Web UI NOT ACCESSIBLE"
        return
    fi
    
    echo "  Status: CONNECTED"
    
    # 3. 디바이스 정보
    echo "  Device Info:"
    device_info=$(call_api $ip "/api/device/information")
    if [ ! -z "$device_info" ]; then
        device_name=$(echo "$device_info" | grep -o '<DeviceName>[^<]*</DeviceName>' | sed 's/<[^>]*>//g')
        imei=$(echo "$device_info" | grep -o '<Imei>[^<]*</Imei>' | sed 's/<[^>]*>//g')
        echo "    Name: ${device_name:-Unknown}"
        echo "    IMEI: ${imei:-Unknown}"
    fi
    
    # 4. 연결 상태
    echo "  Connection Status:"
    conn_status=$(call_api $ip "/api/monitoring/status")
    if [ ! -z "$conn_status" ]; then
        conn_state=$(echo "$conn_status" | grep -o '<ConnectionStatus>[^<]*</ConnectionStatus>' | sed 's/<[^>]*>//g')
        network_type=$(echo "$conn_status" | grep -o '<CurrentNetworkType>[^<]*</CurrentType>' | sed 's/<[^>]*>//g')
        signal=$(echo "$conn_status" | grep -o '<SignalIcon>[^<]*</SignalIcon>' | sed 's/<[^>]*>//g')
        
        # ConnectionStatus 값 해석
        case "$conn_state" in
            "901") echo "    State: CONNECTED" ;;
            "900") echo "    State: CONNECTING" ;;
            "902") echo "    State: DISCONNECTED" ;;
            "903") echo "    State: DISCONNECTING" ;;
            *) echo "    State: $conn_state" ;;
        esac
        
        echo "    Network: ${network_type:-Unknown}"
        echo "    Signal: ${signal:-Unknown}/5"
    fi
    
    # 5. SIM 카드 상태
    echo "  SIM Status:"
    sim_status=$(call_api $ip "/api/monitoring/check-notifications")
    if [ ! -z "$sim_status" ]; then
        sim_state=$(echo "$sim_status" | grep -o '<SIMState>[^<]*</SIMState>' | sed 's/<[^>]*>//g')
        case "$sim_state" in
            "0") echo "    SIM: NORMAL" ;;
            "1") echo "    SIM: PIN REQUIRED" ;;
            "2") echo "    SIM: PUK REQUIRED" ;;
            "255"|"") echo "    SIM: NO SIM" ;;
            *) echo "    SIM: Unknown ($sim_state)" ;;
        esac
    fi
    
    # 6. 인터넷 연결 테스트
    echo "  Internet Test:"
    iface=$(ip addr | grep "192.168.$port.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
    if [ ! -z "$iface" ]; then
        if timeout 3 curl --interface $iface -s https://ipinfo.io/ip >/dev/null 2>&1; then
            external_ip=$(timeout 3 curl --interface $iface -s https://ipinfo.io/ip 2>/dev/null)
            echo "    External IP: $external_ip"
        else
            echo "    External IP: NO INTERNET"
        fi
    else
        echo "    Interface: NOT FOUND"
    fi
    
    echo ""
}

# 모든 동글 상태 요약
print_summary() {
    echo "=== SUMMARY ==="
    
    total=0
    working=0
    
    # 연결된 동글 수 계산
    for port in {11..30}; do
        if ip addr show 2>/dev/null | grep -q "192.168.$port.100"; then
            total=$((total + 1))
            iface=$(ip addr | grep "192.168.$port.100" -B2 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ')
            if [ ! -z "$iface" ]; then
                if timeout 2 curl --interface $iface -s https://ipinfo.io/ip >/dev/null 2>&1; then
                    working=$((working + 1))
                fi
            fi
        fi
    done
    
    echo "Total dongles: $total"
    echo "Working (Internet): $working"
    echo "Not working: $((total - working))"
}

# 메인 실행
main() {
    log "Starting dongle status check..."
    
    # 각 동글 체크 (11~30번 지원, 실제 연결된 것만)
    for port in {11..30}; do
        # 연결된 동글만 체크
        if ip addr show 2>/dev/null | grep -q "192.168.$port.100"; then
            check_dongle $port
        fi
    done
    
    # 요약 출력
    print_summary
    
    log "Dongle status check completed"
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi