#!/bin/bash

# 동글 설정 초기화 스크립트 v1.1
# 물리적으로 연결된 동글 정보를 수집하여 설정 파일에 저장
# 각 서버별로 다른 USB 허브 구성을 자동으로 감지하여 저장

CONFIG_DIR="/home/proxy/config"
CONFIG_FILE="$CONFIG_DIR/dongle_config.json"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# config 디렉토리 생성
mkdir -p "$CONFIG_DIR"

echo -e "${GREEN}=== 동글 설정 초기화 시작 ===${NC}"

# 1. uhubctl을 사용하여 물리적 동글 개수 확인
echo -e "\n${YELLOW}물리적 동글 감지 중...${NC}"
PHYSICAL_COUNT=$(sudo uhubctl | grep "HUAWEI_MOBILE" | wc -l)
echo -e "물리적으로 연결된 동글: ${GREEN}${PHYSICAL_COUNT}개${NC}"

# 2. 각 허브별 동글 정보 수집
echo -e "\n${YELLOW}허브별 동글 정보 수집 중...${NC}"

# 메인 허브 찾기
MAIN_HUB=$(sudo uhubctl | grep "hub 1-" | grep -v "\." | grep -oE "1-[0-9]+" | head -1)
if [ -z "$MAIN_HUB" ]; then
    MAIN_HUB="1-3"  # 기본값
fi
echo -e "메인 허브: ${GREEN}${MAIN_HUB}${NC}"

# 서브 허브 찾기
SUB_HUBS=$(sudo uhubctl | grep "hub ${MAIN_HUB}\." | grep -oE "${MAIN_HUB}\.[0-9]+" | sort -u)
echo -e "서브 허브: ${GREEN}$(echo $SUB_HUBS | tr '\n' ' ')${NC}"

# 3. 각 허브의 동글 연결 포트 확인
declare -A HUB_PORTS

for hub in $SUB_HUBS; do
    ports=$(sudo uhubctl | grep -A4 "hub $hub" | grep "HUAWEI_MOBILE" | grep -oE "Port [0-9]+" | grep -oE "[0-9]+")
    if [ ! -z "$ports" ]; then
        port_array=$(echo $ports | tr ' ' ',')
        HUB_PORTS[$hub]=$port_array
        echo -e "  ${hub}: 포트 [${GREEN}${port_array}${NC}]에 동글 연결됨"
    else
        HUB_PORTS[$hub]=""
        echo -e "  ${hub}: 연결된 동글 없음"
    fi
done

# 4. 현재 네트워크 인터페이스 확인
echo -e "\n${YELLOW}네트워크 인터페이스 확인 중...${NC}"
INTERFACE_COUNT=$(ip addr show | grep -c "192.168.[0-9][0-9].100")
echo -e "활성 네트워크 인터페이스: ${GREEN}${INTERFACE_COUNT}개${NC}"

# 5. lsusb로 인식된 동글 확인
LOGICAL_COUNT=$(lsusb | grep -c "HUAWEI" 2>/dev/null || echo 0)
LOGICAL_COUNT=$(echo "$LOGICAL_COUNT" | tr -d '\n')  # 개행 문자 제거
echo -e "lsusb로 인식된 동글: ${GREEN}${LOGICAL_COUNT}개${NC}"

# 6. 상태 비교
echo -e "\n${YELLOW}상태 분석:${NC}"
if [ "$PHYSICAL_COUNT" -eq "$INTERFACE_COUNT" ]; then
    echo -e "  ✓ 물리적 연결과 네트워크 인터페이스 ${GREEN}일치${NC}"
else
    echo -e "  ✗ 물리적 연결($PHYSICAL_COUNT)과 네트워크 인터페이스($INTERFACE_COUNT) ${RED}불일치${NC}"
fi

if [ "$PHYSICAL_COUNT" -eq "$LOGICAL_COUNT" ]; then
    echo -e "  ✓ 물리적 연결과 USB 인식 ${GREEN}일치${NC}"
else
    echo -e "  ✗ 물리적 연결($PHYSICAL_COUNT)과 USB 인식($LOGICAL_COUNT) ${RED}불일치${NC}"
    echo -e "  ${YELLOW}→ USB 허브 리셋이 필요할 수 있습니다${NC}"
fi

# 7. JSON 설정 파일 생성
echo -e "\n${YELLOW}설정 파일 생성 중...${NC}"

# 서브 허브 배열 생성
SUB_HUB_JSON=""
for hub in $SUB_HUBS; do
    if [ -z "$SUB_HUB_JSON" ]; then
        SUB_HUB_JSON="\"$hub\""
    else
        SUB_HUB_JSON="$SUB_HUB_JSON, \"$hub\""
    fi
done

# 물리적 동글 정보 생성
PHYSICAL_DONGLES_JSON=""
for hub in $SUB_HUBS; do
    ports="${HUB_PORTS[$hub]}"
    if [ ! -z "$PHYSICAL_DONGLES_JSON" ]; then
        PHYSICAL_DONGLES_JSON="$PHYSICAL_DONGLES_JSON,
"
    fi
    
    if [ -z "$ports" ]; then
        PHYSICAL_DONGLES_JSON="$PHYSICAL_DONGLES_JSON    \"$hub\": []"
    else
        port_json=$(echo "$ports" | sed 's/,/, /g')
        PHYSICAL_DONGLES_JSON="$PHYSICAL_DONGLES_JSON    \"$hub\": [$port_json]"
    fi
done

# JSON 파일 생성
cat > "$CONFIG_FILE" << EOF
{
  "expected_count": ${PHYSICAL_COUNT},
  "hub_info": {
    "main_hub": "${MAIN_HUB}",
    "sub_hubs": [${SUB_HUB_JSON}],
    "ports_per_hub": 4
  },
  "physical_dongles": {
${PHYSICAL_DONGLES_JSON}
  },
  "status": {
    "physical_count": ${PHYSICAL_COUNT},
    "interface_count": ${INTERFACE_COUNT},
    "logical_count": ${LOGICAL_COUNT}
  },
  "created_at": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF

echo -e "${GREEN}설정 파일이 생성되었습니다: ${CONFIG_FILE}${NC}"

# 8. 설정 파일 내용 표시
echo -e "\n${YELLOW}=== 설정 파일 내용 ===${NC}"
cat "$CONFIG_FILE"

# 9. 권장 사항
echo -e "\n${YELLOW}=== 권장 사항 ===${NC}"
if [ "$PHYSICAL_COUNT" -ne "$LOGICAL_COUNT" ]; then
    echo -e "${RED}경고: USB 인식 문제가 있습니다.${NC}"
    echo -e "다음 명령으로 USB 허브를 리셋할 수 있습니다:"
    echo -e "  ${GREEN}sudo uhubctl -a cycle -l ${MAIN_HUB} -p 1,3,4${NC}"
fi

# 서버별 정보 표시
echo -e "\n${YELLOW}=== 서버 정보 ===${NC}"
echo -e "서버 IP: ${GREEN}$(hostname -I | awk '{print $1}')${NC}"
echo -e "예상 동글 개수: ${GREEN}${EXPECTED_COUNT}개${NC}"
echo -e "실제 물리적 동글: ${GREEN}${PHYSICAL_COUNT}개${NC}"

echo -e "\n${GREEN}설정 초기화 완료!${NC}"
echo -e "설정을 업데이트하려면: ${GREEN}$0 --update${NC}"

# --update 옵션 처리
if [ "$1" == "--update" ]; then
    echo -e "\n${YELLOW}기존 설정을 현재 상태로 업데이트했습니다.${NC}"
fi