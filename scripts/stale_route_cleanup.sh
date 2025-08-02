#!/bin/bash

# Automatic cleanup of stale dongle routes
# Runs periodically to clean up routes for disconnected dongles

LOG_FILE="/home/proxy/network-monitor/logs/cleanup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

cleanup_stale_routes() {
    local cleaned=0
    
    # Check each potential dongle subnet
    for i in {11..30}; do
        # Check if rule exists
        if ip rule list | grep -q "from 192.168.$i.100 lookup dongle$i"; then
            # Check if interface is actually connected
            if ! ip addr show | grep -q "192.168.$i.100"; then
                log "Found stale route for dongle$i - cleaning up"
                
                # Remove routing rule
                ip rule del from 192.168.$i.100 table dongle$i 2>/dev/null
                
                # Flush routing table
                ip route flush table dongle$i 2>/dev/null
                
                # Remove NAT rule
                iptables -t nat -D POSTROUTING -s 192.168.$i.0/24 -j MASQUERADE 2>/dev/null
                
                ((cleaned++))
            fi
        fi
    done
    
    if [ $cleaned -gt 0 ]; then
        log "Cleaned $cleaned stale routes"
    fi
}

# Run cleanup
cleanup_stale_routes