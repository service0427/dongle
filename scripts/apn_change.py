#!/usr/bin/env python3
"""
Huawei E8372h APN 프로파일 관리 스크립트

기능:
- APN 프로파일 목록 조회
- 활성 APN 확인
- APN 프로파일 변경 (향후 추가)

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


class APNManager:
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

            # 로그인 (필요시)
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

    def get_profiles(self):
        """APN 프로파일 목록 조회"""
        if not self.client:
            if not self.connect():
                return None

        try:
            # 프로파일 목록 조회
            profiles = self.client.dial_up.profiles()
            return profiles

        except Exception as e:
            print(f"Error: Failed to get profiles: {e}")
            return None

    def get_current_profile(self):
        """현재 활성 프로파일 조회"""
        if not self.client:
            if not self.connect():
                return None

        try:
            # 모바일 데이터 스위치 상태에서 현재 프로파일 확인
            mobile_status = self.client.dial_up.mobile_dataswitch()
            return mobile_status

        except Exception as e:
            print(f"Error: Failed to get current profile: {e}")
            return None

    def set_default_profile(self, profile_index):
        """기본 프로파일 설정 (Index로)"""
        if not self.client:
            if not self.connect():
                return False

        try:
            # 프로파일 인덱스로 기본값 설정
            result = self.client.dial_up.set_default_profile(profile_index)
            return True

        except Exception as e:
            print(f"Error: Failed to set default profile: {e}")
            return False

    def set_default_profile_by_name(self, profile_name):
        """기본 프로파일 설정 (이름으로 검색)"""
        # 먼저 프로파일 목록 조회
        profiles = self.get_profiles()
        if not profiles:
            print(f"Error: Failed to get profiles")
            return False

        # 프로파일 리스트 추출
        profile_list = profiles.get('Profiles', {}).get('Profile', [])
        if not isinstance(profile_list, list):
            profile_list = [profile_list]

        # 이름으로 프로파일 검색 (대소문자 무시)
        target_profile = None
        for profile in profile_list:
            name = profile.get('Name', profile.get('ProfileName', ''))
            if name.lower() == profile_name.lower():
                target_profile = profile
                break

        if not target_profile:
            print(f"Error: Profile '{profile_name}' not found")
            print(f"Available profiles:")
            for profile in profile_list:
                name = profile.get('Name', profile.get('ProfileName', 'Unknown'))
                index = profile.get('Index', 'N/A')
                print(f"  - {name} (Index: {index})")
            return False

        # 찾은 프로파일의 Index로 기본값 설정
        profile_index = target_profile.get('Index')
        print(f"Found profile '{profile_name}' with Index {profile_index}")
        print(f"Setting as default profile...")

        return self.set_default_profile(profile_index)

    def display_profiles(self, profiles):
        """프로파일 목록을 보기 좋게 출력"""
        if not profiles:
            print("No profiles found")
            return

        # 현재 기본 프로파일 추출
        current_profile = profiles.get('CurrentProfile', None)

        # XML 응답 파싱
        if hasattr(profiles, 'get'):
            # dict 형태
            profile_list = profiles.get('Profiles', {}).get('Profile', [])
        else:
            # XML 객체
            try:
                import xml.etree.ElementTree as ET
                if isinstance(profiles, str):
                    root = ET.fromstring(profiles)
                else:
                    root = profiles

                # CurrentProfile 추출
                current_elem = root.find('.//CurrentProfile')
                if current_elem is not None:
                    current_profile = current_elem.text

                profile_list = []
                for profile in root.findall('.//Profile'):
                    profile_data = {}
                    for child in profile:
                        profile_data[child.tag] = child.text
                    profile_list.append(profile_data)
            except:
                print("Raw response:")
                print(profiles)
                return

        # 단일 프로파일인 경우 리스트로 변환
        if not isinstance(profile_list, list):
            profile_list = [profile_list]

        print(f"\n{'='*80}")
        print(f"APN Profiles for Dongle {self.subnet} (IP: {self.ip})")
        print(f"{'='*80}\n")

        if current_profile:
            print(f"Current Default Profile: Index {current_profile}\n")

        for idx, profile in enumerate(profile_list, 1):
            profile_index = profile.get('Index', 'N/A')
            is_default = (profile_index == current_profile)

            default_marker = " [DEFAULT]" if is_default else ""
            print(f"Profile #{idx}{default_marker}")
            print(f"  Index:       {profile_index}")
            print(f"  Name:        {profile.get('Name', profile.get('ProfileName', 'N/A'))}")
            print(f"  APN:         {profile.get('ApnName', 'N/A')}")
            print(f"  Username:    {profile.get('Username', 'N/A') or '(none)'}")
            print(f"  Password:    {'***' if profile.get('Password') else '(none)'}")
            print(f"  Auth Mode:   {profile.get('AuthMode', 'N/A')}")
            print(f"  IP Type:     {profile.get('iptype', profile.get('IpType', 'N/A'))}")
            print(f"  Read Only:   {profile.get('ReadOnly', 'N/A')}")
            print(f"  Is Valid:    {profile.get('IsValid', 'N/A')}")
            print(f"  -{'-'*76}")

        print(f"\nTotal: {len(profile_list)} profile(s)\n")

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
        description='Huawei E8372h APN Profile Manager - Auto KT Setup',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 16            # Auto-check and set KT as default if needed
  %(prog)s 16 --json     # Output in JSON format
        """
    )

    parser.add_argument('subnet', type=int,
                       help='Dongle subnet number (e.g., 16, 17, 18)')
    parser.add_argument('--json', action='store_true',
                       help='Output in JSON format')

    args = parser.parse_args()

    # APN 관리자 생성
    manager = APNManager(args.subnet)

    try:
        # 프로파일 목록 조회
        profiles = manager.get_profiles()

        if profiles is None:
            return 1

        # JSON 출력 모드
        if args.json:
            print(json.dumps(profiles, indent=2, default=str))
            return 0

        # 현재 기본 프로파일 확인
        current_profile = profiles.get('CurrentProfile', None)
        profile_list = profiles.get('Profiles', {}).get('Profile', [])
        if not isinstance(profile_list, list):
            profile_list = [profile_list]

        # KT 프로파일 찾기
        kt_profile = None
        current_profile_name = None

        for profile in profile_list:
            profile_index = profile.get('Index')
            profile_name = profile.get('Name', profile.get('ProfileName', ''))

            # 현재 기본 프로파일의 이름
            if profile_index == current_profile:
                current_profile_name = profile_name

            # KT 프로파일 찾기
            if profile_name.lower() == 'kt':
                kt_profile = profile

        # KT 프로파일이 없으면 경고
        if not kt_profile:
            print(f"\nWarning: 'KT' profile not found on dongle {args.subnet}")
            manager.display_profiles(profiles)
            return 1

        kt_index = kt_profile.get('Index')

        # KT가 이미 기본값인지 확인
        if current_profile == kt_index:
            print(f"\n✓ Dongle {args.subnet}: KT profile is already the default")
            manager.display_profiles(profiles)
            return 0

        # KT가 기본값이 아니면 변경
        print(f"\n! Dongle {args.subnet}: Current default is '{current_profile_name}' (Index {current_profile})")
        print(f"  Changing to 'KT' (Index {kt_index})...")

        success = manager.set_default_profile(kt_index)

        if success:
            print(f"\n✓ Success! KT profile is now the default.\n")
            # 변경 후 상태 확인
            profiles = manager.get_profiles()
            if profiles:
                manager.display_profiles(profiles)
            return 0
        else:
            print(f"\n✗ Failed to set KT as default")
            return 1

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
