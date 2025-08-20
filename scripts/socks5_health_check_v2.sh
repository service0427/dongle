#!/bin/bash

# SOCKS5 헬스체크 스크립트 v2
# 정확한 테스트와 필요한 경우에만 재시작

LOG_FILE="/home/proxy/logs/socks5_health.log"

# 로그 함수
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
}

# SOCKS5 테스트
test_socks5() {
    local port=$1
    
    # timeout 명령으로 포트 체크
    timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$port" 2>/dev/null
    return $?
}

# 메인
main() {
    log_info "Starting SOCKS5 health check"
    
    PROBLEM_COUNT=0
    
    # proxy_state.json에서 활성 동글 확인
    if [ -f /home/proxy/proxy_state.json ]; then
        SUBNETS=$(python3 -c "
import json
with open('/home/proxy/proxy_state.json') as f:
    data = json.load(f)
    print(' '.join(data.keys()))
" 2>/dev/null)
    else
        # 기본값 사용
        SUBNETS="11 12 13 14 15 16 17 18"
    fi
    
    for subnet in $SUBNETS; do
        port=$((10000 + subnet))
        
        # 서비스 상태 확인
        if ! systemctl is-active --quiet dongle-socks5-$subnet 2>/dev/null; then
            # 서비스가 없으면 건너뛰기
            continue
        fi
        
        # 포트 테스트 (3번 시도)
        success=false
        for i in 1 2 3; do
            if test_socks5 $port; then
                success=true
                break
            fi
            sleep 1
        done
        
        if [ "$success" = false ]; then
            log_error "Port $port not responding, restarting dongle-socks5-$subnet"
            systemctl restart dongle-socks5-$subnet
            PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
            sleep 2
        else
            # 메모리 체크 (선택적)
            pid=$(pgrep -f "socks5_single.py $subnet" | head -1)
            if [ -n "$pid" ]; then
                memory_kb=$(ps -o rss= -p $pid 2>/dev/null | tr -d ' ')
                if [ -n "$memory_kb" ]; then
                    memory_mb=$((memory_kb / 1024))
                    if [ $memory_mb -gt 500 ]; then
                        log_error "High memory usage for subnet $subnet: ${memory_mb}MB, restarting"
                        systemctl restart dongle-socks5-$subnet
                        PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
                        sleep 2
                    fi
                fi
            fi
        fi
    done
    
    if [ $PROBLEM_COUNT -gt 0 ]; then
        log_info "Health check completed - $PROBLEM_COUNT services restarted"
    else
        log_info "Health check completed - All services healthy"
    fi
}

# 실행
main