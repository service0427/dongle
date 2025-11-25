# Scripts Directory - 실제 사용 파일만

## 📁 구조 (6개 파일만)

```
/home/proxy/scripts/
├── toggle_api.js              # HTTP API 서버 (포트 80)
├── smart_toggle.py            # 지능형 복구 (toggle_api.js가 내부 호출)
├── restart_all_hubs.sh        # USB 허브 전체 재시작
├── reboot_dongle.py           # 동글 완전 재부팅
├── apn_change.py              # APN을 KT로 변경
└── push_proxy_status.sh       # 메인 서버 상태 보고
```

## 🚀 사용법

### 1. 초기 설정 (필수 3개)
```bash
cd /home/proxy
sudo ./install.sh              # 시스템 설치
sudo ./init_dongle_config.sh   # 동글 초기 설정
sudo ./firewall.sh             # 방화벽 설정
```

### 2. 토글 (IP 변경)
```bash
# API 호출
curl https://112.161.54.7/toggle/18

# 내부적으로 smart_toggle.py 자동 실행됨
```

### 3. APN 변경 (KT로)
```bash
# 동글 업데이트 후 APN이 auto로 바뀔 때
python3 /home/proxy/scripts/apn_change.py 18
```

### 4. 동글 복구 (1-2개 해제 시)
```bash
# USB 허브 전체 재시작
/home/proxy/scripts/restart_all_hubs.sh
```

### 5. 동글 재부팅 (완전 먹통 시)
```bash
# 동글 완전 재부팅
python3 /home/proxy/scripts/reboot_dongle.py 18
```

### 6. 상태 보고
```bash
# 메인 서버에 상태 전송 (크론으로 자동 실행)
/home/proxy/scripts/push_proxy_status.sh
```

## 📋 크론 설정

```bash
# 상태 보고 (매분)
* * * * * /home/proxy/scripts/push_proxy_status.sh >/dev/null 2>&1

# 허브 체크 (10분마다)
*/10 * * * * /home/proxy/scripts/restart_all_hubs.sh >> /home/proxy/logs/usb_hub_check.log 2>&1
```

## 🎯 실제 동작 흐름

```
1. GitHub 크론으로 자동 업데이트
   ↓
2. install.sh → init_dongle_config.sh → firewall.sh
   ↓
3. toggle_api.js 실행 (systemd)
   ↓
4. 토글 요청: https://112.161.54.7/toggle/18
   ↓
5. toggle_api.js → smart_toggle.py 호출
   ↓
6. 필요시 수동 복구:
   - APN 변경: apn_change.py
   - 허브 재시작: restart_all_hubs.sh
   - 동글 재부팅: reboot_dongle.py
```

## 📦 나머지 파일들

모든 테스트, 모니터링, 최적화 파일은 삭제되었습니다.
**실제 사용하는 6개 파일만 남았습니다.**
