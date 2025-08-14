#!/bin/bash

#============================================================
# 동글 관리 스크립트
# 
# 연결된 모든 유심의 트래픽 리셋 및 APN 확인
# 
# 사용법:
#   ./dongle_manager.sh info [--subnet 11,12,13]
#   ./dongle_manager.sh reset [--subnet 11,12,13]
#   ./dongle_manager.sh apn [--subnet 11,12,13]
#   ./dongle_manager.sh traffic [--subnet 11,12,13]
#============================================================

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 프로젝트 경로
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/dongle_info.py"

# 사용법 출력
usage() {
    echo "사용법: $0 <명령> [옵션]"
    echo ""
    echo "명령:"
    echo "  info     - 동글 종합 정보 (트래픽 + APN + 네트워크)"
    echo "  reset    - 트래픽 리셋 + 정보 표시"
    echo "  apn      - APN 정보만 표시"
    echo "  traffic  - 트래픽 정보만 표시"
    echo ""
    echo "옵션:"
    echo "  --subnet <번호>  특정 서브넷만 처리 (예: --subnet 11,12,13)"
    echo "  --json           JSON 형태로 출력"
    echo "  --help           도움말 표시"
    echo ""
    echo "예시:"
    echo "  $0 info                    # 모든 동글 종합 정보"
    echo "  $0 reset --subnet 11,12    # 특정 동글 트래픽 리셋"
    echo "  $0 apn --json              # APN 정보를 JSON으로 출력"
}

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# JSON 출력 파싱 및 표시
display_dongle_info() {
    local json_data="$1"
    local show_mode="$2"  # info, apn, traffic
    
    # jq가 없으면 raw JSON 출력
    if ! command -v jq &> /dev/null; then
        echo "$json_data"
        return
    fi
    
    # 헤더 출력
    local timestamp=$(echo "$json_data" | jq -r '.timestamp // "Unknown"')
    local total_dongles=$(echo "$json_data" | jq -r '.summary.connected // 0')
    local total_traffic=$(echo "$json_data" | jq -r '.summary.total_traffic_gb // 0')
    
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  연결된 동글 정보 (${timestamp:0:19})${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    # 동글별 정보 출력
    local dongles=$(echo "$json_data" | jq -r '.dongles | keys[]' 2>/dev/null | sort -n)
    
    if [ -z "$dongles" ]; then
        echo -e "${RED}연결된 동글이 없습니다.${NC}"
        return
    fi
    
    for subnet in $dongles; do
        local dongle_data=$(echo "$json_data" | jq ".dongles.\"$subnet\"")
        local status=$(echo "$dongle_data" | jq -r '.status // "unknown"')
        
        if [ "$status" = "connected" ]; then
            echo -e "${GREEN}동글 $subnet${NC} (192.168.$subnet.100):"
            
            # 네트워크 정보
            if [ "$show_mode" = "info" ] || [ "$show_mode" = "apn" ]; then
                local operator=$(echo "$dongle_data" | jq -r '.network.operator // "Unknown"')
                local network_type=$(echo "$dongle_data" | jq -r '.network.network_type // "Unknown"')
                local rssi=$(echo "$dongle_data" | jq -r '.signal.rssi // "Unknown"')
                
                echo -e "  ├ 통신사: ${CYAN}$operator${NC}"
                echo -e "  ├ 네트워크: $network_type (신호: ${rssi}dBm)"
            fi
            
            # APN 정보
            if [ "$show_mode" = "info" ] || [ "$show_mode" = "apn" ]; then
                local apn_name=$(echo "$dongle_data" | jq -r '.apn.name // "Unknown"')
                local auth_type=$(echo "$dongle_data" | jq -r '.apn.auth_type // "Unknown"')
                
                echo -e "  ├ APN: ${YELLOW}$apn_name${NC}"
                echo -e "  ├ 인증: $auth_type"
            fi
            
            # 트래픽 정보
            if [ "$show_mode" = "info" ] || [ "$show_mode" = "traffic" ]; then
                local upload_gb=$(echo "$dongle_data" | jq -r '.traffic.upload_gb // 0')
                local download_gb=$(echo "$dongle_data" | jq -r '.traffic.download_gb // 0')
                local total_gb=$(echo "$dongle_data" | jq -r '.traffic.total_gb // 0')
                
                echo -e "  ├ 트래픽: ↑${upload_gb}GB ↓${download_gb}GB (총 ${CYAN}${total_gb}GB${NC})"
            fi
            
            # 리셋 정보 (있는 경우)
            local reset_success=$(echo "$dongle_data" | jq -r '.reset.success // null')
            if [ "$reset_success" = "true" ]; then
                local old_gb=$(echo "$dongle_data" | jq -r '.reset.old_traffic_gb // 0')
                local new_gb=$(echo "$dongle_data" | jq -r '.reset.new_traffic_gb // 0')
                echo -e "  ├ 리셋: ${GREEN}성공${NC} (${old_gb}GB → ${new_gb}GB)"
            elif [ "$reset_success" = "false" ]; then
                local error=$(echo "$dongle_data" | jq -r '.reset.error // "Unknown error"')
                echo -e "  ├ 리셋: ${RED}실패${NC} ($error)"
            fi
            
            echo -e "  └ 상태: ${GREEN}정상${NC}"
            
        else
            local error=$(echo "$dongle_data" | jq -r '.error // "Connection failed"')
            echo -e "${RED}동글 $subnet${NC}: ${RED}연결 실패${NC} ($error)"
        fi
        echo ""
    done
    
    # 요약 정보
    echo -e "${BLUE}=========================================${NC}"
    if [ "$show_mode" = "info" ] || [ "$show_mode" = "traffic" ]; then
        echo -e "총 ${total_dongles}개 동글 연결됨 | 총 트래픽: ${CYAN}${total_traffic}GB${NC}"
    else
        echo -e "총 ${total_dongles}개 동글 연결됨"
    fi
    
    # 리셋 요약 (있는 경우)
    local reset_successful=$(echo "$json_data" | jq -r '.summary.reset_successful // null')
    if [ "$reset_successful" != "null" ]; then
        echo -e "트래픽 리셋: ${reset_successful}/${total_dongles}개 성공"
    fi
    
    echo -e "${BLUE}=========================================${NC}"
    echo ""
}

# 메인 실행 함수
main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    local command="$1"
    local subnet_filter=""
    local json_output=false
    
    # 옵션 파싱
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --subnet)
                subnet_filter="$2"
                shift 2
                ;;
            --json)
                json_output=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Python 스크립트 존재 확인
    if [ ! -f "$PYTHON_SCRIPT" ]; then
        log_error "Python 스크립트를 찾을 수 없습니다: $PYTHON_SCRIPT"
        exit 1
    fi
    
    # Python 실행 및 결과 처리
    local python_cmd=""
    case "$command" in
        info|apn|traffic)
            python_cmd="python3 $PYTHON_SCRIPT info"
            ;;
        reset)
            log_warning "트래픽 리셋을 시작합니다..."
            python_cmd="python3 $PYTHON_SCRIPT reset"
            ;;
        *)
            log_error "알 수 없는 명령: $command"
            usage
            exit 1
            ;;
    esac
    
    # 서브넷 필터 추가
    if [ -n "$subnet_filter" ]; then
        python_cmd="$python_cmd $subnet_filter"
    fi
    
    # Python 스크립트 실행
    log_info "동글 정보를 수집하는 중..."
    local result
    result=$($python_cmd 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "동글 정보 수집 실패"
        echo "$result"
        exit 1
    fi
    
    # 결과 출력
    if [ "$json_output" = true ]; then
        echo "$result"
    else
        display_dongle_info "$result" "$command"
    fi
}

# 스크립트 실행
main "$@"