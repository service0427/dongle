#!/usr/bin/env python3
"""
화웨이 API를 통한 동글 재부팅
API 실패시 자동으로 허브 포트 재부팅으로 전환
"""
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection
import time
import sys
import json
import subprocess

# 설정
USERNAME = "admin"
PASSWORD = "KdjLch!@7024"
TIMEOUT = 5
CONFIG_FILE = "/home/proxy/config/dongle_config.json"

def reboot_via_hub(subnet):
    """허브 포트를 통한 동글 재부팅"""
    try:
        # dongle_config.json에서 인터페이스 정보 읽기
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)

        interface_mapping = config.get('interface_mapping', {})
        dongle_info = interface_mapping.get(str(subnet))

        if not dongle_info:
            print(f"동글 {subnet}의 인터페이스 정보를 찾을 수 없습니다")
            return False

        interface = dongle_info.get('interface')
        if not interface:
            print(f"인터페이스 정보가 없습니다")
            return False

        # 인터페이스에서 USB 경로 추출
        usb_path_cmd = f"readlink -f /sys/class/net/{interface}/device 2>/dev/null | grep -oE '[0-9]+-[0-9]+(\.[0-9]+)*' | tail -1"
        result = subprocess.run(usb_path_cmd, shell=True, capture_output=True, text=True, timeout=5)

        if result.returncode != 0 or not result.stdout.strip():
            print(f"USB 경로를 찾을 수 없습니다")
            return False

        usb_path = result.stdout.strip()

        # USB 경로에서 uhubctl 허브와 포트 분리
        # 예: "1-2.4.3" -> hub="1-2.4", port="3"
        if '.' not in usb_path:
            print(f"올바르지 않은 USB 경로 형식: {usb_path}")
            return False

        parts = usb_path.rsplit('.', 1)
        hub = parts[0]
        port = parts[1]

        gateway = dongle_info.get('gateway', f'192.168.{subnet}.1')

        print(f"USB 경로: {usb_path}")
        print(f"허브 포트 재부팅 시도: Hub {hub}, Port {port}")
        print(f"Gateway: {gateway}")

        # uhubctl로 포트 끄기
        cmd_off = f"sudo uhubctl -l {hub} -p {port} -a off"
        result = subprocess.run(cmd_off, shell=True, capture_output=True, text=True, timeout=10)

        if result.returncode != 0:
            print(f"포트 끄기 실패: {result.stderr}")
            return False

        print(f"포트 OFF 완료")

        # 1초 대기 후 ping 체크 시작
        time.sleep(1)
        print(f"동글 전원 차단 확인 중...")

        consecutive_fails = 0
        max_checks = 20

        for i in range(max_checks):
            # ping 체크 (timeout 1초)
            ping_result = subprocess.run(
                f"ping -c 1 -W 1 {gateway}",
                shell=True,
                capture_output=True,
                text=True,
                timeout=2
            )

            if ping_result.returncode != 0:
                consecutive_fails += 1
                print(f"  [{i+1}초] ping 실패 ({consecutive_fails}/3)")

                if consecutive_fails >= 3:
                    print(f"✓ 동글 전원 차단 확인됨 (연속 3회 실패)")
                    break
            else:
                consecutive_fails = 0
                print(f"  [{i+1}초] 아직 응답 중...")

            time.sleep(1)

        if consecutive_fails < 3:
            print(f"⚠ 20초 경과, 강제 진행")

        # uhubctl로 포트 켜기
        cmd_on = f"sudo uhubctl -l {hub} -p {port} -a on"
        result = subprocess.run(cmd_on, shell=True, capture_output=True, text=True, timeout=10)

        if result.returncode != 0:
            print(f"포트 켜기 실패: {result.stderr}")
            return False

        print(f"\n포트 ON 완료, 동글 부팅 대기 중... (5초)")
        time.sleep(5)

        # 부팅 확인
        ping_result = subprocess.run(
            f"ping -c 1 -W 2 {gateway}",
            shell=True,
            capture_output=True,
            text=True,
            timeout=3
        )

        if ping_result.returncode == 0:
            print(f"✓ 동글 재부팅 완료! ({gateway} 응답 확인)")
            return True
        else:
            print(f"⚠ 동글이 아직 부팅 중입니다. 30-60초 정도 더 기다려주세요.")
            return True

    except Exception as e:
        print(f"허브 포트 재부팅 실패: {e}")
        return False

def reboot_dongle_api(subnet):
    """API를 통한 동글 재부팅"""
    try:
        url = f'http://192.168.{subnet}.1/'
        connection = Connection(url, username=USERNAME, password=PASSWORD, timeout=TIMEOUT)

        # Already login 처리
        try:
            client = Client(connection)
        except Exception as e:
            if "Already login" in str(e):
                # 로그아웃 시도
                import requests
                logout_url = f'{url}api/user/logout'
                logout_data = '<?xml version="1.0" encoding="UTF-8"?><request><Logout>1</Logout></request>'
                try:
                    requests.post(logout_url, data=logout_data,
                                headers={'Content-Type': 'application/xml'}, timeout=2)
                except:
                    pass
                time.sleep(1)
                # 재연결
                connection = Connection(url, username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
                client = Client(connection)
            else:
                raise

        # 재부팅 명령
        result = client.device.reboot()

        # 응답 확인 (빈 응답이거나 OK가 아니면 실패로 간주)
        if not result or result == {} or ('OK' not in str(result) and result != 'OK'):
            print(f"API 재부팅 응답 이상: {result}")
            return False

        print(f"API 재부팅 명령 성공")
        print(f"응답: {result}")
        return True

    except Exception as e:
        print(f"API 재부팅 실패: {e}")
        return False

def reboot_dongle(subnet):
    """동글 재부팅 (API 시도 후 실패시 허브 포트로 전환)"""
    print(f"\n{'='*60}")
    print(f"동글 {subnet} 재부팅 시작")
    print(f"{'='*60}\n")

    # 1단계: API 재부팅 시도
    print("[1단계] API 재부팅 시도...")
    api_success = reboot_dongle_api(subnet)

    if api_success:
        print(f"\n약 30-60초 후 동글이 재시작됩니다.")
        print(f"{'='*60}\n")
        return True

    # 2단계: 허브 포트 재부팅으로 전환
    print(f"\n[2단계] API 재부팅 실패, 허브 포트 재부팅으로 전환...\n")
    hub_success = reboot_via_hub(subnet)

    if hub_success:
        print(f"{'='*60}\n")
        return True
    else:
        print(f"\n{'='*60}")
        print(f"모든 재부팅 방법 실패")
        print(f"{'='*60}\n")
        return False

# 실행
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("사용법: python3 reboot_dongle.py [동글번호]")
        print("예시: python3 reboot_dongle.py 27")
        sys.exit(1)

    subnet = int(sys.argv[1])

    # 즉시 재부팅
    success = reboot_dongle(subnet)
    if success:
        print("\n재부팅 후 상태 확인:")
        print(f"  python3 /home/proxy/scripts/check_sim_status.py {subnet}")
    else:
        sys.exit(1)
