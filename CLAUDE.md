# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains two main components:
1. **Network Monitor System** - A monitoring and routing system for Huawei E8372h USB dongles on Rocky Linux 9.6
2. **Flask Proxy Server** - A Flask-based proxy server for managing network toggles and traffic statistics

## Commands

### Service Management
```bash
# Start network monitoring services
sudo systemctl start network-monitor
sudo systemctl start network-monitor-health
sudo systemctl start network-monitor-startup

# Check service status
sudo systemctl status network-monitor
sudo systemctl status network-monitor-health

# Enable services on boot
sudo systemctl enable network-monitor
sudo systemctl enable network-monitor-health
sudo systemctl enable network-monitor-startup
```

### Installation
```bash
# Install network monitor
cd /home/proxy/network-monitor
sudo ./install.sh

# For complete installation with all configurations
sudo ./install-complete.sh
```

### Monitoring and Debugging
```bash
# Check dongle status
/home/proxy/network-monitor/tools/check_dongles.sh

# Debug network configuration
/home/proxy/network-monitor/tools/debug_network.sh

# Switch dongles from Mass Storage Mode
sudo /home/proxy/network-monitor/tools/switch_dongles.sh

# Check health status API
curl http://localhost:8080/status

# View logs
tail -f /home/proxy/network-monitor/logs/monitor.log
tail -f /home/proxy/network-monitor/logs/startup.log
tail -f /home/proxy/network-monitor/logs/recovery.log
tail -f /home/proxy/network-monitor/logs/hotplug.log
```

### Flask Server (if using pm2)
```bash
# Flask server is managed by pm2 at /home/proxy/server.py
pm2 status
pm2 restart server
pm2 logs server
```

## Architecture

### Network Monitor System
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
The Flask server (`server.py`) provides:
- Network toggle API endpoint: `GET /toggle/<port>`
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
- **No proxy headers**: Completely transparent, no Via/X-Forwarded-For headers

### Key Features
1. **Automatic startup**: SOCKS5 servers start automatically when dongles are connected
2. **Proxy info API**: `GET /proxy-info` returns available proxy connections
3. **Anti-detection**: TCP fingerprinting and TTL adjusted to match mobile devices
4. **IP rotation**: Use `/toggle/<subnet>` to change dongle IP (15-second cooldown)

### Example Usage
```bash
# Check available proxies
curl http://112.161.54.7:8080/proxy-info

# Use proxy with curl
curl --socks5 112.161.54.7:10011 https://ipinfo.io/ip

# Playwright integration
const browser = await chromium.launch({
    proxy: { server: 'socks5://112.161.54.7:10011' }
});
```

See `/home/proxy/network-monitor/docs/PROXY_USAGE.md` for detailed usage instructions.