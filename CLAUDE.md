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

# Initialize firewall (optional but recommended)
sudo ./firewall.sh
# Automatically downloads whitelist and applies firewall rules
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

#### Quick Install (dependencies already installed)
```bash
cd /home/proxy
sudo ./install.sh
sudo ./init_dongle_config.sh
```

#### Full System Install (Rocky Linux 9 minimal)
```bash
# Complete system installation including all dependencies
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

### Firewall Management (SOCKS5 Whitelist)
```bash
# Setup/Update firewall (download latest whitelist and apply)
./firewall.sh

# Check firewall status
./firewall.sh status

# Disable firewall
./firewall.sh off

# View firewall logs
tail -f /home/proxy/logs/firewall/firewall.log
grep "SOCKS5-BLOCKED" /var/log/messages | tail -20
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

### 방화벽 관리 (firewall/)
- `init_firewall.sh`: 방화벽 초기 설정 (대화형)
- `apply_firewall.sh`: iptables 규칙 적용
- `update_whitelist.sh`: GitHub Gist에서 Whitelist 다운로드
- `check_firewall.sh`: 방화벽 상태 및 차단 통계 확인

### 중요 설정
- **초기 설정 필수**: `init_dongle_config.sh` 실행으로 동글 구성
- **방화벽 설정 권장**: `init_firewall.sh` 실행으로 SOCKS5 보안 강화
- **개별 SOCKS5 서비스**: 각 동글별 독립 systemd 서비스
- **자동 연결**: systemd 서비스로 부팅 시 자동 시작
- **안정적인 토글**: 4단계 진단 기반 복구 시스템
- **동시 토글 제한**: 정상 3개, 복구 중 무제한
- **USB 매핑 영구 저장**: dongle_config.json에 허브/포트 매핑
- **Whitelist 자동 업데이트**: GitHub Gist 기반 중앙 관리

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

### SOCKS5 Firewall System
The firewall system provides IP-based access control:
- **iptables-based whitelist**: Only approved IPs can connect to SOCKS5 ports
- **GitHub Gist integration**: Central whitelist management across multiple servers
- **Auto-detection**: Automatically discovers active SOCKS5 ports from dongle_config.json
- **Auto-update**: Periodically downloads latest whitelist (default: hourly)
- **systemd integration**: Firewall rules apply on boot after dongle-toggle-api
- **Logging**: Optional logging of blocked connection attempts

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

## Troubleshooting & Diagnostics

### SOCKS5 프록시 장애 진단 절차

#### 문제 증상
- 모든 SOCKS5 포트가 동시에 연결 안됨
- 재시작해도 복구 안됨
- 재부팅만 해결됨

#### 즉시 확인 명령어
```bash
# 1. 현재 상태 확인
/home/proxy/scripts/monitoring/check_conntrack.sh
/home/proxy/scripts/check_socks5_memory.sh

# 2. TIME_WAIT 및 ephemeral 포트 확인
cat /proc/net/nf_conntrack | grep TIME_WAIT | wc -l
echo "Ephemeral ports: $(ss -an | grep -E ":[0-9]+\s" | awk '{print $4}' | cut -d: -f2 | awk '$1 >= 32768 && $1 <= 60999' | sort -u | wc -l) / 28231"
```

#### 문제 발생 후 분석 (중요!)
```bash
# 문제 발생 시간을 기록한 후 실행
# 예: 2025-08-20 14:30에 문제 발생
/home/proxy/scripts/monitoring/analyze_failure_time.py "2025-08-20 14:30"

# 상세 분석
/home/proxy/scripts/monitoring/analyze_failure_time.py "2025-08-20 14:30" --detailed
```

### 시스템 메트릭 수집

#### 자동 수집 (크론)
- **매분 실행**: `/home/proxy/scripts/monitoring/collect_system_metrics.sh`
- **저장 위치**: `/home/proxy/logs/metrics/YYYY-MM-DD/metrics_HH-MM.json`
- **보관 기간**: 7일 (자동 삭제)
- **최대 용량**: 5GB

#### 수집 데이터
- 시스템 메모리/CPU
- Conntrack 상태 (TIME_WAIT, ESTABLISHED 등)
- Ephemeral 포트 사용률
- SOCKS5 프로세스별 메모리/스레드/연결수
- 네트워크 인터페이스 에러
- TCP 소켓 상태

### 원인별 해결 방법

#### 1. Ephemeral 포트 고갈 (가장 의심)
```bash
# 확인
cat /proc/sys/net/ipv4/ip_local_port_range

# 해결: 포트 범위 확대
echo "15000 65000" > /proc/sys/net/ipv4/ip_local_port_range
```

