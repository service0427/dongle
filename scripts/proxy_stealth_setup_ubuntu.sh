#!/bin/bash

# Ubuntu 22.04/24.04 specific proxy configuration
# Makes proxy traffic appear as coming from Ubuntu desktop

LOG_FILE="/home/proxy/network-monitor/logs/proxy_stealth.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Setting up Ubuntu-like proxy configuration..."

# Clear existing rules
iptables -t mangle -F POSTROUTING

# 1. TCP Fingerprint modification for Ubuntu
for i in {11..30}; do
    if ip addr show | grep -q "192.168.$i.100"; then
        # Set TCP MSS to Ubuntu desktop typical value
        iptables -t mangle -A POSTROUTING -s 192.168.$i.0/24 -p tcp --tcp-flags SYN,RST SYN \
            -j TCPMSS --set-mss 1460
        
        # Ubuntu specific TCP settings
        echo 1 > /proc/sys/net/ipv4/tcp_timestamps
        echo 1 > /proc/sys/net/ipv4/tcp_window_scaling
        echo 1 > /proc/sys/net/ipv4/tcp_sack
        echo 1 > /proc/sys/net/ipv4/tcp_fack
        
        # Ubuntu default congestion control
        echo "cubic" > /proc/sys/net/ipv4/tcp_congestion_control
        
        log "Applied Ubuntu TCP settings for dongle $i"
    fi
done

# 2. TTL modification to match Ubuntu
# Ubuntu 22.04/24.04 default TTL: 64
for i in {11..30}; do
    if ip addr show | grep -q "192.168.$i.100"; then
        iptables -t mangle -A POSTROUTING -s 192.168.$i.0/24 -j TTL --ttl-set 64
        log "Set TTL to 64 (Ubuntu default) for dongle $i"
    fi
done

# 3. Remove proxy headers
iptables -I FORWARD -p tcp --dport 80 -m string --algo bm --string "X-Forwarded" -j DROP
iptables -I FORWARD -p tcp --dport 80 -m string --algo bm --string "X-Real-IP" -j DROP
iptables -I FORWARD -p tcp --dport 80 -m string --algo bm --string "Via:" -j DROP
iptables -I FORWARD -p tcp --dport 443 -m string --algo bm --string "X-Forwarded" -j DROP

# 4. Ubuntu-specific network parameters
# TCP keepalive (Ubuntu defaults)
echo 7200 > /proc/sys/net/ipv4/tcp_keepalive_time
echo 75 > /proc/sys/net/ipv4/tcp_keepalive_intvl
echo 9 > /proc/sys/net/ipv4/tcp_keepalive_probes

# TCP buffer sizes (Ubuntu defaults)
echo "4096 87380 6291456" > /proc/sys/net/ipv4/tcp_rmem
echo "4096 16384 4194304" > /proc/sys/net/ipv4/tcp_wmem

# TCP options
echo 1 > /proc/sys/net/ipv4/tcp_syncookies
echo 2 > /proc/sys/net/ipv4/tcp_synack_retries
echo 1 > /proc/sys/net/ipv4/tcp_rfc1337

# Ubuntu-specific TCP initial congestion window
# Note: tcp_init_cwnd is deprecated in newer kernels
# Using ip route to set initcwnd instead
for i in {11..30}; do
    if ip addr show | grep -q "192.168.$i.100"; then
        # Set initial congestion window for default route
        ip route change default via 192.168.$i.1 dev $(ip addr show | grep "192.168.$i.100" | awk '{print $NF}') initcwnd 10 2>/dev/null || true
    fi
done

log "Ubuntu-like proxy configuration completed"

# Test configuration
log "Testing dongle connectivity with Ubuntu settings..."
for i in 11 16; do
    if ip addr show | grep -q "192.168.$i.100"; then
        result=$(curl --interface 192.168.$i.100 -s -m 5 https://ipinfo.io/ip)
        if [ ! -z "$result" ]; then
            log "Dongle $i external IP: $result"
        fi
    fi
done