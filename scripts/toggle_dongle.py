#!/usr/bin/env python3
"""
동글 토글 스크립트 (원본 GitHub 버전)
네트워크 모드 변경 방식 사용
"""

import sys
import json
import time
import requests
from datetime import datetime, timezone, timedelta
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection

# 설정
USERNAME = 'admin'
PASSWORD = 'KdjLch!@7024'  # 원본 비밀번호
MAX_RETRIES = 3
TIMEOUT = 10
MAX_WAIT_TIME = 15

def get_current_ip(subnet):
    """현재 외부 IP 확인"""
    try:
        import subprocess
        # 인터페이스 이름 찾기
        result = subprocess.run(
            f"ip addr show | grep '192.168.{subnet}.100' | awk '{{print $NF}}'",
            shell=True,
            capture_output=True,
            text=True,
            timeout=2
        )
        interface = result.stdout.strip()
        
        if interface:
            # 인터페이스를 통해 직접 외부 IP 확인
            result = subprocess.run(
                f"curl --interface {interface} -s -m 3 http://techb.kr/ip.php 2>/dev/null | head -1",
                shell=True,
                capture_output=True,
                text=True,
                timeout=5
            )
            ip = result.stdout.strip()
            if ip and ip.split('.')[0].isdigit():
                return ip
        return None
    except:
        return None

def get_traffic_stats(client):
    """트래픽 통계 가져오기"""
    try:
        stats = client.monitoring.traffic_statistics()
        return {
            'upload': int(stats['TotalUpload']),
            'download': int(stats['TotalDownload'])
        }
    except:
        return None

def toggle_dongle(subnet):
    """동글 토글 실행 (네트워크 모드 변경 방식)"""
    # 한국 시간대 (UTC+9)
    kst = timezone(timedelta(hours=9))
    now = datetime.now(kst)
    result = {
        'success': False,
        'timestamp': now.strftime('%Y-%m-%d %H:%M:%S')
    }
    
    try:
        # 현재 IP 확인
        old_ip = get_current_ip(subnet)
        
        # Huawei API 연결
        modem_ip = f"192.168.{subnet}.1"
        connection = Connection(f'http://{modem_ip}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
        
        # Already login 에러 처리를 위한 재시도
        try:
            client = Client(connection)
        except Exception as e:
            if "Already login" in str(e):
                # 로그아웃 시도
                try:
                    import requests
                    logout_url = f'http://{modem_ip}/api/user/logout'
                    logout_data = '<?xml version="1.0" encoding="UTF-8"?><request><Logout>1</Logout></request>'
                    requests.post(logout_url, data=logout_data, headers={'Content-Type': 'application/xml'}, timeout=2)
                    time.sleep(1)
                except:
                    pass
                # 재연결 시도
                connection = Connection(f'http://{modem_ip}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
                client = Client(connection)
            else:
                raise
        
        # 현재 네트워크 모드 가져오기
        current_mode = client.net.net_mode()
        
        # AUTO 모드로 변경
        client.net.set_net_mode(
            networkmode='00',  # AUTO
            networkband=current_mode['NetworkBand'],
            lteband=current_mode['LTEBand']
        )
        
        time.sleep(3)
        
        # LTE 전용 모드로 변경
        client.net.set_net_mode(
            networkmode='03',  # LTE only
            networkband=current_mode['NetworkBand'],
            lteband=current_mode['LTEBand']
        )
        
        # IP 변경 대기
        for i in range(MAX_WAIT_TIME):
            time.sleep(1)
            new_ip = get_current_ip(subnet)
            if new_ip and new_ip != old_ip:
                result['ip'] = new_ip
                result['success'] = True
                
                # 트래픽 통계 가져오기
                traffic_stats = get_traffic_stats(client)
                if traffic_stats:
                    result['traffic'] = traffic_stats
                
                # connection.logout() - 메서드 없음
                return result
        
        # 시간 초과지만 IP 확인
        final_ip = get_current_ip(subnet)
        if final_ip:
            result['ip'] = final_ip
            result['success'] = True
            
            # 트래픽 통계 가져오기
            traffic_stats = get_traffic_stats(client)
            if traffic_stats:
                result['traffic'] = traffic_stats
        else:
            result['error'] = 'Failed to get IP after toggle'
        
        # connection.logout() - 메서드 없음
        
    except Exception as e:
        result['error'] = str(e)
    
    return result

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(json.dumps({'error': 'Usage: toggle_dongle.py <subnet>'}))
        sys.exit(1)
    
    try:
        subnet = int(sys.argv[1])
        if subnet < 11 or subnet > 30:
            raise ValueError('Subnet must be between 11 and 30')
            
        result = toggle_dongle(subnet)
        print(json.dumps(result))
        
    except Exception as e:
        print(json.dumps({'error': str(e)}))
        sys.exit(1)