#!/bin/bash

# Fix missing routing rules for connected dongles

LOG_FILE="/home/proxy/network-monitor/logs/fix_routes.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Checking for missing routes..."

# Get all connected dongle IPs
connected_dongles=$(ip addr show | grep "inet 192.168" | grep -v "192.168.100" | awk '{print $2}' | cut -d'/' -f1 | sort)

fixed_count=0

for ip in $connected_dongles; do
    if [[ $ip =~ 192\.168\.([0-9]+)\.100 ]]; then
        subnet="${BASH_REMATCH[1]}"
        interface=$(ip addr show | grep -B2 "$ip" | head -1 | awk -F': ' '{print $2}')
        
        # Check if rule exists
        if ! ip rule list | grep -q "from $ip lookup dongle$subnet"; then
            log "Missing rule for dongle$subnet ($ip on $interface) - adding..."
            
            # Add routing table entry
            ip route add default via 192.168.$subnet.1 dev $interface table dongle$subnet 2>/dev/null
            
            # Add routing rule
            ip rule add from $ip table dongle$subnet
            
            # Add NAT if not exists
            if ! iptables -t nat -C POSTROUTING -o $interface -s 192.168.$subnet.0/24 -j MASQUERADE 2>/dev/null; then
                iptables -t nat -A POSTROUTING -o $interface -s 192.168.$subnet.0/24 -j MASQUERADE
            fi
            
            ((fixed_count++))
            log "Added routing for dongle$subnet"
        fi
    fi
done

log "Fixed $fixed_count missing routes"

# Show current status
log "Current routing rules:"
ip rule list | grep "lookup dongle" | sort -k6 -n