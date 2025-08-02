#!/usr/bin/env python3
"""
동글 APN 설정 수정 스크립트
유심 재삽입 시 잘못된 APN이 선택되는 문제 해결
"""

import sys
import json
import logging
import time
from typing import Dict, Optional
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection

# 설정
USERNAME = 'admin'
PASSWORD = 'KdjLch!@7024'

# KT APN 설정
KT_APN_SETTINGS = {
    'name': 'KT',
    'apn': 'lte.ktfwing.com',
    'username': '',
    'password': '',
    'authmode': '2',  # 0=NONE, 1=PAP, 2=CHAP
    'iptype': '0'     # 0=IPv4, 1=IPv6, 2=IPv4&IPv6
}

# 로거 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class APNFixer:
    def __init__(self, subnet: int):
        self.subnet = subnet
        self.modem_ip = f'192.168.{subnet}.1'
        self.connection_url = f'http://{USERNAME}:{PASSWORD}@{self.modem_ip}'
        
    def verify_kt_network(self, client: Client) -> bool:
        """KT 네트워크인지 확인"""
        try:
            plmn = client.net.current_plmn()
            operator_name = plmn.get('FullName', '').upper()
            return 'KT' in operator_name
        except Exception as e:
            logger.error(f"Failed to verify network: {e}")
            return False
    
    def check_current_apn(self, client: Client) -> Dict:
        """현재 APN 설정 확인"""
        try:
            profiles = client.dial_up.profiles()
            
            # 현재 사용 중인 프로필 찾기
            if 'Profiles' in profiles and 'Profile' in profiles['Profiles']:
                profile_list = profiles['Profiles']['Profile']
                if not isinstance(profile_list, list):
                    profile_list = [profile_list]
                
                # Default가 1인 프로필 찾기
                for profile in profile_list:
                    if profile.get('IsDefault') == '1':
                        return {
                            'index': profile.get('Index'),
                            'name': profile.get('Name'),
                            'apn': profile.get('ApnName'),
                            'auth_mode': profile.get('AuthMode'),
                            'is_correct': False  # 나중에 검증
                        }
            
            return None
        except Exception as e:
            logger.error(f"Failed to check current APN: {e}")
            return None
    
    def create_correct_profile(self, client: Client) -> bool:
        """KT APN 프로필 생성"""
        try:
            settings = KT_APN_SETTINGS
            
            # 새 프로필 생성
            logger.info("Creating new KT APN profile")
            
            # 프로필 추가 시도
            client.dial_up.set_mobile_dataswitch(dataswitch='0')  # 데이터 끄기
            time.sleep(2)
            
            # 프로필 설정
            response = client.dial_up.set_profiles({
                'Profile': {
                    'Index': '1',  # 첫 번째 프로필로 설정
                    'IsDefault': '1',
                    'ProfileName': settings['name'],
                    'APN': settings['apn'],
                    'UserName': settings['username'],
                    'Password': settings['password'],
                    'AuthMode': settings['authmode'],
                    'IpType': settings['iptype']
                }
            })
            
            time.sleep(2)
            client.dial_up.set_mobile_dataswitch(dataswitch='1')  # 데이터 켜기
            
            logger.info("APN profile created successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to create APN profile: {e}")
            return False
    
    def set_default_profile(self, client: Client, profile_index: str) -> bool:
        """특정 프로필을 기본으로 설정"""
        try:
            logger.info(f"Setting profile {profile_index} as default")
            
            # 프로필을 기본으로 설정
            client.dial_up.set_default_profile(profile_index)
            
            # 연결 재시작
            client.dial_up.set_mobile_dataswitch(dataswitch='0')
            time.sleep(2)
            client.dial_up.set_mobile_dataswitch(dataswitch='1')
            
            return True
        except Exception as e:
            logger.error(f"Failed to set default profile: {e}")
            return False
    
    def fix_apn(self) -> Dict:
        """APN 설정 수정"""
        result = {
            'success': False,
            'subnet': self.subnet,
            'operator': None,
            'current_apn': None,
            'action': None,
            'error': None
        }
        
        try:
            with Connection(self.connection_url) as connection:
                client = Client(connection)
                
                # 1. KT 네트워크 확인
                if not self.verify_kt_network(client):
                    result['error'] = 'Not KT network'
                    logger.info("Not KT network, skipping APN fix")
                    return result
                
                result['operator'] = 'KT'
                logger.info("KT network verified")
                
                # 2. 현재 APN 확인
                current_apn = self.check_current_apn(client)
                if current_apn:
                    result['current_apn'] = current_apn['apn']
                    
                    # 올바른 APN인지 확인
                    correct_apn = KT_APN_SETTINGS['apn']
                    if current_apn['apn'] == correct_apn:
                        logger.info("APN is already correct")
                        result['success'] = True
                        result['action'] = 'no_change_needed'
                        return result
                
                # 3. 올바른 프로필 찾기 또는 생성
                profiles = client.dial_up.profiles()
                correct_profile_index = None
                
                if 'Profiles' in profiles and 'Profile' in profiles['Profiles']:
                    profile_list = profiles['Profiles']['Profile']
                    if not isinstance(profile_list, list):
                        profile_list = [profile_list]
                    
                    # 올바른 APN을 가진 프로필 찾기
                    correct_apn = KT_APN_SETTINGS['apn']
                    for profile in profile_list:
                        if profile.get('ApnName') == correct_apn:
                            correct_profile_index = profile.get('Index')
                            logger.info(f"Found correct profile at index {correct_profile_index}")
                            break
                
                # 4. 올바른 프로필이 없으면 생성
                if not correct_profile_index:
                    if self.create_correct_profile(client):
                        correct_profile_index = '1'
                        result['action'] = 'created_new_profile'
                    else:
                        result['error'] = 'Failed to create correct profile'
                        return result
                else:
                    # 올바른 프로필을 기본으로 설정
                    if self.set_default_profile(client, correct_profile_index):
                        result['action'] = 'set_correct_profile_as_default'
                    else:
                        result['error'] = 'Failed to set default profile'
                        return result
                
                result['success'] = True
                result['new_apn'] = KT_APN_SETTINGS['apn']
                
        except Exception as e:
            result['error'] = str(e)
            logger.error(f"APN fix failed: {e}")
        
        return result

def main():
    """메인 함수"""
    if len(sys.argv) != 2:
        print("Usage: fix_dongle_apn.py <subnet>")
        print("Example: fix_dongle_apn.py 11")
        sys.exit(1)
    
    try:
        subnet = int(sys.argv[1])
        if subnet < 11 or subnet > 30:
            print("Subnet must be between 11 and 30")
            sys.exit(1)
        
        fixer = APNFixer(subnet)
        result = fixer.fix_apn()
        
        print(json.dumps(result, indent=2, ensure_ascii=False))
        sys.exit(0 if result['success'] else 1)
        
    except ValueError:
        print("Invalid subnet number")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()