#!/usr/bin/env python3
"""
SOCKS5 프로세스 메모리 모니터링 및 자동 재시작
- 메모리 사용량이 임계값 초과시 재시작
- 스레드 수가 과도할 때 재시작
- 응답 없는 프로세스 감지 및 재시작
"""

import psutil
import subprocess
import time
import logging
import socket
import struct
from datetime import datetime

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/home/proxy/logs/socks5_monitor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# 임계값 설정
MEMORY_THRESHOLD_MB = 500  # 메모리 500MB 초과시 재시작
THREAD_THRESHOLD = 150     # 스레드 150개 초과시 재시작
RESPONSE_TIMEOUT = 5       # 5초 내 응답 없으면 문제로 판단

def get_socks5_processes():
    """실행 중인 SOCKS5 프로세스 목록 반환"""
    processes = []
    
    # proxy_state.json에서 활성 서브넷 목록 가져오기
    active_subnets = set()
    try:
        import json
        with open('/home/proxy/proxy_state.json', 'r') as f:
            data = json.load(f)
            active_subnets = set(int(k) for k in data.keys())
    except:
        # 기본값 사용
        active_subnets = set(range(11, 24))
    
    for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'memory_info', 'num_threads']):
        try:
            cmdline = proc.info['cmdline']
            if cmdline and 'socks5_single' in ' '.join(cmdline):
                # 서브넷 번호 추출
                for arg in cmdline:
                    if arg.isdigit():
                        subnet = int(arg)
                        if subnet in active_subnets:
                            processes.append({
                                'pid': proc.info['pid'],
                                'subnet': subnet,
                                'memory_mb': proc.info['memory_info'].rss / 1048576,
                                'threads': proc.info['num_threads'],
                                'proc': proc
                            })
                            break
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return processes

def test_socks5_port(port):
    """SOCKS5 포트 응답 테스트"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(RESPONSE_TIMEOUT)
        sock.connect(('127.0.0.1', port))
        
        # SOCKS5 handshake 시도
        sock.send(b'\x05\x01\x00')  # Version 5, 1 method, no auth
        response = sock.recv(2)
        sock.close()
        
        # 정상 응답 확인
        if len(response) == 2 and response[0] == 5:
            return True
    except:
        pass
    return False

def restart_socks5_service(subnet):
    """특정 SOCKS5 서비스 재시작"""
    logger.warning(f"Restarting SOCKS5 service for subnet {subnet}")
    try:
        # systemctl restart 사용
        result = subprocess.run(
            ['systemctl', 'restart', f'dongle-socks5-{subnet}'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            logger.info(f"Successfully restarted dongle-socks5-{subnet}")
            return True
        else:
            logger.error(f"Failed to restart dongle-socks5-{subnet}: {result.stderr}")
            
            # 강제 종료 후 재시작 시도
            subprocess.run(['pkill', '-9', '-f', f'socks5_single.py {subnet}'], timeout=5)
            time.sleep(1)
            subprocess.run(['systemctl', 'start', f'dongle-socks5-{subnet}'], timeout=10)
            
    except subprocess.TimeoutExpired:
        logger.error(f"Timeout while restarting dongle-socks5-{subnet}")
    except Exception as e:
        logger.error(f"Error restarting dongle-socks5-{subnet}: {e}")
    return False

def check_and_restart():
    """모든 SOCKS5 프로세스 확인 및 필요시 재시작"""
    processes = get_socks5_processes()
    
    if not processes:
        logger.warning("No SOCKS5 processes found")
        return
    
    restart_count = 0
    
    for proc_info in processes:
        subnet = proc_info['subnet']
        memory_mb = proc_info['memory_mb']
        threads = proc_info['threads']
        port = 10000 + subnet
        
        need_restart = False
        reason = ""
        
        # 메모리 체크
        if memory_mb > MEMORY_THRESHOLD_MB:
            need_restart = True
            reason = f"Memory usage {memory_mb:.1f}MB exceeds threshold {MEMORY_THRESHOLD_MB}MB"
        
        # 스레드 체크
        elif threads > THREAD_THRESHOLD:
            need_restart = True
            reason = f"Thread count {threads} exceeds threshold {THREAD_THRESHOLD}"
        
        # 응답 체크
        elif not test_socks5_port(port):
            need_restart = True
            reason = f"Port {port} not responding"
        
        if need_restart:
            logger.warning(f"Subnet {subnet} needs restart: {reason}")
            if restart_socks5_service(subnet):
                restart_count += 1
                time.sleep(2)  # 재시작 간 간격
        else:
            logger.debug(f"Subnet {subnet} OK - Memory: {memory_mb:.1f}MB, Threads: {threads}")
    
    if restart_count > 0:
        logger.info(f"Restarted {restart_count} SOCKS5 services")
    
    return restart_count

def main():
    """메인 모니터링 루프"""
    logger.info("SOCKS5 memory monitor started")
    
    check_interval = 60  # 1분마다 체크
    last_full_restart = time.time()
    full_restart_interval = 3600  # 1시간마다 전체 재시작 (크론과 동일)
    
    while True:
        try:
            # 정기 체크
            restart_count = check_and_restart()
            
            # 너무 많은 서비스가 재시작된 경우 전체 재시작
            if restart_count > 5:
                logger.warning(f"Too many services restarted ({restart_count}), performing full restart")
                subprocess.run(['/home/proxy/scripts/socks5/manage_socks5.sh', 'restart', 'all'], timeout=30)
                time.sleep(10)
                last_full_restart = time.time()
            
            # 주기적 전체 재시작 (크론 백업)
            if time.time() - last_full_restart > full_restart_interval:
                logger.info("Performing scheduled full restart")
                subprocess.run(['/home/proxy/scripts/socks5/manage_socks5.sh', 'restart', 'all'], timeout=30)
                last_full_restart = time.time()
                time.sleep(10)
            
            # 다음 체크까지 대기
            time.sleep(check_interval)
            
        except KeyboardInterrupt:
            logger.info("Monitor stopped by user")
            break
        except Exception as e:
            logger.error(f"Monitor error: {e}")
            time.sleep(10)

if __name__ == '__main__':
    main()