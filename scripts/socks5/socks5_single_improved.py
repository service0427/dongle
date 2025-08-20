#!/usr/bin/env python3
"""
개선된 단일 포트용 SOCKS5 프록시 서버
- 스레드 풀로 리소스 제한
- 연결별 타임아웃
- 적절한 에러 처리
- 메모리 관리 개선
"""

import socket
import select
import struct
import threading
import subprocess
import sys
import signal
import logging
import time
import gc
from concurrent.futures import ThreadPoolExecutor
from threading import Semaphore

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - Dongle%(subnet)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class SOCKS5Server:
    MAX_THREADS = 100  # 최대 스레드 수 제한
    CONNECTION_TIMEOUT = 30  # 연결 타임아웃 (초)
    BUFFER_SIZE = 16384  # TLS 레코드 크기에 맞춤
    
    def __init__(self, subnet):
        self.subnet = subnet
        self.port = 10000 + subnet
        self.source_ip = f"192.168.{subnet}.100"
        self.running = True
        self.server_socket = None
        self.interface = self.get_interface_name()
        self.thread_pool = ThreadPoolExecutor(max_workers=self.MAX_THREADS)
        self.active_connections = 0
        self.connection_semaphore = Semaphore(self.MAX_THREADS)
        self.total_connections = 0
        self.failed_connections = 0
        
    def get_interface_name(self):
        """IP 주소로 인터페이스 이름 찾기"""
        try:
            result = subprocess.run(['ip', 'addr', 'show'], capture_output=True, text=True)
            lines = result.stdout.split('\n')
            for i, line in enumerate(lines):
                if self.source_ip in line:
                    for j in range(i, -1, -1):
                        if ': ' in lines[j] and '<' in lines[j]:
                            interface = lines[j].split(':')[1].strip().split('@')[0]
                            logger.info(f"Found interface {interface} for IP {self.source_ip}")
                            return interface
        except Exception as e:
            logger.error(f"Failed to find interface for {self.source_ip}: {e}")
        return None
        
    def start(self):
        """프록시 서버 시작"""
        if not self.interface:
            logger.error(f"Interface not found for subnet {self.subnet}")
            return
            
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            # 소켓 버퍼 크기 증가
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 262144)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 262144)
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(128)
            logger.info(f"SOCKS5 proxy listening on port {self.port} (IP: {self.source_ip})")
            
            # 주기적 가비지 컬렉션
            gc_thread = threading.Thread(target=self.periodic_gc, daemon=True)
            gc_thread.start()
            
            # 통계 출력
            stats_thread = threading.Thread(target=self.print_stats, daemon=True)
            stats_thread.start()
            
            while self.running:
                try:
                    readable, _, _ = select.select([self.server_socket], [], [], 1)
                    if readable:
                        client_socket, address = self.server_socket.accept()
                        client_socket.settimeout(self.CONNECTION_TIMEOUT)
                        
                        # 스레드 풀 사용
                        if self.connection_semaphore.acquire(blocking=False):
                            self.thread_pool.submit(self.handle_client_wrapper, client_socket, address)
                        else:
                            logger.warning(f"Max connections reached, rejecting {address}")
                            client_socket.close()
                            
                except Exception as e:
                    if self.running:
                        logger.error(f"Error accepting connection: {e}")
                        
        except Exception as e:
            logger.error(f"Failed to start server on port {self.port}: {e}")
        finally:
            self.stop()
            
    def handle_client_wrapper(self, client_socket, address):
        """클라이언트 처리 래퍼 (리소스 관리)"""
        self.active_connections += 1
        self.total_connections += 1
        start_time = time.time()
        
        try:
            self.handle_client(client_socket, address)
        except Exception as e:
            logger.error(f"Error handling client {address}: {e}")
            self.failed_connections += 1
        finally:
            self.active_connections -= 1
            self.connection_semaphore.release()
            duration = time.time() - start_time
            if duration > 60:  # 1분 이상 연결은 로깅
                logger.info(f"Long connection closed: {address}, duration: {duration:.1f}s")
            
    def handle_client(self, client_socket, address):
        """클라이언트 연결 처리"""
        remote_socket = None
        try:
            # SOCKS5 인증
            data = client_socket.recv(2)
            if len(data) < 2:
                return
                
            version, nmethods = struct.unpack("!BB", data)
            if version != 5:
                return
                
            client_socket.recv(nmethods)
            client_socket.send(b"\x05\x00")  # No auth required
            
            # 연결 요청
            data = client_socket.recv(4)
            if len(data) < 4:
                return
                
            version, cmd, _, atyp = struct.unpack("!BBBB", data)
            
            if cmd != 1:  # CONNECT only
                client_socket.send(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
                return
                
            # 주소 파싱
            if atyp == 1:  # IPv4
                addr = socket.inet_ntoa(client_socket.recv(4))
            elif atyp == 3:  # Domain
                addr_len = client_socket.recv(1)[0]
                addr = client_socket.recv(addr_len).decode()
            else:
                client_socket.send(b"\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00")
                return
                
            port = struct.unpack("!H", client_socket.recv(2))[0]
            
            # 원격 서버 연결
            remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            remote_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, self.interface.encode())
            remote_socket.settimeout(10)
            # TCP_NODELAY로 지연 최소화
            remote_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            
            remote_socket.connect((addr, port))
            remote_socket.settimeout(self.CONNECTION_TIMEOUT)
            
            # 성공 응답
            client_socket.send(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
            
            # 데이터 중계
            self.relay_data(client_socket, remote_socket)
            
        except socket.timeout:
            logger.debug(f"Connection timeout: {address}")
            try:
                client_socket.send(b"\x05\x04\x00\x01\x00\x00\x00\x00\x00\x00")  # Host unreachable
            except:
                pass
        except ConnectionRefused:
            logger.debug(f"Connection refused: {address}")
            try:
                client_socket.send(b"\x05\x05\x00\x01\x00\x00\x00\x00\x00\x00")  # Connection refused
            except:
                pass
        except Exception as e:
            logger.debug(f"Connection error: {address} - {e}")
            try:
                client_socket.send(b"\x05\x01\x00\x01\x00\x00\x00\x00\x00\x00")  # General failure
            except:
                pass
        finally:
            # 확실한 리소스 정리
            if remote_socket:
                try:
                    remote_socket.close()
                except:
                    pass
            try:
                client_socket.close()
            except:
                pass
            
    def relay_data(self, client_socket, remote_socket):
        """클라이언트와 원격 서버 간 데이터 중계"""
        client_socket.setblocking(False)
        remote_socket.setblocking(False)
        
        last_activity = time.time()
        total_bytes = 0
        
        while self.running:
            try:
                # 타임아웃 체크
                if time.time() - last_activity > self.CONNECTION_TIMEOUT:
                    logger.debug("Connection idle timeout")
                    break
                    
                ready = select.select([client_socket, remote_socket], [], [], 1)
                
                if ready[0]:
                    for sock in ready[0]:
                        try:
                            data = sock.recv(self.BUFFER_SIZE)
                            if not data:
                                return
                                
                            if sock is client_socket:
                                remote_socket.sendall(data)
                            else:
                                client_socket.sendall(data)
                                
                            total_bytes += len(data)
                            last_activity = time.time()
                            
                        except socket.error as e:
                            if e.errno not in (socket.EAGAIN, socket.EWOULDBLOCK):
                                return
                                
            except select.error:
                return
            except Exception as e:
                logger.debug(f"Relay error: {e}")
                return
                
        if total_bytes > 1048576:  # 1MB 이상 전송시 로깅
            logger.debug(f"Large transfer: {total_bytes / 1048576:.1f}MB")
            
    def periodic_gc(self):
        """주기적 가비지 컬렉션"""
        while self.running:
            time.sleep(60)  # 1분마다
            collected = gc.collect()
            if collected > 0:
                logger.debug(f"GC collected {collected} objects")
                
    def print_stats(self):
        """통계 출력"""
        while self.running:
            time.sleep(300)  # 5분마다
            logger.info(f"Stats - Active: {self.active_connections}, Total: {self.total_connections}, Failed: {self.failed_connections}")
            
    def stop(self):
        """서버 중지"""
        self.running = False
        self.thread_pool.shutdown(wait=False)
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass
            logger.info(f"SOCKS5 proxy stopped on port {self.port}")

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 socks5_single_improved.py <subnet>")
        print("Example: python3 socks5_single_improved.py 11")
        sys.exit(1)
        
    try:
        subnet = int(sys.argv[1])
        if subnet < 11 or subnet > 30:
            raise ValueError("Subnet must be between 11 and 30")
    except ValueError as e:
        print(f"Invalid subnet: {e}")
        sys.exit(1)
        
    # 로거 설정 업데이트
    logging.basicConfig(
        level=logging.INFO,
        format=f'%(asctime)s - Dongle{subnet} - %(levelname)s - %(message)s'
    )
    
    server = SOCKS5Server(subnet)
    
    def signal_handler(sig, frame):
        logger.info("Shutting down...")
        server.stop()
        sys.exit(0)
        
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    server.start()

if __name__ == '__main__':
    main()