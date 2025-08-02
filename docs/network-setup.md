# 네트워크 설정 문서

## 라우팅 테이블 (/etc/iproute2/rt_tables)

동글별 라우팅 테이블 정의:
```
111 dongle11
112 dongle12
113 dongle13
114 dongle14
115 dongle15
116 dongle16
117 dongle17
118 dongle18
119 dongle19
```

## 정책 기반 라우팅 규칙

### 1. 소스 기반 라우팅
- `from 192.168.11.0/24 lookup dongle11`
- 각 동글 서브넷에서 발생한 트래픽은 해당 동글 테이블 사용

### 2. 인터페이스 기반 라우팅
- `from all iif enp0s21f0u3u4u4 lookup dongle11`
- 특정 인터페이스로 들어온 트래픽은 해당 테이블 사용

### 3. 마크 기반 라우팅
- `from all fwmark 0xb lookup dongle11`
- iptables mangle 테이블에서 마킹된 패킷 라우팅

## 방화벽 규칙 (iptables)

### NAT 설정
```bash
# 각 동글 인터페이스에 대한 MASQUERADE
iptables -t nat -A POSTROUTING -o enp0s21f0u3u4u4 -j MASQUERADE
```

### IP 포워딩
```bash
# /etc/sysctl.conf
net.ipv4.ip_forward = 1
```

## NetworkManager 설정

### 메트릭 고정 (권장)
```bash
# /etc/NetworkManager/system-connections/dongle11.nmconnection
[ipv4]
method=auto
route-metric=211
```

## 복구 방법

### 라우팅 테이블 복구
```bash
sudo cp /home/proxy/network-monitor/backup/rt_tables.backup /etc/iproute2/rt_tables
```

### 방화벽 규칙 복구
```bash
sudo iptables-restore < /home/proxy/network-monitor/backup/iptables_*.rules
```

### 전체 라우팅 재설정
```bash
sudo /home/proxy/network-monitor/scripts/setup_dongle_routing.sh
```