#### 2. TIME_WAIT 과다
```bash
# 확인
cat /proc/net/nf_conntrack | grep TIME_WAIT | wc -l

# 해결: TIME_WAIT 최적화
/home/proxy/scripts/optimization/optimize_time_wait.sh
```

#### 3. Conntrack 테이블 포화
```bash
# 확인
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max

# 해결: 테이블 크기 증가
echo 524288 > /proc/sys/net/netfilter/nf_conntrack_max
```

#### 4. 메모리 누수
```bash
# 확인
/home/proxy/scripts/socks5_detailed_status.py

# 해결: 서비스 재시작
/home/proxy/scripts/socks5/manage_socks5.sh restart all
```

### 예방 조치

#### 자동 모니터링 (이미 설정됨)
- **매시간**: SOCKS5 전체 재시작 (메모리 초기화)
- **5분마다**: 헬스체크 및 문제시 개별 재시작
- **매분**: 시스템 메트릭 수집 (사후 분석용)

#### 권장 시스템 설정
```bash
# TCP 최적화 (모바일 네트워크 모방)
/home/proxy/scripts/optimization/optimize_tcp_for_mobile.sh

# TIME_WAIT 최적화
/home/proxy/scripts/optimization/optimize_time_wait.sh
```

### 네트워크 버퍼 진단

#### 패킷 드롭 확인
```bash
# 메인 인터페이스 패킷 드롭 확인
netstat -i | grep eno1
# RX-DRP와 TX-DRP 값이 높으면 버퍼 문제

# 모든 동글 인터페이스 패킷 드롭 확인
for i in {11..23}; do 
  iface=$(ip addr | grep "192.168.$i.100" -B2 | head -1 | cut -d: -f2 | tr -d ' ')
  if [ -n "$iface" ]; then
    echo "Subnet $i ($iface):"
    netstat -i | grep "^$iface" | head -1
  fi
done
```

#### Ring 버퍼 크기 확인
```bash
# 현재 Ring 버퍼 크기 확인
ethtool -g eno1

# Ring 버퍼가 256 이하면 너무 작음 (권장: 4096)
# 증가 방법:
sudo ethtool -G eno1 rx 4096 tx 4096
```

#### Softnet 통계 확인
```bash
# CPU별 패킷 처리 통계
cat /proc/net/softnet_stat
# 두 번째 값이 0이 아니면 패킷 드롭 발생

# 해석: 각 줄은 CPU, 값은 16진수
# 1번째: 처리된 패킷 수
# 2번째: 드롭된 패킷 수 (중요!)
# 3번째: time squeeze 발생 횟수
```

#### 네트워크 백로그 설정
```bash
# 현재 설정 확인
sysctl net.core.netdev_max_backlog
sysctl net.core.netdev_budget

# 권장 설정 (패킷 드롭 방지)
echo 5000 > /proc/sys/net/core/netdev_max_backlog
echo 300 > /proc/sys/net/core/netdev_budget
```

#### 소켓 버퍼 크기 확인
```bash
# 현재 소켓 버퍼 크기
sysctl net.core.rmem_max
sysctl net.core.wmem_max

# 권장 설정 (4MB)
echo 4194304 > /proc/sys/net/core/rmem_max
echo 4194304 > /proc/sys/net/core/wmem_max
```

#### 문제 발생시 네트워크 버퍼 분석
```bash
# analyze_failure_time.py가 자동으로 분석
# 다음 항목들을 체크:
# - 메인 인터페이스 RX/TX 드롭
# - 동글 인터페이스 총 드롭
# - Ring 버퍼 크기
# - Softnet 드롭 통계
# - netdev_max_backlog 설정

/home/proxy/scripts/monitoring/analyze_failure_time.py "2025-08-20 14:30"
```

### TLS 감지 문제 진단 및 해결

#### 문제 증상
- 쿠팡 등 특정 사이트에서 프록시 차단
- HTTPS 연결은 되지만 페이지 로드 실패
- 재부팅 후에는 일시적으로 정상 작동
- 시간이 지나면 다시 차단

#### 즉시 확인 사항
```bash
# TCP 타임스탬프 확인 (1이면 활성화 - 감지 위험)
sysctl net.ipv4.tcp_timestamps

# HTTPS TIME_WAIT 연결 수 확인
ss -tn state time-wait '( dport = :443 or sport = :443 )' | wc -l

# 쿠팡 접속 테스트
curl --socks5 localhost:10011 https://www.coupang.com -I
```

