#!/bin/bash

# TLS 감지 문제 단계별 해결 스크립트
# 쿠팡 등의 사이트에서 프록시 탐지를 회피하기 위한 단계별 접근
# 사용법: ./tls_detection_fix.sh [level]
# level: 1-5 (미지정시 자동 진행)

LOG_FILE="/home/proxy/logs/tls_detection_fix.log"
TEST_URL="https://www.coupang.com"
PROXY_PORT="10011"  # 테스트용 첫 번째 프록시 포트

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 로깅 함수
log_message() {
    echo -e "$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 쿠팡 접속 테스트 함수
test_coupang_access() {
    local port=${1:-$PROXY_PORT}
    log_message "${BLUE}쿠팡 접속 테스트 시작 (프록시 포트: $port)${NC}"
    
    # curl을 통한 접속 테스트
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        --socks5 localhost:$port \
        --connect-timeout 10 \
        "$TEST_URL" 2>/dev/null)
    
    if [ "$response" = "200" ] || [ "$response" = "301" ] || [ "$response" = "302" ]; then
        log_message "${GREEN}✓ 쿠팡 접속 성공 (HTTP $response)${NC}"
        return 0
    else
        log_message "${RED}✗ 쿠팡 접속 실패 (HTTP $response)${NC}"
        return 1
    fi
}

# 현재 TCP 설정 백업
backup_tcp_settings() {
    log_message "${BLUE}현재 TCP 설정 백업${NC}"
    cat > /tmp/tcp_settings_backup.conf <<EOF
# TCP 설정 백업 - $(date)
net.ipv4.tcp_timestamps = $(sysctl -n net.ipv4.tcp_timestamps)
net.ipv4.tcp_tw_reuse = $(sysctl -n net.ipv4.tcp_tw_reuse)
net.ipv4.tcp_fin_timeout = $(sysctl -n net.ipv4.tcp_fin_timeout)
net.ipv4.tcp_congestion_control = $(sysctl -n net.ipv4.tcp_congestion_control)
net.ipv4.tcp_max_syn_backlog = $(sysctl -n net.ipv4.tcp_max_syn_backlog)
net.core.somaxconn = $(sysctl -n net.core.somaxconn)
EOF
    log_message "백업 완료: /tmp/tcp_settings_backup.conf"
}

# Level 1: TCP 타임스탬프 비활성화
level1_soft_fix() {
    log_message "\n${YELLOW}=== Level 1: TCP 타임스탬프 비활성화 ===${NC}"
    
    # 현재 상태 확인
    current_timestamp=$(sysctl -n net.ipv4.tcp_timestamps)
    log_message "현재 TCP 타임스탬프: $current_timestamp"
    
    if [ "$current_timestamp" = "1" ]; then
        log_message "TCP 타임스탬프 비활성화 중..."
        sysctl -w net.ipv4.tcp_timestamps=0
        
        # 변경 확인
        new_timestamp=$(sysctl -n net.ipv4.tcp_timestamps)
        log_message "변경 후 TCP 타임스탬프: $new_timestamp"
    else
        log_message "TCP 타임스탬프가 이미 비활성화되어 있습니다."
    fi
    
    # 10초 대기
    log_message "10초 대기 중..."
    sleep 10
    
    # 테스트
    if test_coupang_access; then
        log_message "${GREEN}Level 1 해결 성공!${NC}"
        return 0
    else
        log_message "${YELLOW}Level 1로 해결되지 않음. 다음 단계 필요.${NC}"
        return 1
    fi
}

# Level 2: TCP 모바일 최적화
level2_tcp_optimize() {
    log_message "\n${YELLOW}=== Level 2: TCP 모바일 최적화 ===${NC}"
    
    # optimize_tcp_for_mobile.sh 실행
    if [ -f "/home/proxy/scripts/optimize_tcp_for_mobile.sh" ]; then
        log_message "TCP 모바일 최적화 스크립트 실행..."
        bash /home/proxy/scripts/optimize_tcp_for_mobile.sh > /dev/null 2>&1
        
        log_message "주요 변경사항:"
        log_message "  - TCP 타임스탬프: $(sysctl -n net.ipv4.tcp_timestamps)"
        log_message "  - 혼잡 제어: $(sysctl -n net.ipv4.tcp_congestion_control)"
        log_message "  - TIME_WAIT 재사용: $(sysctl -n net.ipv4.tcp_tw_reuse)"
        log_message "  - FIN 타임아웃: $(sysctl -n net.ipv4.tcp_fin_timeout)"
    else
        log_message "${RED}optimize_tcp_for_mobile.sh 파일을 찾을 수 없습니다.${NC}"
        return 1
    fi
    
    # 10초 대기
    log_message "10초 대기 중..."
    sleep 10
    
    # 테스트
    if test_coupang_access; then
        log_message "${GREEN}Level 2 해결 성공!${NC}"
        return 0
    else
        log_message "${YELLOW}Level 2로 해결되지 않음. 다음 단계 필요.${NC}"
        return 1
    fi
}

