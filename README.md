# Network Monitor - Huawei 동글 자동화 시스템

Rocky Linux 9.6에서 Huawei E8372h USB 동글들을 자동으로 관리하고 프록시 서비스를 제공하는 시스템입니다.

## 주요 기능

### 1. 자동 네트워크 설정
- 동글 연결 시 자동으로 라우팅 설정
- DNS 충돌 방지 (`chattr +i /etc/resolv.conf`)
- 메트릭 자동 관리 (eno1: 0, 동글: 200+)

### 2. 동적 SOCKS5 프록시
- 동글 연결/해제 시 자동으로 포트 활성화/비활성화
- 포트: 10011-10030 (10000 + 동글 서브넷)
- 실시간 동글 감지 (5초 간격)

### 3. API 서비스
- 상태 확인: `GET /status`
- 연결 확인: `GET /connectivity`
- IP 변경: `GET /toggle/:subnet`
- 프록시 정보: `GET /proxy-info`
- 데이터 사용량: `GET /data-usage`

### 4. 모니터링
- 일일 데이터 사용량 추적
- 속도 제한 자동 감지 (2GB 이상)
- 실시간 트래픽 모니터링

## 설치

```bash
cd /home/proxy/network-monitor
sudo ./install.sh
```

## 시스템 구성

### 핵심 컴포넌트
- **NetworkManager 디스패처**: 동글 이벤트 처리
- **동적 SOCKS5 서버**: 실시간 프록시 관리
- **Health Check API**: 상태 모니터링 (포트 8080)

### 서비스
- `dongle-socks5.service` - 동적 프록시 서버
- `network-monitor-health.service` - API 서버
- `proxy-stealth-pc.service` - PC 모드 네트워크 설정

## 사용법

### 프록시 접속
```javascript
// Playwright 예제
const browser = await chromium.launch({
    proxy: { server: 'socks5://112.161.54.7:10011' }
});
```

### IP 변경
```bash
curl http://112.161.54.7:8080/toggle/11
```

### 상태 확인
```bash
curl http://112.161.54.7:8080/status
```

## 디렉토리 구조
```
/home/proxy/network-monitor/
├── scripts/           # 핵심 스크립트
├── docs/             # 문서
├── config/           # 설정 파일
├── logs/             # 로그 파일
├── data/             # 데이터 파일
└── archive/          # 아카이브된 파일
```

## 문제 해결

### 로그 확인
```bash
journalctl -u dongle-socks5 -f
journalctl -u network-monitor-health -f
tail -f /home/proxy/network-monitor/logs/*.log
```

### 서비스 재시작
```bash
systemctl restart dongle-socks5
systemctl restart network-monitor-health
```

## 주의사항
- Rocky Linux 9.6 전용
- root 권한 필요
- 방화벽에서 포트 8080, 10011-10030 열려있어야 함