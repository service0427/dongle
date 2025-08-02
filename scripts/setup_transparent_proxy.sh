#!/bin/bash

# Setup transparent proxy rules for dongles
# This removes proxy headers and makes traffic appear as direct mobile connection

LOG_FILE="/home/proxy/network-monitor/logs/transparent_proxy.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Setting up transparent proxy rules..."

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Clear existing mangle rules for our interfaces
for i in {11..30}; do
    iptables -t mangle -D PREROUTING -i enp0s21f0u3u* -p tcp -s 192.168.$i.0/24 -j MARK --set-mark $i 2>/dev/null
done

# Add mangle rules for each dongle subnet
for i in {11..30}; do
    # Check if interface exists
    if ip addr show | grep -q "192.168.$i.100"; then
        # Mark packets from dongle subnet
        iptables -t mangle -A PREROUTING -s 192.168.$i.0/24 -j MARK --set-mark $i
        
        # TCP MSS clamping to handle MTU issues
        iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -s 192.168.$i.0/24 -j TCPMSS --clamp-mss-to-pmtu
        
        log "Added transparent proxy rules for dongle $i"
    fi
done

# Add connection tracking helpers
modprobe nf_conntrack_ftp
modprobe nf_conntrack_tftp
modprobe nf_conntrack_sip
modprobe nf_conntrack_irc
modprobe nf_conntrack_h323

# Optimize connection tracking
echo 262144 > /proc/sys/net/netfilter/nf_conntrack_max
echo 120 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established

log "Transparent proxy setup completed"