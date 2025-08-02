#!/bin/bash

# Enhanced proxy stealth configuration
# Makes proxy traffic indistinguishable from direct mobile connection

LOG_FILE="/home/proxy/network-monitor/logs/proxy_stealth.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Setting up stealth proxy configuration..."

# 1. TCP Fingerprint modification
# Change TCP options to match mobile devices
for i in {11..30}; do
    if ip addr show | grep -q "192.168.$i.100"; then
        # Set TCP options similar to mobile devices
        iptables -t mangle -A POSTROUTING -s 192.168.$i.0/24 -p tcp --tcp-flags SYN,RST SYN \
            -j TCPMSS --set-mss 1400
        
        # Randomize TCP timestamps
        echo 1 > /proc/sys/net/ipv4/tcp_timestamps
        
        # Set TCP window scaling
        echo 1 > /proc/sys/net/ipv4/tcp_window_scaling
        
        log "Applied TCP stealth settings for dongle $i"
    fi
done

# 2. TTL modification to match mobile devices
# Mobile devices typically have TTL 64
for i in {11..30}; do
    if ip addr show | grep -q "192.168.$i.100"; then
        iptables -t mangle -A POSTROUTING -s 192.168.$i.0/24 -j TTL --ttl-set 64
    fi
done

# 3. Remove proxy-related headers at netfilter level
# Strip X-Forwarded-For, Via, X-Real-IP headers
iptables -I FORWARD -p tcp --dport 80 -m string --algo bm --string "X-Forwarded" -j DROP
iptables -I FORWARD -p tcp --dport 80 -m string --algo bm --string "X-Real-IP" -j DROP
iptables -I FORWARD -p tcp --dport 80 -m string --algo bm --string "Via:" -j DROP
iptables -I FORWARD -p tcp --dport 443 -m string --algo bm --string "X-Forwarded" -j DROP

# 4. DNS configuration to use mobile carrier DNS
# This is already handled by dispatcher scripts

# 5. Connection state optimization
echo 86400 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
echo 65535 > /proc/sys/net/core/rmem_default
echo 65535 > /proc/sys/net/core/wmem_default
echo 4096 87380 4194304 > /proc/sys/net/ipv4/tcp_rmem
echo 4096 65536 4194304 > /proc/sys/net/ipv4/tcp_wmem

# 6. Disable ICMP redirects
echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects
echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects

# 7. Enable SYN cookies
echo 1 > /proc/sys/net/ipv4/tcp_syncookies

log "Stealth proxy configuration completed"

# Test configuration
log "Testing dongle connectivity..."
for i in 11 16; do
    if ip addr show | grep -q "192.168.$i.100"; then
        result=$(curl --interface 192.168.$i.100 -s -m 5 https://ipinfo.io/ip)
        if [ ! -z "$result" ]; then
            log "Dongle $i external IP: $result"
        fi
    fi
done