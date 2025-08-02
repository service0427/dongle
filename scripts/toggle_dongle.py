#!/usr/bin/env python3
"""
동글 IP 변경을 위한 네트워크 토글 스크립트
"""

import sys
import json
import logging
import time
import requests
import os
import psutil
from typing import Dict, Optional
from datetime import datetime
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection
from huawei_lte_api.exceptions import LoginErrorUsernameWrongException, LoginErrorPasswordWrongException

# 설정
USERNAME = 'admin'
PASSWORD = 'KdjLch!@7024'
MAX_RETRIES = 3
TIMEOUT = 10
MAX_WAIT_TIME = 15
MIN_TOGGLE_INTERVAL = 15  # 최소 토글 간격 (초)
LAST_TOGGLE_FILE = '/tmp/dongle_last_toggle.json'
LOCK_FILE_PREFIX = '/tmp/dongle_toggle_'

# 로거 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DongleToggler:
    def __init__(self, subnet: int):
        self.subnet = subnet
        self.modem_ip = f'192.168.{subnet}.1'
        self.local_ip = f'192.168.{subnet}.100'
        self.connection_url = f'http://{USERNAME}:{PASSWORD}@{self.modem_ip}'
        self.lock_file = f'{LOCK_FILE_PREFIX}{subnet}.lock'
        
    def check_last_toggle_time(self) -> Optional[float]:
        """마지막 토글 시간 확인"""
        try:
            if os.path.exists(LAST_TOGGLE_FILE):
                with open(LAST_TOGGLE_FILE, 'r') as f:
                    data = json.load(f)
                    return data.get(str(self.subnet))
        except Exception:
            pass
        return None
    
    def save_toggle_time(self):
        """토글 시간 저장"""
        try:
            data = {}
            if os.path.exists(LAST_TOGGLE_FILE):
                with open(LAST_TOGGLE_FILE, 'r') as f:
                    data = json.load(f)
            
            data[str(self.subnet)] = time.time()
            
            with open(LAST_TOGGLE_FILE, 'w') as f:
                json.dump(data, f)
        except Exception as e:
            logger.error(f"토글 시간 저장 실패: {e}")
    
    def is_process_running(self, pid: int) -> bool:
        """프로세스가 실행 중인지 확인"""
        try:
            process = psutil.Process(pid)
            return process.is_running() and 'python' in process.name()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            return False
    
    def acquire_lock(self) -> bool:
        """프로세스 락 획득"""
        try:
            # 락 파일이 있는지 확인
            if os.path.exists(self.lock_file):
                with open(self.lock_file, 'r') as f:
                    pid = int(f.read().strip())
                
                # 프로세스가 실제로 실행 중인지 확인
                if self.is_process_running(pid):
                    logger.warning(f"Toggle already in progress for dongle{self.subnet} (PID: {pid})")
                    return False
                else:
                    # 죽은 프로세스의 락 파일 삭제
                    logger.info(f"Removing stale lock file for dongle{self.subnet}")
                    os.remove(self.lock_file)
            
            # 새 락 파일 생성
            with open(self.lock_file, 'w') as f:
                f.write(str(os.getpid()))
            return True
            
        except Exception as e:
            logger.error(f"Failed to acquire lock: {e}")
            return False
    
    def release_lock(self):
        """프로세스 락 해제"""
        try:
            if os.path.exists(self.lock_file):
                os.remove(self.lock_file)
        except Exception as e:
            logger.error(f"Failed to release lock: {e}")
        
    def check_current_ip(self) -> Optional[str]:
        """현재 외부 IP 확인"""
        try:
            # 여러 방법으로 IP 확인 시도
            commands = [
                f"curl --interface {self.local_ip} -k -s -m 5 http://ipinfo.io/ip",
                f"curl --interface {self.local_ip} -k -s -m 5 https://ipinfo.io/ip",
                "curl -s -m 5 http://ipinfo.io/ip",  # fallback to default route
                "curl -s -m 5 https://ipinfo.io/ip"   # fallback with https
            ]
            
            import subprocess
            for cmd in commands:
                try:
                    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
                    if result.returncode == 0 and result.stdout.strip():
                        ip = result.stdout.strip()
                        if ip and '.' in ip:  # basic IP validation
                            logger.info(f"IP 확인 성공: {ip} (명령어: {cmd})")
                            return ip
                except subprocess.TimeoutExpired:
                    logger.warning(f"IP 확인 타임아웃: {cmd}")
                    continue
                except Exception as e:
                    logger.warning(f"IP 확인 실패: {cmd}, 오류: {e}")
                    continue
                    
        except Exception as e:
            logger.error(f"IP 확인 전체 실패: {e}")
        return None
    
    def toggle_network_mode(self, client: Client) -> bool:
        """네트워크 모드 변경"""
        try:
            # 현재 모드 확인
            current_mode = client.net.net_mode()
            logger.info(f"현재 네트워크 모드: {current_mode}")
            
            # 자동 모드로 변경
            logger.info("자동 모드로 변경 중...")
            client.net.set_net_mode(
                networkmode='00',  # AUTO
                networkband=current_mode['NetworkBand'],
                lteband=current_mode['LTEBand']
            )
            
            time.sleep(2)
            
            # LTE 모드로 변경
            logger.info("LTE 모드로 변경 중...")
            client.net.set_net_mode(
                networkmode='03',  # LTE only
                networkband=current_mode['NetworkBand'],
                lteband=current_mode['LTEBand']
            )
            
            return True
        except Exception as e:
            logger.error(f"네트워크 모드 변경 실패: {e}")
            return False
    
    def wait_for_ip_change(self, old_ip: str) -> Optional[str]:
        """IP 변경 대기"""
        logger.info(f"IP 변경 대기 중... (현재: {old_ip})")
        start_time = time.time()
        
        while time.time() - start_time < MAX_WAIT_TIME:
            current_ip = self.check_current_ip()
            if current_ip and current_ip != old_ip:
                logger.info(f"새로운 IP 감지: {current_ip}")
                return current_ip
            time.sleep(1)
            
        logger.warning("IP 변경 타임아웃")
        return None
    
    def get_traffic_statistics(self, client: Client) -> Dict:
        """트래픽 통계 가져오기"""
        try:
            stats = client.monitoring.traffic_statistics()
            return {
                'upload': stats.get('TotalUpload', '0'),
                'download': stats.get('TotalDownload', '0'),
                'upload_rate': stats.get('CurrentUploadRate', '0'),
                'download_rate': stats.get('CurrentDownloadRate', '0')
            }
        except Exception as e:
            logger.error(f"트래픽 통계 가져오기 실패: {e}")
            return {
                'upload': '0',
                'download': '0',
                'upload_rate': '0',
                'download_rate': '0'
            }
    
    def toggle(self) -> Dict:
        """동글 네트워크 토글 실행"""
        result = {
            'success': False,
            'subnet': self.subnet,
            'old_ip': None,
            'new_ip': None,
            'error': None,
            'timestamp': datetime.now().isoformat(),
            'traffic': None
        }
        
        try:
            # 프로세스 락 확인
            if not self.acquire_lock():
                result['error'] = 'Toggle already in progress'
                return result
            
            # 시간 간격 체크
            last_toggle = self.check_last_toggle_time()
            if last_toggle:
                elapsed = time.time() - last_toggle
                if elapsed < MIN_TOGGLE_INTERVAL:
                    remaining = MIN_TOGGLE_INTERVAL - elapsed
                    result['error'] = f'Too soon to toggle. Please wait {remaining:.0f} seconds'
                    self.release_lock()
                    return result
            
            # 현재 IP 확인
            old_ip = self.check_current_ip()
            if not old_ip:
                result['error'] = 'Cannot get current IP'
                self.release_lock()
                return result
                
            result['old_ip'] = old_ip
            logger.info(f"동글{self.subnet} 현재 IP: {old_ip}")
            
            # 모뎀 연결 및 토글
            with Connection(self.connection_url) as connection:
                client = Client(connection)
                
                # 로그인 상태 확인
                state = client.user.state_login()
                if state.get('State') != '0':
                    result['error'] = f'Login failed: State={state.get("State")}'
                    return result
                
                # 네트워크 모드 토글
                if not self.toggle_network_mode(client):
                    result['error'] = 'Failed to toggle network mode'
                    self.release_lock()
                    return result
                
                # IP 변경 대기
                new_ip = self.wait_for_ip_change(old_ip)
                if new_ip:
                    result['new_ip'] = new_ip
                    result['success'] = True
                    
                    # 트래픽 통계 가져오기
                    result['traffic'] = self.get_traffic_statistics(client)
                    
                    # 토글 시간 저장
                    self.save_toggle_time()
                else:
                    result['error'] = 'IP change timeout'
                    
        except (LoginErrorUsernameWrongException, LoginErrorPasswordWrongException) as e:
            result['error'] = f'Login error: {str(e)}'
        except Exception as e:
            result['error'] = f'Error: {str(e)}'
            logger.error(f"토글 중 오류 발생: {e}")
        finally:
            # 항상 락 해제
            self.release_lock()
            
        return result

def main():
    """메인 함수"""
    if len(sys.argv) != 2:
        print("Usage: toggle_dongle.py <subnet>")
        print("Example: toggle_dongle.py 11")
        sys.exit(1)
        
    try:
        subnet = int(sys.argv[1])
        if subnet < 11 or subnet > 30:
            print("Subnet must be between 11 and 30")
            sys.exit(1)
            
        toggler = DongleToggler(subnet)
        result = toggler.toggle()
        
        # JSON 결과 출력
        print(json.dumps(result, indent=2))
        
        # 성공 여부에 따른 종료 코드
        sys.exit(0 if result['success'] else 1)
        
    except ValueError:
        print("Invalid subnet number")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()