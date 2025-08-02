# Playwright 외부 연결 가이드

이 문서는 외부 서버의 Playwright에서 이 프록시 시스템을 사용하는 방법을 설명합니다.

## 시스템 정보
- **프록시 서버 IP**: 112.161.54.7
- **사용 가능한 서비스**:
  1. SOCKS5 프록시 (동글별)
  2. WireGuard VPN

## 방법 1: SOCKS5 프록시 사용 (권장)

### 프록시 정보 확인
```bash
curl http://112.161.54.7:8080/proxy-info
```

### Playwright 설정
```javascript
const { chromium } = require('playwright');

async function main() {
    // 동글 11 사용 (포트 10011)
    const browser = await chromium.launch({
        proxy: {
            server: 'socks5://112.161.54.7:10011'
        }
    });

    const context = await browser.newContext({
        // PC로 위장 (현재 설정)
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        viewport: { width: 1920, height: 1080 },
        locale: 'ko-KR',
        timezoneId: 'Asia/Seoul'
    });

    const page = await context.newPage();
    
    // IP 확인
    await page.goto('https://ipinfo.io/json');
    const ipInfo = await page.textContent('body');
    console.log('현재 IP:', JSON.parse(ipInfo));
    
    // 실제 사용
    await page.goto('https://www.coupang.com');
    
    await browser.close();
}

main();
```

### 동글별 포트
- 동글 11: `socks5://112.161.54.7:10011`
- 동글 16: `socks5://112.161.54.7:10016`
- 동글 17: `socks5://112.161.54.7:10017`
- (패턴: 10000 + 동글 번호)

### IP 변경 (토글)
특정 동글의 IP를 변경하려면:
```javascript
// 동글 11 IP 변경
const response = await fetch('http://112.161.54.7:8080/toggle/11');
const result = await response.json();
console.log('새 IP:', result.newIP);

// 15초 쿨다운 있음
```

## 방법 2: WireGuard VPN 사용

### WireGuard 클라이언트 설정
```ini
[Interface]
PrivateKey = qCBVTzrK4uZSt/TJE2hiQozmLhi79Fxu0Ms34eQHfHc=
Address = 10.8.0.2/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = xTCiN8kF6ZP5MsLhD6afft83nikZwXWo/7nnoOO1vFg=
Endpoint = 112.161.54.7:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### Linux에서 WireGuard 연결
```bash
# WireGuard 설치
sudo apt install wireguard

# 설정 파일 생성
sudo nano /etc/wireguard/wg0.conf
# 위 설정 붙여넣기

# 연결
sudo wg-quick up wg0

# 이후 Playwright는 프록시 설정 없이 사용
```

## 동시 사용 예제 (여러 동글)

```javascript
const { chromium } = require('playwright');

async function multiDongleTest() {
    // 동글 11로 브라우저 1
    const browser1 = await chromium.launch({
        proxy: { server: 'socks5://112.161.54.7:10011' }
    });
    
    // 동글 16으로 브라우저 2
    const browser2 = await chromium.launch({
        proxy: { server: 'socks5://112.161.54.7:10016' }
    });
    
    // 각각 다른 IP로 작업
    const page1 = await browser1.newPage();
    const page2 = await browser2.newPage();
    
    // 동시 작업...
    
    await browser1.close();
    await browser2.close();
}
```

## API 엔드포인트

### 상태 확인
```javascript
// 전체 시스템 상태
fetch('http://112.161.54.7:8080/status')

// 연결 상태
fetch('http://112.161.54.7:8080/connectivity')

// 데이터 사용량
fetch('http://112.161.54.7:8080/data-usage')
```

## 주의사항

1. **동시 연결 제한**: 사이트별로 4-6개 이하 권장
2. **User-Agent 일치**: 프록시 설정과 브라우저 설정 일치 필요
3. **속도 제한**: 일 2GB 이상 사용 시 속도 저하 가능
4. **IP 토글 쿨다운**: 15초

## 트러블슈팅

### 연결 안 됨
1. 프록시 상태 확인: `curl http://112.161.54.7:8080/proxy-info`
2. 해당 동글 활성 상태 확인

### 느린 속도
1. 데이터 사용량 확인: `curl http://112.161.54.7:8080/data-usage`
2. 다른 동글로 전환

### 차단됨
1. 동시 연결 수 줄이기
2. 요청 간 딜레이 추가
3. IP 토글 후 재시도