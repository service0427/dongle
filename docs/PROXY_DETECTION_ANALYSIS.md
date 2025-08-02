# 프록시 감지 분석: 네이버/쿠팡

## 테스트 결과

### requests 라이브러리 (프로그래밍 방식)
- **네이버**: ❌ 차단됨 ('robot' 감지)
- **쿠팡**: ❌ 타임아웃 (연결 거부)
- **네이버쇼핑**: ❌ 차단됨

### 실제 차이점: Squid vs SOCKS5

## 1. 프로토콜 레벨 차이

### Squid (HTTP/HTTPS Proxy)
- HTTP 헤더 수정 가능
- Via, X-Forwarded-For 헤더 추가
- HTTP 레벨에서 동작
- 캐싱 기능

### SOCKS5 (우리 시스템)
- TCP/IP 레벨에서 동작
- HTTP 헤더 건드리지 않음
- 더 투명한 연결
- 프록시임을 숨기기 더 어려움

## 2. 감지 방법들

### 네이버/쿠팡이 사용하는 감지 기술

1. **TLS Fingerprinting (JA3)**
   - requests: Python 라이브러리 특유의 TLS 패턴
   - 브라우저: 실제 Chrome/Firefox 패턴

2. **HTTP/2 지원**
   - requests: 기본적으로 HTTP/1.1
   - 브라우저: HTTP/2 사용

3. **JavaScript 실행**
   - requests: JavaScript 실행 불가
   - 브라우저: 정상 실행

4. **행동 패턴**
   - 마우스 움직임 없음
   - 스크롤 없음
   - 쿠키 처리 미흡

5. **Canvas Fingerprinting**
   - JavaScript로 그래픽 렌더링 테스트
   - 각 디바이스마다 미세한 차이

## 3. Squid에서 문제없었던 이유

1. **캐싱 프록시로 인식**
   - 기업/학교에서 흔히 사용
   - 정상적인 사용 케이스

2. **오래된 감지 시스템**
   - 예전에는 단순 IP/User-Agent 체크
   - 최근 더 정교해짐

3. **HTTP 프록시의 일반성**
   - 널리 사용되는 표준
   - 차단하면 정상 사용자도 영향

## 4. 해결 방법

### 1단계: 브라우저 자동화 사용
```python
# Playwright/Selenium 사용
# 실제 브라우저 엔진으로 렌더링
```

### 2단계: Stealth 설정
```javascript
// 자동화 감지 회피
Object.defineProperty(navigator, 'webdriver', {
    get: () => undefined
});
```

### 3단계: 실제 사용자처럼 행동
- 랜덤 대기 시간
- 마우스 움직임 시뮬레이션
- 스크롤 동작
- 쿠키 유지

### 4단계: Residential Proxy 고려
- 데이터센터 IP가 아닌 실제 가정용 IP
- 하지만 우리는 이미 KT 모바일 IP 사용 중

## 5. 결론

1. **프로그래밍 방식 요청은 쉽게 감지됨**
   - TLS/HTTP 패턴이 다름
   - JavaScript 실행 불가

2. **SOCKS5는 투명하지만 그래서 더 의심받을 수 있음**
   - 일반 사용자는 SOCKS5 잘 안 씀
   - VPN처럼 보일 수 있음

3. **해결책: 실제 브라우저 사용**
   - Playwright/Puppeteer 권장
   - Stealth 플러그인 필수
   - 느리지만 확실함

4. **대안: API 사용**
   - 공식 API가 있다면 활용
   - 크롤링보다 안정적