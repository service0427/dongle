#!/usr/bin/env python3
"""
동글 APN 정보 확인 스크립트
"""

import sys
import json
import logging
from typing import Dict, List, Optional
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection

# 설정
USERNAME = 'admin'
PASSWORD = 'KdjLch!@7024'

# 로거 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def check_dongle_apn(subnet: int) -> Dict:
    """특정 동글의 APN 정보 확인"""
    modem_ip = f'192.168.{subnet}.1'
    connection_url = f'http://{USERNAME}:{PASSWORD}@{modem_ip}'
    
    result = {
        'subnet': subnet,
        'connected': False,
        'apn_info': None,
        'error': None
    }
    
    try:
        with Connection(connection_url) as connection:
            client = Client(connection)
            
            # 연결 상태 확인
            device_info = client.device.information()
            result['connected'] = True
            
            # APN 프로필 정보
            apn_list = client.dial_up.profiles()
            
            # 현재 사용 중인 프로필
            connection_info = client.dial_up.connection()
            
            current_profile = None
            if 'Profiles' in apn_list and 'Profile' in apn_list['Profiles']:
                profiles = apn_list['Profiles']['Profile']
                # 단일 프로필이면 리스트로 변환
                if not isinstance(profiles, list):
                    profiles = [profiles]
                
                # 현재 사용 중인 프로필 찾기
                for profile in profiles:
                    if profile.get('IsDefault') == '1' or profile.get('Index') == connection_info.get('CurrentProfile'):
                        current_profile = profile
                        break
                
                # 기본 프로필이 없으면 첫 번째 프로필 사용
                if not current_profile and profiles:
                    current_profile = profiles[0]
            
            if current_profile:
                result['apn_info'] = {
                    'name': current_profile.get('Name', ''),
                    'apn': current_profile.get('ApnName', ''),
                    'username': current_profile.get('Username', ''),
                    'auth_mode': current_profile.get('AuthMode', ''),
                    'ip_type': current_profile.get('IpType', ''),
                    'is_default': current_profile.get('IsDefault', '0') == '1'
                }
            
            # 추가 네트워크 정보
            net_info = client.net.current_plmn()
            signal_info = client.device.signal()
            
            result['network_info'] = {
                'operator': net_info.get('FullName', ''),
                'network_type': net_info.get('Rat', ''),
                'signal_strength': signal_info.get('rsrp', '')
            }
            
    except Exception as e:
        result['error'] = str(e)
        logger.error(f"동글{subnet} APN 확인 실패: {e}")
    
    return result

def check_all_dongles() -> List[Dict]:
    """모든 연결된 동글의 APN 확인"""
    results = []
    
    # 11-30번 동글 확인
    for subnet in range(11, 31):
        # 먼저 인터페이스가 있는지 확인
        import subprocess
        check_cmd = f"ip addr show | grep -q '192.168.{subnet}.100'"
        if subprocess.run(check_cmd, shell=True).returncode == 0:
            logger.info(f"동글{subnet} 확인 중...")
            result = check_dongle_apn(subnet)
            results.append(result)
    
    return results

def main():
    """메인 함수"""
    if len(sys.argv) > 1:
        # 특정 동글 확인
        try:
            subnet = int(sys.argv[1])
            if subnet < 11 or subnet > 30:
                print("Subnet must be between 11 and 30")
                sys.exit(1)
            
            result = check_dongle_apn(subnet)
            print(json.dumps(result, indent=2, ensure_ascii=False))
        except ValueError:
            print("Invalid subnet number")
            sys.exit(1)
    else:
        # 모든 동글 확인
        results = check_all_dongles()
        print(json.dumps(results, indent=2, ensure_ascii=False))

if __name__ == '__main__':
    main()