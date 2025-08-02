# Huawei E8372h USB 모드 관련 참고사항

## 모드 전환 동작

Huawei E8372h 동글은 두 가지 모드로 작동합니다:
- **Mass Storage Mode** (12d1:1f01) - 초기 연결 시
- **Network Mode** (12d1:14db) - 네트워크 인터페이스로 작동

## 자동 전환

대부분의 경우:
1. 동글을 연결하면 Mass Storage Mode로 인식
2. 몇 초(보통 5-10초) 후 자동으로 Network Mode로 전환
3. 가끔 전환이 안 되면 재부팅으로 해결

## 수동 전환 방법

자동 전환이 실패한 경우:

```bash
# 1. 현재 상태 확인
lsusb | grep "12d1"

# 2. Mass storage mode 동글만 전환
sudo /home/proxy/network-monitor/tools/switch_dongles.sh

# 3. 특정 동글만 전환 (bus와 device 번호 확인 후)
sudo usb_modeswitch -v 12d1 -p 1f01 -P 14db -b [bus] -g [device]
```

## 문제 해결

1. **전환이 안 되는 경우**
   - 동글을 뺐다가 다시 연결
   - 다른 USB 포트에 연결
   - 시스템 재부팅

2. **반복적으로 Mass Storage Mode로 돌아가는 경우**
   - 동글 펌웨어 문제일 수 있음
   - Windows에서 Huawei Mobile Partner로 펌웨어 업데이트 시도

3. **udev 규칙 활성화**
   - 필요시 `/etc/udev/rules.d/40-huawei-modeswitch.rules` 파일의 주석 제거
   - `sudo udevadm control --reload-rules && sudo udevadm trigger`

## 참고

- 대부분의 경우 udev 규칙 없이도 자동 전환됨
- 강제 전환은 동글에 부담을 줄 수 있으므로 최후의 수단으로 사용