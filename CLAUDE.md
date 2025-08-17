# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a unified USB dongle proxy management system:
1. **Smart Toggle System** - Intelligent toggle with diagnosis-based recovery for Huawei E8372h USB dongles
2. **SOCKS5 Proxy Server** - Transparent proxy service with automatic routing management  
3. **Automated Network Setup** - Self-configuring network with persistent USB device mapping

## Commands

### Initial Setup (Required)
```bash
# Initialize dongle configuration
cd /home/proxy
sudo ./init_dongle_config.sh
```

### Service Management
```bash
# Start dongle services
sudo systemctl start dongle-toggle-api

# Check service status  
sudo systemctl status dongle-toggle-api

# Individual SOCKS5 services
/home/proxy/scripts/socks5/manage_socks5.sh status
/home/proxy/scripts/socks5/manage_socks5.sh restart 11  # Specific dongle
/home/proxy/scripts/socks5/manage_socks5.sh restart all # All dongles

# Enable services on boot
sudo systemctl enable dongle-toggle-api
```

### Installation
```bash
# Complete system installation for Rocky Linux 9
cd /home/proxy
sudo bash setup_complete_system.sh
```

### Monitoring and Debugging
```bash
# Check all proxy connection status
/home/proxy/scripts/utils/check_proxy_ips.sh

# Manual network setup (routing initialization)
sudo /home/proxy/scripts/manual_setup.sh

# Individual dongle management
/home/proxy/scripts/utils/dongle_manager.sh info
/home/proxy/scripts/utils/dongle_manager.sh reset

# Power control (individual or all dongles)
sudo /home/proxy/scripts/power_control.sh status
sudo /home/proxy/scripts/power_control.sh off 11
sudo /home/proxy/scripts/power_control.sh on all

# Check API status
curl http://localhost/status

# View logs
tail -f /home/proxy/logs/toggle_api.log
tail -f /home/proxy/logs/socks5_proxy.log
tail -f /home/proxy/logs/push_status.log
```

### Flask Server (if using pm2)
```bash
# Flask server is managed by pm2 at /home/proxy/server.py
pm2 status
pm2 restart server
pm2 logs server
```

## Scripts 폴더 구조 (2025-08-16 업데이트)

### 자동화 핵심 파일
- `smart_toggle.py`: 지능형 토글 시스템 (진단→단계별 복구)
  - 0단계: 문제 진단 (인터페이스/라우팅/연결 상태)
  - 1단계: 라우팅 재설정 (가장 빠른 복구)
  - 2단계: 네트워크 토글 (모뎀 모드 전환)
  - 3단계: USB unbind/bind (드라이버 재시작)
  - 4단계: 전원 재시작 (개별→전체 허브 재시작)
- `toggle_api.js`: HTTP API 서버 (포트 80, config 기반 상태 관리)
- `socks5/`: SOCKS5 프록시 관련
  - `socks5_single.py`: 개별 포트용 독립 SOCKS5 서버
  - `manage_socks5.sh`: SOCKS5 서비스 관리 (start/stop/restart/status)
- `manual_setup.sh`: 시스템 시작 시 라우팅 초기 설정
- `power_control.sh`: USB 동글 전원 제어 (개별/전체)
- `usb_mapping.json`: USB 디바이스 매핑 정보 (허브/포트/경로)

### 관리/진단 도구 (utils/)  
- `check_proxy_ips.sh`: 모든 프록시 연결 상태 진단
- `dongle_manager.sh`: 트래픽 리셋/APN 확인
- `dongle_info.py`: 동글 정보 수집 API
- `install_uhubctl.sh`: uhubctl 설치 스크립트

### 중요 설정
- **초기 설정 필수**: `init_dongle_config.sh` 실행으로 동글 구성
- **개별 SOCKS5 서비스**: 각 동글별 독립 systemd 서비스
- **자동 연결**: systemd 서비스로 부팅 시 자동 시작
- **안정적인 토글**: 4단계 진단 기반 복구 시스템
- **동시 토글 제한**: 정상 3개, 복구 중 무제한
- **USB 매핑 영구 저장**: dongle_config.json에 허브/포트 매핑

## Architecture

### Smart Toggle System
The system consists of several interconnected components:

