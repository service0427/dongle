#!/usr/bin/env python3
"""
Huawei E8372h Mobile Network Searching 설정 관리 스크립트

기능:
- Preferred network mode 조회 및 변경 (Auto/3G only/4G only)
- Network search mode 조회 (Auto/Manual)
- 네트워크 모드 설정 표시

작성일: 2025-11-01
"""

import sys
import json
import argparse
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection

# 설정
USERNAME = "admin"
PASSWORD = "KdjLch!@7024"
TIMEOUT = 10
CONFIG_FILE = "/home/proxy/config/dongle_config.json"

# 네트워크 모드 매핑
NETWORK_MODE_MAP = {
    '00': 'Auto',
    '01': '2G only',
    '02': '3G only',
    '03': '4G only',
    '0201': '3G preferred',
    '0302': '4G preferred',
}

# CLI에서 사용할 모드 이름 -> 코드 매핑
MODE_NAME_TO_CODE = {
    'auto': '00',
    '3g': '02',
    '4g': '03',
}

SEARCH_MODE_MAP = {
    '0': 'Auto',
    '1': 'Manual',
}

BAND_MAP = {
    '3FFFFFFF': 'All bands',
    '800C5': 'LTE B1/B3/B5/B7/B8/B20',
}


class NetworkSearchingManager:
    def __init__(self, subnet):
        self.subnet = subnet
        self.ip = f"192.168.{subnet}.1"
        self.client = None

    def connect(self):
        """동글에 연결"""
        try:
            url = f"http://{self.ip}/"
            connection = Connection(url, timeout=TIMEOUT)
            self.client = Client(connection)

            # 로그인
            try:
                self.client.user.login(USERNAME, PASSWORD)
            except Exception as e:
                # 이미 로그인된 경우 무시
                if "already logged in" not in str(e).lower():
                    print(f"Warning: Login error: {e}")

            return True

        except Exception as e:
            print(f"Error: Failed to connect to {self.ip}: {e}")
            return False

    def get_net_mode(self):
        """네트워크 모드 조회"""
        if not self.client:
            if not self.connect():
                return None

        try:
            # 네트워크 모드 조회
            net_mode = self.client.net.net_mode()
            return net_mode

        except Exception as e:
            print(f"Error: Failed to get network mode: {e}")
            return None

    def set_network_mode(self, mode_code, network_band=None, lte_band=None):
        """네트워크 모드 설정"""
        if not self.client:
            if not self.connect():
                return False

        # 현재 설정 가져오기
        current = self.get_net_mode()
        if not current:
            print("Error: Failed to get current network mode")
            return False

        # 현재 밴드 설정 사용 (변경하지 않음)
        if network_band is None:
            network_band = current.get('NetworkBand', '3FFFFFFF')
        if lte_band is None:
            lte_band = current.get('LTEBand', '3FFFFFFF')

        try:
            # 네트워크 모드 설정
            # API 시그니처: set_net_mode(lteband, networkband, networkmode)
            result = self.client.net.set_net_mode(
                lte_band,
                network_band,
                mode_code
            )
            return True

        except Exception as e:
            print(f"Error: Failed to set network mode: {e}")
            return False

    def get_network_search_mode(self):
        """네트워크 검색 모드 조회"""
        if not self.client:
            if not self.connect():
                return None

        try:
            # 현재 등록 상태 조회
            register_info = self.client.net.register()
            return register_info

        except Exception as e:
            # 조회 실패 시 에러 메시지 출력하지 않음
            return None

    def set_network_search_mode(self, mode):
        """네트워크 검색 모드 설정"""
        if not self.client:
            if not self.connect():
                return False

        try:
            if mode == 'auto':
                # Auto 모드: mode=0, plmn="", rat=""
                result = self.client.net.set_register('0', '', '')
            elif mode == 'manual':
                # Manual 모드: mode=1, 현재 PLMN 고정
                # 현재 연결된 PLMN 정보 가져오기
                try:
                    current_plmn = self.client.net.current_plmn()
                    plmn = current_plmn.get('Numeric', '45008')  # KT
                    rat = current_plmn.get('Rat', '7')  # 4G
                except:
                    # 현재 PLMN 정보를 가져올 수 없으면 기본값 사용
                    plmn = '45008'  # KT
                    rat = '7'  # 4G

                result = self.client.net.set_register('1', plmn, rat)
            else:
                print(f"Error: Invalid mode '{mode}'")
                return False

            return True

        except Exception as e:
            print(f"Error: Failed to set network search mode: {e}")
            return False

    def display_network_settings(self, net_mode, plmn_info=None):
        """네트워크 설정을 보기 좋게 출력"""
        if not net_mode:
            print("No network mode information found")
            return

        print(f"\n{'='*80}")
        print(f"Mobile Network Searching for Dongle {self.subnet} (IP: {self.ip})")
        print(f"{'='*80}\n")

        # Preferred Network Mode
        network_mode = net_mode.get('NetworkMode', 'N/A')
        network_band = net_mode.get('NetworkBand', 'N/A')
        lte_band = net_mode.get('LTEBand', 'N/A')

        print(f"Preferred Network Mode:")
        print(f"  Mode:        {network_mode} ({NETWORK_MODE_MAP.get(network_mode, 'Unknown')})")
        print(f"  Network Band: {network_band}")
        print(f"  LTE Band:    {lte_band} ({BAND_MAP.get(lte_band, 'Custom')})")
        print()

        # Network Search Mode
        if plmn_info:
            mode = plmn_info.get('Mode', 'N/A')
            state = plmn_info.get('State', 'N/A')

            print(f"Network Search Mode:")
            mode_text = 'Auto' if mode == '0' else 'Manual' if mode == '1' else 'Unknown'
            print(f"  Mode:        {mode} ({mode_text})")
            print(f"  State:       {state}")

            # 현재 네트워크 정보
            plmn = plmn_info.get('Plmn', '')
            rat = plmn_info.get('Rat', '')
            if plmn or rat:
                print(f"  PLMN:        {plmn if plmn else 'Auto'}")
                rat_text = {'0': '2G', '2': '3G', '7': '4G'}.get(rat, 'Auto')
                print(f"  RAT:         {rat if rat else 'Auto'} ({rat_text})")

        print(f"\n{'='*80}\n")

    def disconnect(self):
        """연결 종료"""
        if self.client:
            try:
                self.client.user.logout()
            except:
                pass


