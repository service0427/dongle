#!/bin/bash
# USB 동글 전원 제어 스크립트
# 사용법: power_control.sh [on|off|cycle|status] [subnet|all]

CONFIG_FILE="/home/proxy/config/dongle_config.json"

get_hub_port() {
    local subnet=$1
    python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
mapping = config.get('port_mapping', {}).get('$subnet', {})
print(mapping.get('hub', ''), mapping.get('port', ''))
"
}

power_control() {
    local action=$1
    local hub=$2
    local port=$3

    if [ -z "$hub" ] || [ -z "$port" ]; then
        echo "Error: Invalid hub/port"
        return 1
    fi

    case $action in
        on)
            uhubctl -a on -l "$hub" -p "$port" 2>/dev/null
            ;;
        off)
            uhubctl -a off -l "$hub" -p "$port" 2>/dev/null
            ;;
        cycle)
            uhubctl -a cycle -l "$hub" -p "$port" 2>/dev/null
            ;;
        status)
            uhubctl -l "$hub" -p "$port" 2>/dev/null
            ;;
    esac
}

ACTION=$1
TARGET=$2

if [ -z "$ACTION" ]; then
    echo "Usage: $0 [on|off|cycle|status] [subnet|all]"
    exit 1
fi

if [ -z "$TARGET" ]; then
    TARGET="all"
fi

if [ "$TARGET" = "all" ]; then
    # 모든 동글 처리
    SUBNETS=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
print(' '.join(config.get('port_mapping', {}).keys()))
")
    for subnet in $SUBNETS; do
        read hub port <<< $(get_hub_port $subnet)
        if [ -n "$hub" ] && [ -n "$port" ]; then
            echo "Dongle $subnet (hub=$hub, port=$port): $ACTION"
            power_control $ACTION "$hub" "$port"
        fi
    done
else
    # 특정 동글만 처리
    read hub port <<< $(get_hub_port $TARGET)
    if [ -n "$hub" ] && [ -n "$port" ]; then
        echo "Dongle $TARGET (hub=$hub, port=$port): $ACTION"
        power_control $ACTION "$hub" "$port"
    else
        echo "Error: Dongle $TARGET not found in config"
        exit 1
    fi
fi