1. **Core Scripts** (`/home/proxy/network-monitor/scripts/`)
   - `monitor.sh` - Main monitoring loop that checks connectivity and triggers recovery
   - `startup.sh` - Boot-time configuration (IP forwarding, routing setup)
   - `setup_dongle_routing.sh` - Configures routing tables for each dongle
   - `recovery.sh` - Handles network recovery when failures detected
   - `dongle_hotplug.sh` - Triggered by udev for USB events
   - `health_check.js` - Node.js server providing health status API

2. **Service Architecture**
   - Uses systemd for service management with three services:
     - `network-monitor.service` - Main monitoring service
     - `network-monitor-health.service` - Health check web server
     - `network-monitor-startup.service` - One-shot startup configuration
   - udev rules trigger hotplug script on USB events

3. **Routing Strategy**
   - Main interface (eno1) always has lowest metric (100)
   - Dongles assigned incrementing metrics (200, 201, 202...)
   - Each dongle gets its own routing table (e.g., table 11 for 192.168.11.x)
   - IP rules ensure traffic from dongle IPs uses their respective tables

### Flask Proxy Server
The Toggle API server (`toggle_api.js`) provides:
- Network toggle API endpoint: `GET /toggle/<subnet>` (Port 80)
- Integration with Huawei LTE API for modem control
- Traffic statistics collection
- Proxy configuration for each dongle port (e.g., port 3311 for dongle on 192.168.11.x)

### Key Patterns

1. **Interface Detection**
   - Main interface: First active interface that's not USB
   - Dongle interfaces: USB interfaces with specific IP patterns (192.168.1[1-9].100, etc.)

2. **State Management**
   - JSON state file at `/home/proxy/network-monitor/logs/state.json`
   - Tracks current interfaces, IPs, and monitoring status

3. **Recovery Mechanism**
   - Configurable via `ENABLE_RECOVERY` in config
   - Monitors external connectivity through main interface
   - Attempts recovery after MAX_FAILURES consecutive failures

## Important Notes

1. **Path Migration**: This project was migrated from `/home` to `/home/proxy`. All paths have been updated accordingly.

2. **Recovery Sensitivity**: The recovery feature can be overly sensitive to temporary network delays. It's recommended to set `ENABLE_RECOVERY=no` in the config file unless absolutely needed.

3. **Metric Conflicts**: Some dongles may receive low DHCP metrics that conflict with the main interface priority. The system actively monitors and corrects this.

4. **USB Mode Issues**: Dongles may initialize in Mass Storage Mode. Use the switch_dongles.sh tool to convert them to network mode.

5. **Security Note**: The Flask server contains hardcoded credentials in NetworkConfig. These should be moved to environment variables or a secure configuration file.

6. **Logging**: All components log extensively. Monitor log sizes as they can grow quickly with DEBUG_MODE enabled.

7. **Node.js Requirement**: The health check server requires Node.js. Rocky Linux 9 users should install via: `dnf module install nodejs:18/common`

## SOCKS5 Proxy Feature

The system now includes a transparent SOCKS5 proxy server that makes traffic appear as genuine mobile network connections:

### Proxy Details
- **Port Range**: 10011-10030 (10000 + dongle subnet number)
- **Type**: SOCKS5 without authentication
- **Host**: 112.161.54.7 (external access)
- **API Port**: 80 (HTTP API for status/toggle)
- **No proxy headers**: Completely transparent, no Via/X-Forwarded-For headers

### Key Features
1. **Automatic startup**: SOCKS5 servers start automatically when dongles are connected
2. **Proxy info API**: `GET /proxy-info` returns available proxy connections
3. **Anti-detection**: TCP fingerprinting and TTL adjusted to match mobile devices
4. **IP rotation**: Use `/toggle/<subnet>` to change dongle IP (15-second cooldown)

### Example Usage
```bash
# Check available proxies
curl http://112.161.54.7/proxy-info

# Use proxy with curl
curl --socks5 112.161.54.7:10011 https://ipinfo.io/ip

# Playwright integration
const browser = await chromium.launch({
    proxy: { server: 'socks5://112.161.54.7:10011' }
});
```

See `/home/proxy/network-monitor/docs/PROXY_USAGE.md` for detailed usage instructions.