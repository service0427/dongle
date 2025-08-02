# WireGuard VPN 설정 가이드

## 서버 상태
- **상태**: ✅ 실행 중
- **포트**: 51820/UDP
- **네트워크**: 10.8.0.1/24
- **자동 시작**: 활성화됨

## 클라이언트 설정

### Windows/Mac/Linux 클라이언트
1. WireGuard 앱 설치
2. 새 터널 추가
3. 아래 설정 붙여넣기:

```
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

### Android/iOS 클라이언트
1. WireGuard 앱 설치
2. QR 코드 스캔 또는 수동 입력
3. 위 설정 사용

## 특징

### 트래픽 라우팅
- **기본**: 메인 인터페이스(eno1) 사용
- **네이버(223.130.195.0/24)**: 동글 16 사용
- 나머지 트래픽: 일반 인터넷 연결

### 보안
- ChaCha20-Poly1305 암호화
- 완전한 터널링 (0.0.0.0/0)
- DNS 보호 (8.8.8.8)

## 관리 명령어

```bash
# 상태 확인
wg show

# 연결된 클라이언트 확인
wg show wg0 endpoints

# 트래픽 통계
wg show wg0 transfer

# 재시작
systemctl restart wg-quick@wg0

# 로그 확인
journalctl -u wg-quick@wg0 -f
```

## 다중 클라이언트 추가

새 클라이언트를 추가하려면:

```bash
# 새 키 생성
wg genkey | tee client2_private.key | wg pubkey > client2_public.key

# wg0.conf에 추가
[Peer]
PublicKey = <새_클라이언트_공개키>
AllowedIPs = 10.8.0.3/32

# WireGuard 재시작
wg-quick down wg0 && wg-quick up wg0
```

## 문제 해결

### 연결 안 됨
1. 방화벽 확인: `firewall-cmd --list-ports`
2. 서버 상태: `systemctl status wg-quick@wg0`
3. 로그 확인: `journalctl -u wg-quick@wg0`

### 느린 속도
1. MTU 조정: `ip link set mtu 1380 dev wg0`
2. 압축 비활성화 (클라이언트 설정)