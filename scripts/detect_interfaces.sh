#!/bin/bash

# 인터페이스 자동 감지 스크립트
# 메인 인터페이스(eno1 등)와 동글 인터페이스를 구분하여 감지

LOG_FILE="/home/proxy/network-monitor/logs/monitor.log"

# 로깅 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 메인 인터페이스 감지 (192.168.x.100이 아닌 인터페이스)
detect_main_interface() {
    local main_iface=""
    
    # 방법 1: 기본 게이트웨이가 있고 192.168 대역이 아닌 인터페이스
    main_iface=$(ip route | grep default | grep -v "192.168" | awk '{print $5}' | head -1)
    
    if [ -z "$main_iface" ]; then
        # 방법 2: 192.168.x.100이 아닌 IP를 가진 인터페이스 찾기
        for iface in $(ls /sys/class/net/ | grep -v lo); do
            local ip=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
            if [[ ! -z "$ip" && ! "$ip" =~ ^192\.168\.[0-9]+\.100$ && ! "$ip" =~ ^127\. ]]; then
                # 사설 IP 대역이 아닌 경우 우선
                if [[ ! "$ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]]; then
                    main_iface="$iface"
                    break
                fi
            fi
        done
    fi
    
    # 방법 3: 물리적 이더넷 인터페이스 패턴 매칭
    if [ -z "$main_iface" ]; then
        for pattern in "eno" "eth" "enp" "ens"; do
            for iface in $(ls /sys/class/net/ | grep "^$pattern"); do
                local ip=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
                if [[ ! -z "$ip" && ! "$ip" =~ ^192\.168\.[0-9]+\.100$ ]]; then
                    main_iface="$iface"
                    break 2
                fi
            done
        done
    fi
    
    echo "$main_iface"
}

# 동글 인터페이스 감지 (192.168.x.100, 11~30번 지원)
detect_dongle_interfaces() {
    local dongles=""
    
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        local ip=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        # 192.168.11.100 ~ 192.168.30.100 범위 확인
        if [[ "$ip" =~ ^192\.168\.([0-9]+)\.100$ ]]; then
            local subnet="${BASH_REMATCH[1]}"
            if [ "$subnet" -ge 11 ] && [ "$subnet" -le 30 ]; then
                if [ -z "$dongles" ]; then
                    dongles="$iface"
                else
                    dongles="$dongles $iface"
                fi
            fi
        fi
    done
    
    echo "$dongles"
}

# IP 할당 대기
wait_for_ip() {
    local iface=$1
    local max_wait=300  # 최대 5분 대기
    local wait_interval=10
    local elapsed=0
    
    log "Waiting for IP assignment on $iface..."
    
    while [ $elapsed -lt $max_wait ]; do
        local ip=$(ip addr show "$iface" 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d'/' -f1)
        if [ ! -z "$ip" ]; then
            log "IP assigned to $iface: $ip"
            return 0
        fi
        
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
        log "Still waiting for IP on $iface... ($elapsed/$max_wait seconds)"
    done
    
    log "ERROR: No IP assigned to $iface after $max_wait seconds"
    return 1
}

# 인터페이스 정보 출력
print_interface_info() {
    local iface=$1
    local ip=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    local mac=$(ip addr show "$iface" 2>/dev/null | grep "link/ether" | awk '{print $2}')
    local state=$(ip addr show "$iface" 2>/dev/null | grep -oP '(?<=state )\w+')
    
    echo "Interface: $iface"
    echo "  State: $state"
    echo "  IP: ${ip:-Not assigned}"
    echo "  MAC: ${mac:-Not available}"
}

# 메인 함수
main() {
    log "Starting interface detection..."
    
    # 메인 인터페이스 감지
    MAIN_INTERFACE=$(detect_main_interface)
    
    if [ -z "$MAIN_INTERFACE" ]; then
        log "ERROR: No main interface detected!"
        exit 1
    fi
    
    log "Main interface detected: $MAIN_INTERFACE"
    
    # IP 할당 확인
    if ! wait_for_ip "$MAIN_INTERFACE"; then
        log "ERROR: Failed to get IP on main interface"
        exit 1
    fi
    
    # 인터페이스 정보 출력
    print_interface_info "$MAIN_INTERFACE"
    
    # 동글 인터페이스 감지
    DONGLE_INTERFACES=$(detect_dongle_interfaces)
    
    if [ ! -z "$DONGLE_INTERFACES" ]; then
        log "Dongle interfaces detected: $DONGLE_INTERFACES"
        for dongle in $DONGLE_INTERFACES; do
            print_interface_info "$dongle"
        done
    else
        log "No dongle interfaces detected"
    fi
    
    # 결과를 환경 변수로 내보내기
    echo "export MAIN_INTERFACE=$MAIN_INTERFACE"
    echo "export DONGLE_INTERFACES=\"$DONGLE_INTERFACES\""
}

# 스크립트가 직접 실행될 때만 main 함수 호출
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi