# Playwright에서 WireGuard VPN 사용 가이드

외부 서버의 Playwright에서 이 시스템의 WireGuard VPN을 통해 네이버 접속하는 방법입니다.

## 시스템 정보
- **WireGuard 서버**: 112.161.54.7:51820
- **VPN 네트워크**: 10.8.0.0/24
- **안전한 부분 터널링**: 네이버만 VPN 사용, 나머지 인터넷은 기존 연결 유지

## WireGuard 클라이언트 설정

### 1. WireGuard 설치

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install wireguard
```

**CentOS/RHEL:**
```bash
sudo dnf install wireguard-tools
```

**Windows/Mac:**
- [WireGuard 공식 사이트](https://www.wireguard.com/install/)에서 앱 다운로드

### 2. 클라이언트 설정 파일 생성

`/etc/wireguard/wg0.conf` (Linux) 또는 앱에 추가:

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

### 3. VPN 연결

**Linux:**
```bash
# 연결
sudo wg-quick up wg0

# 상태 확인
sudo wg show

# 연결 해제
sudo wg-quick down wg0
```

**Windows/Mac:**
- WireGuard 앱에서 터널 활성화

## Playwright 사용법

### 1. 기본 사용 (프록시 설정 불필요)

```javascript
const { chromium } = require('playwright');

async function main() {
    // WireGuard 연결 후에는 프록시 설정 불필요
    const browser = await chromium.launch();
    
    const context = await browser.newContext({
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        viewport: { width: 1920, height: 1080 },
        locale: 'ko-KR',
        timezoneId: 'Asia/Seoul'
    });

    const page = await context.newPage();
    
    // 네이버 접속 (자동으로 동글 16 통해 접속됨)
    await page.goto('https://www.naver.com');
    console.log('네이버 접속 완료');
    
    // 다른 사이트는 일반 연결 사용
    await page.goto('https://www.google.com');
    console.log('구글 접속 완료');
    
    await browser.close();
}

main();
```

### 2. IP 확인

```javascript
const { chromium } = require('playwright');

async function checkIP() {
    const browser = await chromium.launch();
    const page = await browser.newPage();
    
    // 네이버로 접속하여 IP 확인 (동글 16 사용)
    await page.goto('https://search.naver.com/search.naver?query=내+아이피');
    await page.waitForTimeout(2000);
    
    console.log('네이버에서 확인한 IP (동글 16)');
    
    // 구글로 접속하여 IP 확인 (일반 연결 사용)
    await page.goto('https://whatismyipaddress.com/');
    await page.waitForTimeout(2000);
    
    console.log('구글에서 확인한 IP (일반 연결)');
    
    await browser.close();
}

checkIP();
```

## 네트워크 라우팅 확인

VPN 연결 후 라우팅 확인:

```bash
# 라우팅 테이블 확인
ip route

# 네이버 IP 확인
nslookup www.naver.com

# 핑 테스트
ping www.naver.com
ping www.google.com
```

## 트러블슈팅

### 1. VPN 연결 안 됨
```bash
# 방화벽 확인
sudo ufw status
sudo firewall-cmd --list-ports

# WireGuard 로그 확인
sudo journalctl -u wg-quick@wg0 -f
```

### 2. 네이버만 다른 IP로 나가는지 확인
```bash
# 네이버 IP 범위 확인
dig www.naver.com

# 라우팅 규칙 확인
ip rule show
```

### 3. 연결은 되지만 인터넷 안 됨
- DNS 설정 확인: `cat /etc/resolv.conf`
- 방화벽 설정 확인
- 서버 측 포트포워딩 확인

## 장점

1. **투명성**: Playwright 코드에서 프록시 설정 불필요
2. **안정성**: SOCKS5보다 안정적인 연결
3. **자동 라우팅**: 네이버만 동글 16 사용, 나머지는 일반 연결
4. **암호화**: 모든 트래픽 암호화
5. **HTTP/3 지원**: 네이버의 HTTP/3 요청도 정상 처리

## 주의사항

- 한 번에 하나의 클라이언트만 연결 가능 (현재 설정)
- 네이버 접속 시에만 동글 16 사용됨
- VPN 연결 시 모든 트래픽이 서버를 거쳐감