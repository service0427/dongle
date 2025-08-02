# OS 핑거프린팅 감지 및 대응

## 네, Ubuntu도 감지됩니다!

각 OS는 고유한 네트워크 특성을 가지고 있어 원격에서 감지 가능합니다:

## OS별 특징

### Windows (7/10/11)
- **TTL**: 128
- **TCP Window Size**: 65535
- **TCP MSS**: 1460
- **TCP Options**: 특정 순서와 값

### Ubuntu/Debian Linux
- **TTL**: 64
- **TCP Window Size**: 29200 (Ubuntu 기본값)
- **TCP MSS**: 1460
- **TCP Congestion Control**: cubic (기본)
- **TCP Timestamps**: 활성화
- **/proc/sys 설정값**: Ubuntu 특유의 네트워크 튜닝

### macOS
- **TTL**: 64
- **TCP Window Size**: 65535
- **TCP MSS**: 1460
- **TCP Options**: macOS 특유 패턴

### Android/iOS (모바일)
- **TTL**: 64
- **TCP MSS**: 1400 이하 (모바일 네트워크)
- **TCP Window**: 작은 초기값
- **User-Agent**: 모바일 특유

## 감지 도구들

### 1. Nmap OS Detection
```bash
nmap -O target_ip
```
TCP/IP 스택 특성으로 OS 추측

### 2. p0f (Passive OS Fingerprinting)
연결만으로 OS 감지:
- SYN 패킷 분석
- TCP 옵션 순서
- Window size

### 3. 웹 서비스 감지
- TLS fingerprinting (JA3)
- HTTP 헤더 패턴
- JavaScript navigator 객체

## 우리 시스템의 대응

### Ubuntu 모드 추가
```bash
# Ubuntu 22.04/24.04처럼 보이기
/home/proxy/network-monitor/scripts/switch_proxy_mode.sh ubuntu
```

특징:
- TTL: 64 (Linux 기본)
- TCP MSS: 1460 (이더넷)
- TCP Congestion: cubic
- Ubuntu 기본 네트워크 파라미터

### 사용 가능한 모드들
1. **mobile** - 모바일 기기
2. **pc** - Windows PC
3. **ubuntu** - Ubuntu Desktop

## 중요 포인트

1. **OS 감지는 매우 정확함**
   - 단순 User-Agent 변경으로는 부족
   - TCP/IP 레벨 특성이 중요

2. **일관성이 핵심**
   - User-Agent와 TCP 특성이 일치해야 함
   - 예: Ubuntu User-Agent + Windows TTL = 의심

3. **추가 감지 요소**
   - 시간대 설정
   - 언어 설정
   - 설치된 플러그인
   - Canvas fingerprinting

## 권장사항

Playwright 사용 시:
```javascript
// Ubuntu로 위장
const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0',
    locale: 'ko-KR',
    timezoneId: 'Asia/Seoul'
});
```

네트워크 레벨에서도 Ubuntu로 설정하면 더 완벽한 위장이 됩니다.