# Level 3: 연결 상태 정리
level3_connection_cleanup() {
    log_message "\n${YELLOW}=== Level 3: 연결 상태 정리 ===${NC}"
    
    # TIME_WAIT 소켓 수 확인
    time_wait_count=$(ss -tn state time-wait | wc -l)
    log_message "현재 TIME_WAIT 소켓: $time_wait_count"
    
    # Conntrack 정리
    log_message "Conntrack 테이블 정리 중..."
    conntrack -F 2>/dev/null || log_message "conntrack 명령어 없음 (무시)"
    
    # TIME_WAIT 최적화
    if [ -f "/home/proxy/scripts/optimize_time_wait.sh" ]; then
        log_message "TIME_WAIT 최적화 실행..."
        bash /home/proxy/scripts/optimize_time_wait.sh > /dev/null 2>&1
    fi
    
    # SOCKS5 서비스 재시작
    log_message "SOCKS5 서비스 재시작..."
    /home/proxy/scripts/socks5/manage_socks5.sh restart all > /dev/null 2>&1
    
    # 15초 대기 (서비스 안정화)
    log_message "15초 대기 중 (서비스 안정화)..."
    sleep 15
    
    # 테스트
    if test_coupang_access; then
        log_message "${GREEN}Level 3 해결 성공!${NC}"
        return 0
    else
        log_message "${YELLOW}Level 3로 해결되지 않음. 다음 단계 필요.${NC}"
        return 1
    fi
}

# Level 4: 개별 동글 재시작
level4_dongle_reset() {
    log_message "\n${YELLOW}=== Level 4: 개별 동글 재시작 ===${NC}"
    
    # 테스트할 subnet 추출 (포트에서 10000 빼기)
    subnet=$((PROXY_PORT - 10000))
    
    log_message "동글 $subnet 재시작 중..."
    
    # 스마트 토글 실행
    if [ -f "/home/proxy/scripts/smart_toggle.py" ]; then
        python3 /home/proxy/scripts/smart_toggle.py $subnet 2>&1 | tee -a "$LOG_FILE"
    else
        log_message "${RED}smart_toggle.py를 찾을 수 없습니다.${NC}"
        
        # 대체: 전원 재시작
        if [ -f "/home/proxy/scripts/power_control.sh" ]; then
            log_message "전원 재시작 시도..."
            /home/proxy/scripts/power_control.sh off $subnet
            sleep 5
            /home/proxy/scripts/power_control.sh on $subnet
        fi
    fi
    
    # 20초 대기 (동글 재연결)
    log_message "20초 대기 중 (동글 재연결)..."
    sleep 20
    
    # 라우팅 재설정
    log_message "라우팅 재설정..."
    /home/proxy/scripts/manual_setup.sh > /dev/null 2>&1
    
    # SOCKS5 재시작
    /home/proxy/scripts/socks5/manage_socks5.sh restart $subnet > /dev/null 2>&1
    
    # 10초 대기
    sleep 10
    
    # 테스트
    if test_coupang_access; then
        log_message "${GREEN}Level 4 해결 성공!${NC}"
        return 0
    else
        log_message "${YELLOW}Level 4로 해결되지 않음. 다음 단계 필요.${NC}"
        return 1
    fi
}

