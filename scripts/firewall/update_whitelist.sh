#!/bin/bash

#############################################
# SOCKS5 Whitelist 업데이트 스크립트
# - GitHub Gist에서 IP 목록 다운로드
# - 변경사항 있으면 방화벽 자동 재적용
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/home/proxy/config/firewall_config.json"
WHITELIST_FILE="/home/proxy/config/whitelist_ips.txt"
LOG_FILE="/home/proxy/logs/firewall/firewall.log"
APPLY_SCRIPT="$SCRIPT_DIR/apply_firewall.sh"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 설정 파일 존재 확인
if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: 설정 파일 없음: $CONFIG_FILE"
    log "먼저 init_firewall.sh를 실행하세요."
    exit 1
fi

# 방화벽 활성화 여부 확인
ENABLED=$(jq -r '.enabled' "$CONFIG_FILE" 2>/dev/null)
if [ "$ENABLED" != "true" ]; then
    log "INFO: 방화벽이 비활성화되어 있습니다. 업데이트를 건너뜁니다."
    exit 0
fi

# Whitelist URL 가져오기
WHITELIST_URL=$(jq -r '.whitelist_url' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$WHITELIST_URL" ] || [ "$WHITELIST_URL" = "null" ]; then
    log "ERROR: Whitelist URL이 설정되지 않았습니다."
    exit 1
fi

log "INFO: Whitelist 업데이트 시작: $WHITELIST_URL"

# 임시 파일에 다운로드
TMP_FILE=$(mktemp)
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TMP_FILE" "$WHITELIST_URL" --max-time 30)

if [ "$HTTP_CODE" != "200" ]; then
    log "ERROR: Whitelist 다운로드 실패 (HTTP $HTTP_CODE)"
    rm -f "$TMP_FILE"
    exit 1
fi

# 다운로드한 파일 크기 확인
FILE_SIZE=$(stat -c%s "$TMP_FILE" 2>/dev/null)
if [ -z "$FILE_SIZE" ] || [ "$FILE_SIZE" -eq 0 ]; then
    log "ERROR: 다운로드한 파일이 비어있습니다."
    rm -f "$TMP_FILE"
    exit 1
fi

# IP 형식 검증 (주석과 빈 줄 제거 후)
# IP 뒤에 주석(# 설명)이 있는 경우도 처리
VALID_IPS=$(grep -v '^#' "$TMP_FILE" | grep -v '^$' | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | wc -l)
TOTAL_LINES=$(grep -v '^#' "$TMP_FILE" | grep -v '^$' | wc -l)

if [ "$VALID_IPS" -eq 0 ]; then
    log "ERROR: 유효한 IP 주소가 없습니다."
    log "다운로드 내용 (처음 10줄):"
    head -10 "$TMP_FILE" | tee -a "$LOG_FILE"
    rm -f "$TMP_FILE"
    exit 1
fi

if [ "$VALID_IPS" -ne "$TOTAL_LINES" ]; then
    log "WARNING: 일부 줄이 유효한 IP 형식이 아닙니다. (유효: $VALID_IPS / 전체: $TOTAL_LINES)"
fi

# 유효한 IP만 추출 (주석 제거, 정렬)
# 각 줄에서 IP 부분만 추출 (# 이후는 무시)
grep -v '^#' "$TMP_FILE" | grep -v '^$' | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort -u > "${TMP_FILE}.clean"

# 기존 파일과 비교
if [ -f "$WHITELIST_FILE" ]; then
    if diff -q "$WHITELIST_FILE" "${TMP_FILE}.clean" > /dev/null 2>&1; then
        log "INFO: Whitelist 변경사항 없음 (IP 개수: $VALID_IPS)"
        rm -f "$TMP_FILE" "${TMP_FILE}.clean"
        exit 2  # 변경사항 없음을 의미하는 exit code
    else
        log "INFO: Whitelist 변경 감지"
        log "변경 전 IP 개수: $(wc -l < "$WHITELIST_FILE")"
        log "변경 후 IP 개수: $(wc -l < "${TMP_FILE}.clean")"

        # 추가된 IP
        ADDED=$(comm -13 <(sort "$WHITELIST_FILE") <(sort "${TMP_FILE}.clean"))
        if [ -n "$ADDED" ]; then
            log "추가된 IP:"
            echo "$ADDED" | tee -a "$LOG_FILE"
        fi

        # 제거된 IP
        REMOVED=$(comm -23 <(sort "$WHITELIST_FILE") <(sort "${TMP_FILE}.clean"))
        if [ -n "$REMOVED" ]; then
            log "제거된 IP:"
            echo "$REMOVED" | tee -a "$LOG_FILE"
        fi
    fi
else
    log "INFO: 첫 번째 Whitelist 다운로드 (IP 개수: $VALID_IPS)"
fi

# 새 파일로 교체
mv "${TMP_FILE}.clean" "$WHITELIST_FILE"
rm -f "$TMP_FILE"

log "INFO: Whitelist 업데이트 완료"

# 방화벽 규칙 재적용
if [ -x "$APPLY_SCRIPT" ]; then
    log "INFO: 방화벽 규칙 재적용 시작"
    "$APPLY_SCRIPT"
    if [ $? -eq 0 ]; then
        log "SUCCESS: 방화벽 규칙 재적용 완료"
    else
        log "ERROR: 방화벽 규칙 재적용 실패"
        exit 1
    fi
else
    log "ERROR: apply_firewall.sh를 찾을 수 없거나 실행 권한이 없습니다."
    exit 1
fi

exit 0
