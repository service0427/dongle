# Huawei Dongle SOCKS5 Proxy System

Huawei E8372h USB 동글을 이용한 SOCKS5 프록시 서버 및 자동 토글 시스템입니다.

## 🚀 주요 기능

- **SOCKS5 프록시 서버**: 각 동글별 독립적인 SOCKS5 프록시 제공
- **자동 IP 토글**: 웹 API를 통한 동글 IP 변경 기능
- **트래픽 통계**: 업로드/다운로드 통계 수집 및 모니터링
- **동시성 제어**: 포트별 락 및 글로벌 동시 실행 제한
- **상태 모니터링**: 실시간 프록시 상태 확인 및 허브 서버 연동

## 🏗️ 시스템 아키텍처

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   External      │    │  Toggle API     │    │  SOCKS5 Proxy   │
│   Client        ├───▶│  Server         ├───▶│  Servers        │
│                 │    │  (Port 8080)    │    │  (10011-10030)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                 │
                                 ▼
                       ┌─────────────────┐
                       │  Huawei Dongles │
                       │  (192.168.x.x)  │
                       └─────────────────┘
```

## 📋 시스템 요구사항

- **OS**: Rocky Linux 9.6 (CentOS/RHEL 계열)
- **Hardware**: Huawei E8372h USB 동글
- **Software**: 
  - Node.js 18+
  - Python 3.8+
  - systemd
  - curl, netstat

## ⚡ 빠른 시작

### 1. 설치

```bash
# 리포지토리 클론
git clone https://github.com/service0427/dongle.git
cd dongle

# 설치 실행
chmod +x install.sh
sudo ./install.sh
```

### 2. 서비스 시작

```bash
# Toggle API 서버 시작
sudo systemctl start dongle-toggle-api
sudo systemctl enable dongle-toggle-api

# 상태 확인
sudo systemctl status dongle-toggle-api
```

### 3. 사용법

#### API 엔드포인트

- **헬스체크**: `GET /health`
- **프록시 상태**: `GET /status` 
- **IP 토글**: `GET /toggle/{subnet}`

#### 프록시 사용

```bash
# SOCKS5 프록시 사용 (포트 10011-10030)
curl --socks5 112.161.54.7:10011 https://ipinfo.io/ip

# 특정 동글 IP 변경
curl http://112.161.54.7:8080/toggle/11
```

## 🔧 설정

### 주요 설정 파일

- `scripts/toggle_api.js` - API 서버 설정
- `scripts/socks5_proxy.py` - SOCKS5 프록시 설정
- `scripts/push_proxy_status.sh` - 상태 전송 스크립트

### 환경 변수

- `MAX_CONCURRENT_TOGGLES=3` - 최대 동시 토글 수
- `TOGGLE_TIMEOUT=30000` - 토글 타임아웃 (ms)

## 📡 API 참조

### GET /status

프록시 상태 조회

```json
{
  "status": "ready",
  "api_version": "v1-enhanced", 
  "timestamp": "2025-08-12 21:00:22",
  "available_proxies": [
    {
      "proxy_url": "socks5://112.161.54.7:10011",
      "external_ip": "175.223.18.34",
      "last_toggle": "2025-08-12 20:15:30",
      "traffic": {
        "upload": 357587155,
        "download": 3598351751
      }
    }
  ]
}
```

### GET /toggle/{subnet}

특정 동글 IP 토글 (subnet: 11-30)

**성공 응답**:
```json
{
  "success": true,
  "timestamp": "2025-08-12 21:00:22",
  "ip": "175.223.22.72",
  "traffic": {
    "upload": 550946316,
    "download": 5126833837
  }
}
```

**에러 응답**:
```json
{
  "error": "Toggle already in progress for subnet 11",
  "code": "TOGGLE_IN_PROGRESS"
}
```

## 🔄 동시성 제어

### 포트별 락
- 같은 포트에 동시 토글 요청 차단
- HTTP 409 Conflict 반환

### 글로벌 제한  
- 최대 3개 동시 토글 실행
- HTTP 429 Too Many Requests 반환

## 🛠️ 유지보수

### 로그 확인

```bash
# API 서버 로그
journalctl -u dongle-toggle-api -f

# 시스템 로그
tail -f /home/proxy/backup_unnecessary/logs/push_status.log
```

### 서비스 재시작

```bash
# API 서버 재시작
sudo systemctl restart dongle-toggle-api

# SOCKS5 프록시 재시작 (필요시)
sudo pkill -f socks5_proxy.py
```

### 트러블슈팅

#### 동글이 인식되지 않는 경우
```bash
# USB 모드 확인 및 변경
sudo /home/proxy/backup/network-monitor/tools/switch_dongles.sh
```

#### 프록시 연결 실패
```bash
# 프록시 상태 확인
netstat -tln | grep 100[1-3][0-9]

# 개별 프록시 테스트
curl --socks5 127.0.0.1:10011 -s http://techb.kr/ip.php
```

## 📁 디렉토리 구조

```
/home/proxy/
├── scripts/                 # 핵심 스크립트
│   ├── toggle_api.js       # Toggle API 서버
│   ├── toggle_dongle.py    # 동글 토글 스크립트
│   ├── socks5_proxy.py     # SOCKS5 프록시 서버
│   └── push_proxy_status.sh # 상태 전송 스크립트
├── config/                 # 설정 파일
├── install.sh             # 설치 스크립트
├── CLAUDE.md              # 프로젝트 가이드 (내부용)
└── README.md              # 사용자 매뉴얼 (이 파일)
```

## 🔐 보안 고려사항

- Huawei API 인증 정보는 환경변수 또는 별도 설정 파일에 저장
- 외부 접근이 필요한 경우 방화벽 규칙 적절히 설정
- 로그 파일 크기 및 보관 기간 관리

## 🤝 기여

이슈 보고나 개선 제안은 GitHub Issues를 통해 해주세요.

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.

## 📞 지원

- GitHub Issues: [https://github.com/service0427/dongle/issues](https://github.com/service0427/dongle/issues)
- 문서: CLAUDE.md (내부 참조용)