# 네트워크 핑거프린팅 및 감지 기술

## 네, 이런 것들도 감지 가능합니다!

웹사이트와 보안 시스템은 다양한 방법으로 사용자의 실제 디바이스 타입과 네트워크 환경을 감지할 수 있습니다:

## 1. TTL (Time To Live) 감지
네트워크 패킷의 TTL 값은 OS별로 다릅니다:
- **Windows**: 128
- **Linux/Mac**: 64  
- **iOS/Android**: 64

많은 CDN과 보안 서비스가 이를 체크합니다.

## 2. TCP 핑거프린팅
TCP 연결 시 다양한 특성을 분석:
- **MSS (Maximum Segment Size)**
  - 모바일: 1400 (낮은 값)
  - PC: 1460 (이더넷 표준)
- **Window Size**: 초기 윈도우 크기
- **TCP Options**: 타임스탬프, SACK 등의 옵션

## 3. TLS 핑거프린팅 (JA3)
HTTPS 연결 시 TLS handshake 패턴 분석:
- Cipher suites 순서
- TLS extensions
- 지원 프로토콜 버전

각 브라우저/앱마다 고유한 패턴이 있습니다.

## 4. HTTP 헤더 분석
- **User-Agent**: 브라우저/디바이스 정보
- **Accept headers**: 지원 형식
- **헤더 순서**: 브라우저별로 다름

## 5. JavaScript 핑거프린팅
- Canvas fingerprinting
- WebGL 렌더링 차이
- 폰트 목록
- 화면 해상도
- 터치 이벤트 지원

## 6. 네트워크 특성
- **IP 대역**: 모바일 ISP vs 일반 ISP
- **DNS 서버**: 통신사 DNS vs 공용 DNS
- **지연시간 패턴**: 모바일은 더 높고 불규칙

## 7. 프록시 감지
- X-Forwarded-For, Via 헤더
- 열린 프록시 포트
- IP 평판 데이터베이스
- WebRTC IP 누출

## 우리 시스템의 대응

### PC 모드 설정
```bash
- TTL: 128 (Windows처럼)
- TCP MSS: 1460 (이더넷)
- TCP 옵션: PC 특성
```

### 모바일 모드 설정
```bash
- TTL: 64 (모바일)
- TCP MSS: 1400 (모바일 네트워크)
- TCP 옵션: 모바일 특성
```

### 프록시 은폐
- 프록시 헤더 제거
- 직접 연결처럼 보이도록
- KT 모바일 IP 사용

## 참고
완벽한 위장은 어렵습니다. 정교한 감지 시스템은 여러 요소를 종합적으로 분석하기 때문입니다. 하지만 우리 시스템은 가장 일반적인 감지 방법들을 우회할 수 있도록 설계되었습니다.