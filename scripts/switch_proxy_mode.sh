#!/bin/bash

# Script to switch between mobile and PC proxy configurations

MODE=${1:-status}
LOG_FILE="/home/proxy/network-monitor/logs/proxy_mode.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_current_ttl() {
    # Check current TTL setting from iptables
    ttl=$(iptables -t mangle -L POSTROUTING -n -v | grep "TTL set to" | head -1 | sed 's/.*TTL set to //' | awk '{print $1}')
    if [ -z "$ttl" ]; then
        echo "unknown"
    else
        echo "$ttl"
    fi
}

get_current_mode() {
    ttl=$(get_current_ttl)
    case $ttl in
        64) 
            # Check if it's mobile or ubuntu mode
            mss=$(iptables -t mangle -L POSTROUTING -n -v | grep "TCPMSS" | head -1 | grep -o "set [0-9]*" | awk '{print $2}')
            if [ "$mss" = "1400" ]; then
                echo "mobile"
            else
                echo "ubuntu"
            fi
            ;;
        128) echo "pc" ;;
        *) echo "unknown" ;;
    esac
}

show_status() {
    mode=$(get_current_mode)
    ttl=$(get_current_ttl)
    
    echo "Current proxy mode: $mode"
    echo "Current TTL: $ttl"
    echo ""
    echo "Mode characteristics:"
    
    if [ "$mode" = "mobile" ]; then
        echo "  - TTL: 64 (mobile device default)"
        echo "  - TCP MSS: 1400 (mobile network)"
        echo "  - Appearance: Mobile device on cellular network"
    elif [ "$mode" = "pc" ]; then
        echo "  - TTL: 128 (Windows PC default)"
        echo "  - TCP MSS: 1460 (ethernet)"
        echo "  - Appearance: Desktop PC on broadband"
    elif [ "$mode" = "ubuntu" ]; then
        echo "  - TTL: 64 (Linux/Ubuntu default)"
        echo "  - TCP MSS: 1460 (ethernet)"
        echo "  - TCP: cubic congestion control"
        echo "  - Appearance: Ubuntu 22.04/24.04 desktop"
    else
        echo "  - No proxy stealth configuration active"
    fi
}

case $MODE in
    mobile)
        log "Switching to mobile mode..."
        /home/proxy/network-monitor/scripts/proxy_stealth_setup.sh
        echo "Switched to mobile mode"
        ;;
    pc)
        log "Switching to PC mode..."
        /home/proxy/network-monitor/scripts/proxy_stealth_setup_pc.sh
        echo "Switched to PC mode"
        ;;
    ubuntu)
        log "Switching to Ubuntu mode..."
        /home/proxy/network-monitor/scripts/proxy_stealth_setup_ubuntu.sh
        echo "Switched to Ubuntu mode"
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 [mobile|pc|ubuntu|status]"
        echo ""
        echo "  mobile - Configure proxy to appear as mobile device"
        echo "  pc     - Configure proxy to appear as Windows PC"
        echo "  ubuntu - Configure proxy to appear as Ubuntu desktop"
        echo "  status - Show current configuration (default)"
        echo ""
        show_status
        exit 1
        ;;
esac