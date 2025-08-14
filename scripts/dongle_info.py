#!/usr/bin/env python3
"""
동글 정보 수집 및 트래픽 리셋 모듈
- 트래픽 통계 조회 및 리셋
- APN 정보 확인
- 네트워크 상태 조회
- 디바이스 정보 수집
"""

import sys
import json
import time
import subprocess
from datetime import datetime, timezone, timedelta
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection

# 설정
USERNAME = 'admin'
PASSWORD = 'KdjLch!@7024'
TIMEOUT = 10

def get_connected_dongles():
    """연결된 동글 서브넷 목록 반환"""
    connected = []
    for subnet in range(11, 31):
        try:
            result = subprocess.run(
                f"ping -c 1 -W 1 192.168.{subnet}.1",
                shell=True,
                capture_output=True,
                timeout=2
            )
            if result.returncode == 0:
                connected.append(subnet)
        except:
            continue
    return connected

def get_dongle_info(subnet, include_reset=False):
    """동글 종합 정보 수집"""
    modem_ip = f"192.168.{subnet}.1"
    
    result = {
        'subnet': subnet,
        'ip': f"192.168.{subnet}.100",
        'modem_ip': modem_ip,
        'status': 'disconnected',
        'error': None,
        'timestamp': datetime.now().isoformat()
    }
    
    try:
        connection = Connection(f'http://{modem_ip}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
        
        # Already login 에러 처리
        try:
            client = Client(connection)
        except Exception as e:
            if "Already login" in str(e):
                # 로그아웃 후 재연결
                try:
                    import requests
                    logout_url = f'http://{modem_ip}/api/user/logout'
                    logout_data = '<?xml version="1.0" encoding="UTF-8"?><request><Logout>1</Logout></request>'
                    requests.post(logout_url, data=logout_data, headers={'Content-Type': 'application/xml'}, timeout=2)
                    time.sleep(1)
                except:
                    pass
                connection = Connection(f'http://{modem_ip}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
                client = Client(connection)
            else:
                raise
        
        result['status'] = 'connected'
        
        # 트래픽 통계
        try:
            traffic_stats = client.monitoring.traffic_statistics()
            upload_bytes = int(traffic_stats.get('TotalUpload', 0))
            download_bytes = int(traffic_stats.get('TotalDownload', 0))
            
            result['traffic'] = {
                'upload_bytes': upload_bytes,
                'download_bytes': download_bytes,
                'total_bytes': upload_bytes + download_bytes,
                'upload_gb': round(upload_bytes / (1024**3), 2),
                'download_gb': round(download_bytes / (1024**3), 2),
                'total_gb': round((upload_bytes + download_bytes) / (1024**3), 2)
            }
        except Exception as e:
            result['traffic'] = {'error': str(e)}
        
        # APN 정보
        try:
            profiles = client.dialup.profiles()
            if isinstance(profiles, dict) and 'Profiles' in profiles:
                profile_list = profiles['Profiles']['Profile']
                if not isinstance(profile_list, list):
                    profile_list = [profile_list]
                
                # 현재 사용 중인 프로파일 찾기
                current_profile = None
                for profile in profile_list:
                    if profile.get('IsValid') == '1':
                        current_profile = profile
                        break
                
                if not current_profile and profile_list:
                    current_profile = profile_list[0]
                
                if current_profile:
                    result['apn'] = {
                        'name': current_profile.get('ApnName', 'Unknown'),
                        'profile_id': current_profile.get('ProfileId', 'Unknown'),
                        'auth_type': current_profile.get('AuthType', 'Unknown'),
                        'username': current_profile.get('Username', ''),
                        'ip_type': current_profile.get('IpType', 'Unknown'),
                        'is_valid': current_profile.get('IsValid', '0') == '1'
                    }
                else:
                    result['apn'] = {'error': 'No valid profile found'}
            else:
                result['apn'] = {'error': 'Invalid profiles response'}
        except Exception as e:
            result['apn'] = {'error': str(e)}
        
        # 네트워크 정보
        try:
            network_info = client.net.current_network()
            signal_info = client.device.signal()
            
            result['network'] = {
                'operator': network_info.get('FullName', 'Unknown'),
                'short_name': network_info.get('ShortName', 'Unknown'),
                'network_type': network_info.get('CurrentNetworkType', 'Unknown'),
                'roaming': network_info.get('RoamingStatus', '0') == '1'
            }
            
            # 신호 강도
            result['signal'] = {
                'rssi': signal_info.get('rssi', 'Unknown'),
                'rsrp': signal_info.get('rsrp', 'Unknown'),
                'rsrq': signal_info.get('rsrq', 'Unknown'),
                'sinr': signal_info.get('sinr', 'Unknown')
            }
        except Exception as e:
            result['network'] = {'error': str(e)}
            result['signal'] = {'error': str(e)}
        
        # 디바이스 정보
        try:
            device_info = client.device.information()
            result['device'] = {
                'device_name': device_info.get('DeviceName', 'Unknown'),
                'serial_number': device_info.get('SerialNumber', 'Unknown'),
                'imei': device_info.get('Imei', 'Unknown'),
                'software_version': device_info.get('SoftwareVersion', 'Unknown'),
                'hardware_version': device_info.get('HardwareVersion', 'Unknown')
            }
        except Exception as e:
            result['device'] = {'error': str(e)}
        
        # 트래픽 리셋 (요청된 경우)
        if include_reset:
            try:
                old_traffic = result.get('traffic', {})
                
                # 트래픽 리셋 실행
                clear_result = client.monitoring.set_clear_traffic()
                time.sleep(3)  # 처리 대기
                
                # 리셋 후 확인
                new_stats = client.monitoring.traffic_statistics()
                new_upload = int(new_stats.get('TotalUpload', 0))
                new_download = int(new_stats.get('TotalDownload', 0))
                
                result['reset'] = {
                    'success': True,
                    'api_response': str(clear_result),
                    'old_traffic_gb': old_traffic.get('total_gb', 0),
                    'new_traffic_gb': round((new_upload + new_download) / (1024**3), 2),
                    'cleared': old_traffic.get('total_gb', 0) > round((new_upload + new_download) / (1024**3), 2)
                }
                
                # 업데이트된 트래픽 정보
                result['traffic'] = {
                    'upload_bytes': new_upload,
                    'download_bytes': new_download,
                    'total_bytes': new_upload + new_download,
                    'upload_gb': round(new_upload / (1024**3), 2),
                    'download_gb': round(new_download / (1024**3), 2),
                    'total_gb': round((new_upload + new_download) / (1024**3), 2)
                }
            except Exception as e:
                result['reset'] = {
                    'success': False,
                    'error': str(e)
                }
        
    except Exception as e:
        result['error'] = str(e)
    
    return result

def get_all_dongles_info(include_reset=False, subnet_filter=None):
    """모든 동글 정보 수집"""
    if subnet_filter:
        subnets = [int(s) for s in subnet_filter if s.isdigit()]
    else:
        subnets = get_connected_dongles()
    
    results = {
        'timestamp': datetime.now().isoformat(),
        'dongles': {},
        'summary': {
            'total_requested': len(subnets),
            'connected': 0,
            'total_traffic_gb': 0,
            'reset_attempted': include_reset,
            'reset_successful': 0 if include_reset else None
        }
    }
    
    for subnet in subnets:
        dongle_info = get_dongle_info(subnet, include_reset)
        results['dongles'][str(subnet)] = dongle_info
        
        if dongle_info['status'] == 'connected':
            results['summary']['connected'] += 1
            
            # 트래픽 합계 계산
            if 'traffic' in dongle_info and 'total_gb' in dongle_info['traffic']:
                results['summary']['total_traffic_gb'] += dongle_info['traffic']['total_gb']
            
            # 리셋 성공 카운트
            if include_reset and dongle_info.get('reset', {}).get('success'):
                results['summary']['reset_successful'] += 1
    
    results['summary']['total_traffic_gb'] = round(results['summary']['total_traffic_gb'], 2)
    
    return results

def main():
    if len(sys.argv) < 2:
        print("사용법: python3 dongle_info.py [info|reset] [subnet1,subnet2,...]")
        print("  info  - 동글 정보 조회")
        print("  reset - 트래픽 리셋 포함 정보 조회")
        print("  subnet 예시: 11,12,13 (생략시 모든 연결된 동글)")
        sys.exit(1)
    
    command = sys.argv[1].lower()
    subnet_filter = None
    
    if len(sys.argv) > 2:
        subnet_filter = sys.argv[2].split(',')
    
    include_reset = command == 'reset'
    
    try:
        results = get_all_dongles_info(include_reset, subnet_filter)
        print(json.dumps(results, indent=2, ensure_ascii=False))
    except KeyboardInterrupt:
        print("\n작업이 취소되었습니다.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(json.dumps({'error': str(e), 'timestamp': datetime.now().isoformat()}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()