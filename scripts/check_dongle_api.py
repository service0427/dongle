#!/usr/bin/env python3

import sys
import json
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection
from huawei_lte_api.exceptions import LoginError

def check_dongle(port):
    """특정 포트의 동글 상태를 확인"""
    modem_ip = f'192.168.{port}.1'
    username = 'admin'
    password = 'KdjLch!@7024'
    
    result = {
        'port': port,
        'ip': modem_ip,
        'status': 'unknown',
        'details': {}
    }
    
    try:
        # 연결 URL 생성
        connection_url = f'http://{username}:{password}@{modem_ip}'
        
        with Connection(connection_url) as connection:
            client = Client(connection)
            
            # 로그인 상태 확인
            try:
                login_state = client.user.state_login()
                result['details']['login_state'] = login_state.get('State', 'unknown')
            except:
                result['details']['login_state'] = 'error'
            
            # 디바이스 정보
            try:
                device_info = client.device.information()
                result['details']['device_name'] = device_info.get('DeviceName', 'unknown')
                result['details']['imei'] = device_info.get('Imei', 'unknown')
            except:
                pass
            
            # 모니터링 상태
            try:
                status = client.monitoring.status()
                result['details']['connection_status'] = status.get('ConnectionStatus', 'unknown')
                result['details']['network_type'] = status.get('CurrentNetworkType', 'unknown')
                result['details']['signal_icon'] = status.get('SignalIcon', 'unknown')
                
                # 연결 상태 해석
                conn_status = status.get('ConnectionStatus')
                if conn_status == '901':
                    result['status'] = 'connected'
                elif conn_status == '902':
                    result['status'] = 'disconnected'
                else:
                    result['status'] = f'status_{conn_status}'
            except:
                pass
            
            # SIM 상태
            try:
                check_notif = client.monitoring.check_notifications()
                result['details']['sim_state'] = check_notif.get('SIMState', 'unknown')
            except:
                pass
            
            # 트래픽 통계
            try:
                traffic = client.monitoring.traffic_statistics()
                result['details']['total_upload'] = traffic.get('TotalUpload', 'unknown')
                result['details']['total_download'] = traffic.get('TotalDownload', 'unknown')
            except:
                pass
                
    except LoginError as e:
        result['status'] = 'login_error'
        result['error'] = str(e)
    except Exception as e:
        result['status'] = 'error'
        result['error'] = str(e)
    
    return result

def main():
    if len(sys.argv) > 1:
        # 특정 포트만 체크
        port = int(sys.argv[1])
        result = check_dongle(port)
        print(json.dumps(result, indent=2))
    else:
        # 모든 동글 체크
        results = []
        for port in range(11, 20):
            print(f"Checking dongle {port}...", file=sys.stderr)
            result = check_dongle(port)
            results.append(result)
        
        print(json.dumps(results, indent=2))

if __name__ == "__main__":
    main()