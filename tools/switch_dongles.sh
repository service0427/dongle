#!/bin/bash

echo "=== Huawei E8372h 동글 모드 전환 ==="
echo "Mass storage mode에서 네트워크 모드로 전환합니다..."
echo

# Mass storage mode (12d1:1f01)에 있는 모든 동글 찾기
for device in $(lsusb | grep "12d1:1f01" | awk '{print $2":"$4}' | sed 's/:$//'); do
    bus=$(echo $device | cut -d: -f1)
    dev=$(echo $device | cut -d: -f2)
    
    echo "동글 발견: Bus $bus Device $dev"
    
    # usb_modeswitch로 모드 전환
    usb_modeswitch -v 12d1 -p 1f01 -P 14db -b $bus -g $dev -M "55534243123456780000000000000a11062000000000000100000000000000"
    
    echo "모드 전환 시도 완료"
    echo
done

echo "5초 후 상태를 확인합니다..."
sleep 5

echo
echo "=== 현재 USB 장치 상태 ==="
lsusb | grep "12d1" | grep -E "(14db|1f01)"