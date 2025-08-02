#!/usr/bin/env python3
"""
동적 SOCKS5 프록시 서버
동글 연결/해제를 실시간으로 감지하여 자동으로 포트 활성화/비활성화
"""
import socket
import select
import struct
import threading
import subprocess
import time
import logging
import signal
import sys
import os
from typing import Dict, Optional

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DynamicSOCKS5Server:
    def __init__(self):
        self.servers = {}  # {subnet: SOCKS5Server}
        self.threads = {}  # {subnet: Thread}
        self.running = True
        self.monitor_interval = 5  # 5초마다 동글 상태 체크
        
    def check_dongles(self):
        """현재 연결된 동글 확인"""
        connected_dongles = {}
        
        for subnet in range(11, 31):
            cmd = f"ip addr show | grep -q '192.168.{subnet}.100'"
            result = subprocess.run(cmd, shell=True, capture_output=True)
            
            if result.returncode == 0:
                # 인터페이스 이름도 가져오기
                cmd = f"ip addr show | grep '192.168.{subnet}.100' | awk '{{print $NF}}'"
                interface = subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()
                connected_dongles[subnet] = interface
                
        return connected_dongles
        
    def start_proxy(self, subnet):
        """특정 동글의 프록시 시작"""
        if subnet in self.servers:
            return  # 이미 실행 중
            
        port = 10000 + subnet
        dongle_ip = f"192.168.{subnet}.100"
        
        logger.info(f"동글 {subnet} 프록시 시작 (포트 {port})")
        
        from dongle_socks5_server import SOCKS5Server
        server = SOCKS5Server(port, '0.0.0.0', dongle_ip)
        self.servers[subnet] = server
        
        thread = threading.Thread(target=server.start, name=f"proxy_{subnet}")
        thread.daemon = True
        thread.start()
        self.threads[subnet] = thread
        
    def stop_proxy(self, subnet):
        """특정 동글의 프록시 중지"""
        if subnet not in self.servers:
            return  # 실행 중이 아님
            
        logger.info(f"동글 {subnet} 프록시 중지")
        
        server = self.servers[subnet]
        server.running = False
        
        # 서버 소켓 강제 종료
        try:
            # 더미 연결로 accept 블록 해제
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect(('127.0.0.1', 10000 + subnet))
            s.close()
        except:
            pass
            
        # 정리
        del self.servers[subnet]
        del self.threads[subnet]
        
    def monitor_loop(self):
        """동글 상태 모니터링 루프"""
        logger.info("동글 모니터링 시작")
        
        while self.running:
            try:
                # 현재 연결된 동글 확인
                current_dongles = self.check_dongles()
                current_subnets = set(current_dongles.keys())
                active_subnets = set(self.servers.keys())
                
                # 새로 연결된 동글
                new_dongles = current_subnets - active_subnets
                for subnet in new_dongles:
                    logger.info(f"새 동글 감지: {subnet} ({current_dongles[subnet]})")
                    self.start_proxy(subnet)
                    
                # 연결 해제된 동글
                removed_dongles = active_subnets - current_subnets
                for subnet in removed_dongles:
                    logger.info(f"동글 제거 감지: {subnet}")
                    self.stop_proxy(subnet)
                    
                # 상태 로그 (변경 시에만)
                if new_dongles or removed_dongles:
                    logger.info(f"활성 프록시: {sorted(current_subnets)}")
                    
            except Exception as e:
                logger.error(f"모니터링 오류: {e}")
                
            time.sleep(self.monitor_interval)
            
    def start(self):
        """동적 프록시 서버 시작"""
        logger.info("동적 SOCKS5 프록시 서버 시작")
        
        # 초기 동글 확인 및 프록시 시작
        initial_dongles = self.check_dongles()
        for subnet, interface in initial_dongles.items():
            logger.info(f"초기 동글 발견: {subnet} ({interface})")
            self.start_proxy(subnet)
            
        if not initial_dongles:
            logger.warning("연결된 동글이 없습니다. 동글 연결을 기다립니다...")
            
        # 모니터링 시작
        self.monitor_loop()
        
    def stop(self):
        """서버 종료"""
        logger.info("동적 SOCKS5 프록시 서버 종료 중...")
        self.running = False
        
        # 모든 프록시 중지
        for subnet in list(self.servers.keys()):
            self.stop_proxy(subnet)
            
        logger.info("종료 완료")

def signal_handler(signum, frame):
    """시그널 핸들러"""
    logger.info(f"시그널 {signum} 수신")
    if hasattr(signal_handler, 'server'):
        signal_handler.server.stop()
    sys.exit(0)

def main():
    # 시그널 핸들러 설정
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # 서버 시작
    server = DynamicSOCKS5Server()
    signal_handler.server = server
    
    try:
        server.start()
    except KeyboardInterrupt:
        pass
    finally:
        server.stop()

if __name__ == '__main__':
    main()