# Level 5: 전체 시스템 재초기화
level5_full_reset() {
    log_message "\n${YELLOW}=== Level 5: 전체 시스템 재초기화 ===${NC}"
    log_message "${RED}경고: 모든 연결이 일시적으로 중단됩니다.${NC}"
    
    # 모든 SOCKS5 중지
    log_message "모든 SOCKS5 서비스 중지..."
    /home/proxy/scripts/socks5/manage_socks5.sh stop all > /dev/null 2>&1
    
    # 모든 동글 전원 재시작
    log_message "모든 동글 전원 재시작..."
    if [ -f "/home/proxy/scripts/power_control.sh" ]; then
        /home/proxy/scripts/power_control.sh off all
        sleep 10
        /home/proxy/scripts/power_control.sh on all
    fi
    
    # 30초 대기
    log_message "30초 대기 중 (동글 재연결)..."
    sleep 30
    
    # 동글 구성 재초기화
    log_message "동글 구성 재초기화..."
    if [ -f "/home/proxy/init_dongle_config.sh" ]; then
        /home/proxy/init_dongle_config.sh > /dev/null 2>&1
    fi
    
    # TCP 최적화 재적용
    log_message "TCP 최적화 재적용..."
    if [ -f "/home/proxy/scripts/optimize_tcp_for_mobile.sh" ]; then
        bash /home/proxy/scripts/optimize_tcp_for_mobile.sh > /dev/null 2>&1
    fi
    
    # SOCKS5 시작
    log_message "SOCKS5 서비스 시작..."
    /home/proxy/scripts/socks5/manage_socks5.sh start all > /dev/null 2>&1
    
    # 20초 대기
    log_message "20초 대기 중 (서비스 안정화)..."
    sleep 20
    
    # 테스트
    if test_coupang_access; then
        log_message "${GREEN}Level 5 해결 성공!${NC}"
        return 0
    else
        log_message "${RED}Level 5로도 해결되지 않음. 재부팅이 필요할 수 있습니다.${NC}"
        return 1
    fi
}

# 메인 실행 로직
main() {
    log_message "\n${BLUE}======================================${NC}"
    log_message "${BLUE}TLS 감지 문제 해결 스크립트 시작${NC}"
    log_message "${BLUE}시간: $(date)${NC}"
    log_message "${BLUE}======================================${NC}"
    
    # 초기 테스트
    log_message "\n${BLUE}초기 상태 테스트${NC}"
    if test_coupang_access; then
        log_message "${GREEN}문제 없음! 쿠팡 접속이 정상적입니다.${NC}"
        exit 0
    fi
    
    # TCP 설정 백업
    backup_tcp_settings
    
    # 레벨 지정 확인
    if [ -n "$1" ]; then
        level=$1
        log_message "\n지정된 레벨: $level"
        
        case $level in
            1) level1_soft_fix ;;
            2) level2_tcp_optimize ;;
            3) level3_connection_cleanup ;;
            4) level4_dongle_reset ;;
            5) level5_full_reset ;;
            *) log_message "${RED}잘못된 레벨: $level (1-5 사용)${NC}" ;;
        esac
    else
        # 자동 진행 모드
        log_message "\n${BLUE}자동 진행 모드 시작${NC}"
        
        # Level 1
        if ! level1_soft_fix; then
            # Level 2
            if ! level2_tcp_optimize; then
                # Level 3
                if ! level3_connection_cleanup; then
                    # Level 4
                    if ! level4_dongle_reset; then
                        # Level 5
                        level5_full_reset
                    fi
                fi
            fi
        fi
    fi
    
    # 최종 상태 출력
    log_message "\n${BLUE}=== 최종 상태 ===${NC}"
    log_message "TCP 타임스탬프: $(sysctl -n net.ipv4.tcp_timestamps)"
    log_message "혼잡 제어: $(sysctl -n net.ipv4.tcp_congestion_control)"
    log_message "TIME_WAIT 수: $(ss -tn state time-wait | wc -l)"
    log_message "HTTPS 연결: $(ss -tn state established '( dport = :443 or sport = :443 )' | wc -l)"
    
    # 최종 테스트
    log_message "\n${BLUE}최종 테스트${NC}"
    if test_coupang_access; then
        log_message "${GREEN}✓ 문제 해결 완료!${NC}"
        
        # 분석 스크립트 실행 권장
        log_message "\n${BLUE}권장사항:${NC}"
        log_message "1. 5분 후 다시 테스트: $0"
        log_message "2. 문제 재발시 로그 분석: /home/proxy/scripts/analyze_failure_time.py \"$(date '+%Y-%m-%d %H:%M')\""
    else
        log_message "${RED}✗ 문제가 지속됩니다. 재부팅을 고려하세요.${NC}"
        log_message "권장: sudo reboot"
    fi
    
    log_message "\n로그 파일: $LOG_FILE"
}

# 실행
main "$@"