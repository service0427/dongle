#!/bin/bash

# PC-like proxy configuration
# Makes proxy traffic appear as regular PC connection

LOG_FILE="/home/proxy/network-monitor/logs/proxy_stealth.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Setting up PC-like proxy configuration..."

# Clear existing mobile-like rules
iptables -t mangle -F POSTROUTING

# 1. TCP Fingerprint modification for PC
# Set TCP options similar to Windows/Linux PCs
for i in {11..30}; do
    if ip addr show | grep -q "192.168.$i.100"; then
        # Set TCP MSS to PC typical value (1460 for ethernet)
        iptables -t mangle -A POSTROUTING -s 192.168.$i.0/24 -p tcp --tcp-flags SYN,RST SYN \
            -j TCPMSS --set-mss 1460
        
        # Enable TCP timestamps (common on PCs)
        echo 1 > /proc/sys/net/ipv4/tcp_timestamps
        
        # Set TCP window scaling
        echo 1 > /proc/sys/net/ipv4/tcp_window_scaling
        
        log "Applied PC TCP settings for dongle $i"
    fi
done

# 2. TTL modification to match PC devices
# Windows default: 128, Linux default: 64
# Using 128 for Windows-like appearance
for i in {11..30}; do
    if ip addr show | grep -q "192.168.$i.100"; then
        iptables -t mangle -A POSTROUTING -s 192.168.$i.0/24 -j TTL --ttl-set 128
        log "Set TTL to 128 (Windows default) for dongle $i"
    fi
done

# 3. Remove proxy-related headers at netfilter level
# Strip X-Forwarded-For, Via, X-Real-IP headers
iptables -I FORWARD -p tcp --dport 80 -m string --algo bm --string "X-Forwarded" -j DROP
iptables -I FORWARD -p tcp --dport 80 -m string --algo bm --string "X-Real-IP" -j DROP
iptables -I FORWARD -p tcp --dport 80 -m string --algo bm --string "Via:" -j DROP
iptables -I FORWARD -p tcp --dport 443 -m string --algo bm --string "X-Forwarded" -j DROP

# 4. Connection state optimization for PC
echo 86400 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
echo 262144 > /proc/sys/net/core/rmem_default
echo 262144 > /proc/sys/net/core/wmem_default
echo 4096 87380 4194304 > /proc/sys/net/ipv4/tcp_rmem
echo 4096 65536 4194304 > /proc/sys/net/ipv4/tcp_wmem

# 5. Enable typical PC network features
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
echo 1 > /proc/sys/net/ipv4/tcp_sack
echo 1 > /proc/sys/net/ipv4/tcp_fack

log "PC-like proxy configuration completed"

# Test configuration
log "Testing dongle connectivity with PC settings..."
for i in 11 16; do
    if ip addr show | grep -q "192.168.$i.100"; then
        result=$(curl --interface 192.168.$i.100 -s -m 5 https://ipinfo.io/ip)
        if [ ! -z "$result" ]; then
            log "Dongle $i external IP: $result"
        fi
    fi
done