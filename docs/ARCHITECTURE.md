# System Architecture

## 개요
이 시스템은 NetworkManager 이벤트 기반으로 동작하며, 동글 연결/해제를 자동으로 감지하여 네트워크 설정과 프록시 서비스를 관리합니다.

## 주요 컴포넌트

### 1. NetworkManager Dispatcher
**위치**: `/etc/NetworkManager/dispatcher.d/`
- `50-dongle-up`: 동글 연결 이벤트 처리
- `60-dongle-down`: 동글 해제 이벤트 처리

**동작 흐름**:
1. USB 동글 연결 감지
2. DHCP로 IP 할당 대기 (최대 30초)
3. 라우팅 테이블 설정 (ip rule/route)
4. NAT 설정 (iptables MASQUERADE)
5. APN 확인 및 수정 (KT 전용)

### 2. 동적 SOCKS5 프록시 서버
**스크립트**: `dongle_socks5_dynamic.py`
**서비스**: `dongle-socks5.service`

**특징**:
- 5초마다 동글 상태 확인
- 자동 포트 할당 (10000 + subnet)
- 동글별 독립적인 프록시 스레드

### 3. Health Check API
**스크립트**: `health_check.js`
**서비스**: `network-monitor-health.service`
**포트**: 8080

**기능**:
- 시스템 상태 모니터링
- 연결 상태 확인
- IP 토글 기능
- 데이터 사용량 추적

## 네트워크 구성

### IP 할당
- 메인 인터페이스: DHCP (112.161.54.7)
- 동글: 192.168.X.100 (X: 11-30)

### 라우팅
```
# 메인 테이블
default via <gateway> dev eno1 metric 0

# 동글별 테이블 (예: table 11)
default via 192.168.11.1 dev enp0s21f0u3u4u4
192.168.11.0/24 dev enp0s21f0u3u4u4

# IP 규칙
from 192.168.11.100 lookup dongle11
```

### DNS 보호
```bash
chattr +i /etc/resolv.conf
```

## 데이터 흐름

### 외부 → 프록시 → 인터넷
1. 클라이언트 → SOCKS5 (포트 10011)
2. 프록시 서버가 요청 수신
3. 동글 IP(192.168.11.100)로 바인드
4. 라우팅 테이블 11을 통해 전송
5. NAT를 거쳐 인터넷으로

### IP 토글 프로세스
1. API 요청 수신 (/toggle/11)
2. 프로세스 락 확인
3. Huawei API로 연결 해제
4. 15초 대기
5. 재연결 및 새 IP 할당

## 보안 설정

### 네트워크 핑거프린팅 회피
- TTL: 128 (Windows PC)
- TCP MSS: 1460 (Ethernet)
- 프록시 헤더 제거

### 접근 제어
- 방화벽: 포트 8080, 10011-10030
- 프록시: 인증 없음 (내부용)

## 모니터링

### 로그 위치
- `/home/proxy/network-monitor/logs/`
- systemd journal

### 주요 메트릭
- 동글별 연결 상태
- 데이터 사용량
- API 응답 시간
- 프록시 연결 수