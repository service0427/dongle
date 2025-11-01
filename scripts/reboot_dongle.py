#!/usr/bin/env python3
"""
화웨이 API를 통한 동글 재부팅
"""
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection
import time
import sys

# 설정
USERNAME = "admin"
PASSWORD = "KdjLch!@7024"
TIMEOUT = 5

def reboot_dongle(subnet):
    """동글 재부팅"""
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

        print(f"\n{'='*60}")
        print(f"동글 {subnet} 재부팅 시작")
        print(f"{'='*60}\n")

        # 재부팅 명령
        try:
            result = client.device.reboot()
            print(f"재부팅 명령 전송 성공")
            print(f"응답: {result}")
            print(f"\n약 30-60초 후 동글이 재시작됩니다.")
            print(f"{'='*60}\n")
            return True
        except Exception as e:
            print(f"재부팅 명령 실패: {e}")
            print(f"{'='*60}\n")
            return False

    except Exception as e:
        print(f"\n{'='*60}")
        print(f"동글 {subnet} 연결 실패")
        print(f"오류: {str(e)}")
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