#### 수집된 메트릭 분석
```bash
# 문제 발생 시간대 TLS 관련 분석
/home/proxy/scripts/monitoring/analyze_failure_time.py "2025-08-20 14:30"

# 주요 확인 항목:
# - TCP 타임스탬프 활성화 여부
# - HTTPS TIME_WAIT 수 (500개 이상이면 위험)
# - TCP 재전송 횟수
# - 동글별 HTTPS 연결 수
```

#### 단계별 해결 방법

##### 자동 해결 (권장)
```bash
# 자동으로 Level 1부터 5까지 순차 진행
/home/proxy/scripts/optimization/tls_detection_fix.sh

# 특정 레벨만 실행
/home/proxy/scripts/optimization/tls_detection_fix.sh 1  # Level 1만
/home/proxy/scripts/optimization/tls_detection_fix.sh 2  # Level 2만
```

##### 수동 해결 단계

**Level 1: TCP 타임스탬프 비활성화 (가장 먼저 시도)**
```bash
# TLS 핑거프린팅 주요 지표 비활성화
sysctl -w net.ipv4.tcp_timestamps=0

# 10초 대기 후 테스트
sleep 10
curl --socks5 localhost:10011 https://www.coupang.com -I
```

**Level 2: TCP 모바일 최적화**
```bash
# 모바일 네트워크 환경 모방
/home/proxy/scripts/optimization/optimize_tcp_for_mobile.sh

# SOCKS5 재시작
/home/proxy/scripts/socks5/manage_socks5.sh restart all
```

**Level 3: 연결 상태 정리**
```bash
# TIME_WAIT 최적화
/home/proxy/scripts/optimization/optimize_time_wait.sh

# Conntrack 테이블 정리
conntrack -F

# SOCKS5 재시작
/home/proxy/scripts/socks5/manage_socks5.sh restart all
```

**Level 4: 동글 재시작**
```bash
# 문제 있는 동글만 재시작
python3 /home/proxy/scripts/smart_toggle.py 11

# 또는 전원 재시작
/home/proxy/scripts/power_control.sh off 11
sleep 5
/home/proxy/scripts/power_control.sh on 11
```

**Level 5: 전체 재초기화**
```bash
# 모든 서비스 재시작
systemctl restart dongle-toggle-api
/home/proxy/init_dongle_config.sh
```

#### 예방 조치

##### 부팅시 자동 적용
```bash
# /etc/rc.local 또는 systemd 서비스에 추가
/home/proxy/scripts/optimization/optimize_tcp_for_mobile.sh
```

##### 주기적 상태 정리 (크론)
```bash
# crontab -e에 추가 (30분마다)
*/30 * * * * /home/proxy/scripts/optimization/tls_detection_fix.sh 3 > /dev/null 2>&1
```

#### 모니터링

##### 실시간 TLS 상태 확인
```bash
# TCP 설정 및 HTTPS 연결 모니터링
watch -n 5 'echo "TCP Timestamps: $(sysctl -n net.ipv4.tcp_timestamps)"; \
            echo "HTTPS TIME_WAIT: $(ss -tn state time-wait "( dport = :443 or sport = :443 )" | wc -l)"; \
            echo "HTTPS ESTABLISHED: $(ss -tn state established "( dport = :443 or sport = :443 )" | wc -l)"'
```

##### 로그 확인
```bash
# TLS 해결 시도 로그
tail -f /home/proxy/logs/tls_detection_fix.log

# 메트릭 수집 데이터 (매분)
ls -la /home/proxy/logs/metrics/$(date +%Y-%m-%d)/
```

#### 문제 지속시

1. **메트릭 수집 후 분석**
   ```bash
   # 10분 대기 후 분석
   sleep 600
   /home/proxy/scripts/monitoring/analyze_failure_time.py "$(date '+%Y-%m-%d %H:%M' -d '5 minutes ago')"
   ```

2. **TCP 덤프 수집** (고급)
   ```bash
   # TLS 핸드셰이크 캡처
   tcpdump -i any -w /tmp/tls_capture.pcap 'tcp port 443' -c 1000
   ```

3. **최후 수단: 재부팅**
   ```bash
   sudo reboot
   ```

### 긴급 복구

#### 전체 시스템 재시작 (최후 수단)
```bash
# 1. 서비스만 재시작
systemctl restart dongle-toggle-api
/home/proxy/scripts/socks5/manage_socks5.sh restart all

# 2. 라우팅 초기화
/home/proxy/init_dongle_config.sh

# 3. 재부팅 (최후)
reboot
```