# Windows 11에서 WireGuard + Playwright 설정

## 1단계: WireGuard 설치
1. https://www.wireguard.com/install/ → "Windows Installer" 다운로드
2. 관리자 권한으로 설치

## 2단계: VPN 설정
1. WireGuard 앱 실행
2. "Add Tunnel" → "Add empty tunnel..." 클릭
3. 아래 설정 붙여넣기:

```ini
[Interface]
PrivateKey = qCBVTzrK4uZSt/TJE2hiQozmLhi79Fxu0Ms34eQHfHc=
Address = 10.8.0.2/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = xTCiN8kF6ZP5MsLhD6afft83nikZwXWo/7nnoOO1vFg=
Endpoint = 112.161.54.7:51820
AllowedIPs = 223.130.195.0/24
PersistentKeepalive = 25
```

4. "Save" → "Activate" 클릭
5. 테스트: 브라우저에서 google.com, naver.com 모두 정상 접속되는지 확인

## 3단계: Playwright 사용
```javascript
const { chromium } = require('playwright');

async function main() {
    // 프록시 설정 불필요! VPN이 자동 처리
    const browser = await chromium.launch();
    
    const context = await browser.newContext({
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        locale: 'ko-KR'
    });

    const page = await context.newPage();
    
    await page.goto('https://www.naver.com'); // 동글 16 사용
    await page.goto('https://www.google.com'); // 기존 연결 사용
    
    await browser.close();
}

main();
```

**핵심**: 네이버만 VPN 사용, 나머지 사이트는 기존 연결 유지