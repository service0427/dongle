#!/bin/bash

# 네트워크 설정 백업 스크립트
# 라우팅 테이블, 방화벽 규칙 등을 백업

BACKUP_DIR="/home/proxy/network-monitor/backup"
DATE=$(date +%Y%m%d_%H%M%S)

echo "=== Network Configuration Backup ==="
echo "Date: $(date)"
echo

# 1. 라우팅 테이블 백업
echo "Backing up routing tables..."
cp /etc/iproute2/rt_tables "$BACKUP_DIR/rt_tables.backup"

# 2. 현재 라우팅 규칙 백업
echo "Backing up routing rules..."
ip rule list > "$BACKUP_DIR/ip_rules_${DATE}.txt"
ip route show table all > "$BACKUP_DIR/ip_routes_${DATE}.txt"

# 3. 방화벽 규칙 백업
echo "Backing up iptables rules..."
iptables-save > "$BACKUP_DIR/iptables_${DATE}.rules"

# 4. NetworkManager 연결 프로필 백업
echo "Backing up NetworkManager connections..."
if [ -d /etc/NetworkManager/system-connections ]; then
    tar -czf "$BACKUP_DIR/nm_connections_${DATE}.tar.gz" /etc/NetworkManager/system-connections/
fi

# 5. 시스템 네트워크 설정 백업
echo "Backing up system network config..."
cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.backup" 2>/dev/null
sysctl -a | grep -E "net.ipv4.ip_forward|net.ipv4.conf" > "$BACKUP_DIR/sysctl_network_${DATE}.txt"

# 6. 현재 인터페이스 상태 백업
echo "Backing up interface status..."
ip addr > "$BACKUP_DIR/ip_addr_${DATE}.txt"
ip link > "$BACKUP_DIR/ip_link_${DATE}.txt"

echo
echo "Backup completed in: $BACKUP_DIR"
ls -la "$BACKUP_DIR"