def load_dongle_config():
    """동글 설정 로드"""
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error: Failed to load config: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(
        description='Huawei E8372h Mobile Network Searching Manager',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 16                        # Show network settings for dongle 16
  %(prog)s 16 --set-mode auto        # Set preferred network to Auto mode
  %(prog)s 16 --set-mode 4g          # Set preferred network to 4G only
  %(prog)s 16 --set-mode 3g          # Set preferred network to 3G only
  %(prog)s 16 --set-search auto      # Set network search to Auto mode
  %(prog)s 16 --set-search manual    # Set network search to Manual mode
  %(prog)s 16 --json                 # Output in JSON format
        """
    )

    parser.add_argument('subnet', type=int,
                       help='Dongle subnet number (e.g., 16, 17, 18)')
    parser.add_argument('--set-mode', type=str, metavar='MODE',
                       choices=['auto', '3g', '4g'],
                       help='Set preferred network mode (auto, 3g, 4g)')
    parser.add_argument('--set-search', type=str, metavar='MODE',
                       choices=['auto', 'manual'],
                       help='Set network search mode (auto, manual)')
    parser.add_argument('--json', action='store_true',
                       help='Output in JSON format')

    args = parser.parse_args()

    # 네트워크 검색 관리자 생성
    manager = NetworkSearchingManager(args.subnet)

    try:
        # 네트워크 검색 모드 변경
        if args.set_search:
            mode_text = 'Auto' if args.set_search == 'auto' else 'Manual'
            print(f"\nChanging network search mode to '{mode_text}'...")

            success = manager.set_network_search_mode(args.set_search)

            if success:
                print(f"✓ Success! Network search mode changed to '{mode_text}'")
                if args.set_search == 'auto':
                    print(f"  Note: Dongle is re-registering to network. This may take a few seconds.\n")

                # 변경 후 상태 확인
                import time
                time.sleep(5 if args.set_search == 'auto' else 2)

                try:
                    net_mode = manager.get_net_mode()
                    search_mode = manager.get_network_search_mode()
                    if net_mode:
                        manager.display_network_settings(net_mode, search_mode)
                except Exception as e:
                    print(f"Note: Verification skipped (dongle is still re-registering)")
                    print(f"      Please check status again in a few seconds.")
                return 0
            else:
                print(f"✗ Failed to change network search mode")
                return 1

        # 네트워크 모드 변경
        if args.set_mode:
            mode_code = MODE_NAME_TO_CODE[args.set_mode]
            mode_name = NETWORK_MODE_MAP[mode_code]

            print(f"\nChanging network mode to '{mode_name}' (code: {mode_code})...")

            success = manager.set_network_mode(mode_code)

            if success:
                print(f"✓ Success! Network mode changed to '{mode_name}'\n")

                # 변경 후 상태 확인
                import time
                time.sleep(2)  # 설정 적용 대기

                net_mode = manager.get_net_mode()
                search_mode = manager.get_network_search_mode()
                if net_mode:
                    manager.display_network_settings(net_mode, search_mode)
                return 0
            else:
                print(f"✗ Failed to change network mode")
                return 1

        # 네트워크 모드 조회
        net_mode = manager.get_net_mode()

        if net_mode is None:
            return 1

        # 네트워크 검색 모드 조회
        plmn_info = manager.get_network_search_mode()

        # JSON 출력 모드
        if args.json:
            output = {
                'net_mode': net_mode,
                'plmn_info': plmn_info
            }
            print(json.dumps(output, indent=2, default=str))
            return 0

        # 사람이 읽기 좋은 형식으로 출력
        manager.display_network_settings(net_mode, plmn_info)

        return 0

    except KeyboardInterrupt:
        print("\nInterrupted by user")
        return 130
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        manager.disconnect()


if __name__ == "__main__":
    sys.exit(main())
