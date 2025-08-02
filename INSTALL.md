# Network Monitor 설치 가이드

## 설치 순서

### 1. 시스템 초기 설정 (새 서버에서만 필요)

새로운 Rocky Linux 9.6 서버에서는 먼저 시스템 초기 설정을 실행합니다:

```bash
cd /home/proxy/network-monitor
sudo ./system_initial_setup.sh
```

이 스크립트는 다음을 수행합니다:
- 시간대 설정 (Asia/Seoul)
- EPEL/Remi 저장소 설정
- 시스템 패키지 업데이트
- 필수 패키지 설치 (net-tools, usbutils, vim 등)
- Node.js 23.x 및 PM2 설치
- GRUB 부팅 메뉴 숨김 설정
- 네트워크 초기 설정:
  - eno1 메트릭을 0으로 설정
  - DNS 고정 (168.126.63.1, 8.8.8.8, 8.8.4.4)
  - 라우팅 테이블 설정
  - IP 포워딩 활성화
  - NetworkManager DNS 관리 비활성화
- USB 모드 스위치 도구 설치
- Python 및 Huawei LTE API 라이브러리 설치

### 2. Network Monitor 설치

시스템 초기 설정이 완료되면 Network Monitor를 설치합니다:

```bash
cd /home/proxy/network-monitor
sudo ./install.sh
```

### 3. 시스템 재부팅

설치 완료 후 시스템을 재부팅합니다:

```bash
sudo reboot
```

## 설치 확인

재부팅 후 다음 명령으로 서비스 상태를 확인합니다:

```bash
# 서비스 상태 확인
sudo systemctl status network-monitor
sudo systemctl status network-monitor-health

# 동글 상태 확인
/home/proxy/network-monitor/tools/check_dongles.sh

# 헬스체크 API 확인
curl http://localhost:8080/status
```

## 주의사항

1. **DNS 설정**: `/etc/resolv.conf`가 immutable로 설정되어 있습니다. 변경이 필요한 경우:
   ```bash
   sudo chattr -i /etc/resolv.conf
   # 수정 후
   sudo chattr +i /etc/resolv.conf
   ```

2. **메트릭 설정**: eno1의 메트릭은 0으로 고정되어 있어 항상 최우선 순위를 가집니다.

3. **로그 확인**: 문제 발생 시 로그를 확인하세요:
   ```bash
   tail -f /home/proxy/network-monitor/logs/monitor.log
   tail -f /home/proxy/network-monitor/logs/startup.log
   ```