# 외부에서 프록시 사용 가이드

## 프록시 접속 정보

- **서버**: 112.161.54.7
- **포트**: 
  - 동글 11: 10011
  - 동글 16: 10016
- **타입**: SOCKS5 (인증 없음)

## 사용 가능한 API

### 1. 프록시 목록 확인
```bash
curl http://112.161.54.7:8080/proxy-info
```

### 2. IP 변경 (토글)
```bash
# 동글 11 IP 변경
curl http://112.161.54.7:8080/toggle/11

# 동글 16 IP 변경  
curl http://112.161.54.7:8080/toggle/16
```

### 3. 연결 상태 확인
```bash
curl http://112.161.54.7:8080/connectivity
```

## Playwright 예제

```javascript
const { chromium } = require('playwright');

(async () => {
    // 브라우저 실행 (프록시 설정)
    const browser = await chromium.launch({
        proxy: {
            server: 'socks5://112.161.54.7:10011'  // 동글 11 사용
        }
    });

    // 컨텍스트 생성
    const context = await browser.newContext({
        // PC 모드로 설정됨
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        viewport: { width: 1920, height: 1080 },
        locale: 'ko-KR',
        timezoneId: 'Asia/Seoul'
    });

    // 페이지 생성 및 이동
    const page = await context.newPage();
    
    // IP 확인
    await page.goto('https://ipinfo.io/json');
    const ipInfo = await page.textContent('body');
    console.log('Current IP:', JSON.parse(ipInfo));

    // 원하는 사이트 방문
    await page.goto('https://example.com');
    
    await browser.close();
})();
```

## Python requests 예제

```python
import requests

# 프록시 설정
proxies = {
    'http': 'socks5://112.161.54.7:10011',
    'https': 'socks5://112.161.54.7:10011'
}

# IP 확인
response = requests.get('https://ipinfo.io/json', proxies=proxies)
print(f"Current IP: {response.json()['ip']}")

# 일반 요청
response = requests.get('https://example.com', proxies=proxies)
print(f"Status: {response.status_code}")
```

## 모드 전환

현재 PC 모드로 설정되어 있습니다:
- TTL: 128 (Windows)
- TCP MSS: 1460 (이더넷)

## 주의사항

1. **봇 감지**: 네이버/쿠팡 등은 프로그래밍 방식 요청을 감지할 수 있습니다
2. **브라우저 권장**: 감지 회피를 위해 Playwright/Selenium 사용 권장
3. **IP 토글**: 15초 쿨다운이 있습니다
4. **동시 사용**: 여러 동글을 동시에 사용 가능합니다