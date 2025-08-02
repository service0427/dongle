#!/bin/bash

# SOCKS5 프록시 재시작 스크립트 (중복 방지)
# 락 파일을 사용하여 동시 실행 방지

LOCK_FILE="/var/run/socks5_restart.lock"
LOG_FILE="/home/proxy/network-monitor/logs/socks5_restart.log"
PENDING_FILE="/var/run/socks5_restart.pending"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 락 획득 시도
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    # 락을 획득할 수 없으면 pending 표시만 하고 종료
    touch "$PENDING_FILE"
    log "재시작 이미 진행 중 - pending 표시"
    exit 0
fi

# 락 획득 성공
log "SOCKS5 재시작 시작 (락 획득)"

# 잠시 대기하여 추가 요청들이 pending에 쌓이도록
sleep 3

# Pending 확인
if [ -f "$PENDING_FILE" ]; then
    log "추가 동글 변경 감지됨 - 일괄 처리"
    rm -f "$PENDING_FILE"
fi

# 실제 재시작
systemctl restart dongle-socks5

if [ $? -eq 0 ]; then
    log "SOCKS5 프록시 재시작 성공"
    
    # 잠시 대기 후 활성 포트 확인
    sleep 2
    active_ports=$(ss -tlnp | grep -E "1001[0-9]" | awk '{print $4}' | cut -d: -f2 | sort)
    
    if [ ! -z "$active_ports" ]; then
        log "활성 포트: $active_ports"
        
        # 동글 개수 확인
        dongle_count=$(echo "$active_ports" | wc -l)
        log "활성 동글 수: $dongle_count"
    else
        log "경고: 활성 포트 없음"
    fi
else
    log "오류: SOCKS5 프록시 재시작 실패"
fi

# 락 해제 (자동으로 해제되지만 명시적으로)
flock -u 200