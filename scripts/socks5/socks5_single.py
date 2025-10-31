#!/usr/bin/env python3
"""
단일 포트용 SOCKS5 프록시 서버
각 동글별로 독립적으로 실행되는 서비스
사용법: python3 socks5_single.py <subnet>
예: python3 socks5_single.py 11
"""

import socket
import select
import struct
import threading
import subprocess
import sys
import signal
import logging

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - Dongle%(subnet)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class SOCKS5Server:
    def __init__(self, subnet):
        self.subnet = subnet
        self.port = 10000 + subnet
        self.source_ip = f"192.168.{subnet}.100"
        self.running = True
        self.server_socket = None
        self.interface = self.get_interface_name()
        
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
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(128)
            logger.info(f"SOCKS5 proxy listening on port {self.port} (IP: {self.source_ip})")
            
            while self.running:
                try:
                    readable, _, _ = select.select([self.server_socket], [], [], 1)
                    if readable:
                        client_socket, address = self.server_socket.accept()
                        thread = threading.Thread(target=self.handle_client, args=(client_socket, address))
                        thread.daemon = True
                        thread.start()
                except Exception as e:
                    if self.running:
                        logger.error(f"Error accepting connection: {e}")
                        
        except Exception as e:
            logger.error(f"Failed to start server on port {self.port}: {e}")
        finally:
            self.stop()
            
    def handle_client(self, client_socket, address):
        """클라이언트 연결 처리"""
        try:
            # SOCKS5 인증
            data = client_socket.recv(2)
            if len(data) < 2:
                client_socket.close()
                return
                
            version, nmethods = struct.unpack("!BB", data)
            if version != 5:
                client_socket.close()
                return
                
            client_socket.recv(nmethods)
            client_socket.send(b"\x05\x00")  # No auth required
            
            # 연결 요청
            data = client_socket.recv(4)
            if len(data) < 4:
                client_socket.close()
                return
                
            version, cmd, _, atyp = struct.unpack("!BBBB", data)
            
            if cmd != 1:  # CONNECT only
                client_socket.send(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
                client_socket.close()
                return
                
            # 주소 파싱
            if atyp == 1:  # IPv4
                addr = socket.inet_ntoa(client_socket.recv(4))
            elif atyp == 3:  # Domain
                addr_len = client_socket.recv(1)[0]
                addr = client_socket.recv(addr_len).decode()
            else:
                client_socket.send(b"\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00")
                client_socket.close()
                return
                
            port = struct.unpack("!H", client_socket.recv(2))[0]
            
            # 원격 서버 연결 (특정 IP 바인딩)
            try:
                remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                remote_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, self.interface.encode())
                remote_socket.settimeout(10)
                remote_socket.connect((addr, port))
                
                # 성공 응답
                client_socket.send(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
                
                # 데이터 중계
                self.relay_data(client_socket, remote_socket)
                
            except Exception as e:
                logger.debug(f"Failed to connect to {addr}:{port} - {e}")
                client_socket.send(b"\x05\x01\x00\x01\x00\x00\x00\x00\x00\x00")
                
        except Exception as e:
            logger.debug(f"Error handling client: {e}")
        finally:
            client_socket.close()
            
    def relay_data(self, client_socket, remote_socket):
        """클라이언트와 원격 서버 간 데이터 중계"""
        try:
            # TCP Keepalive 설정 (유휴 연결 자동 정리)
            client_socket.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 60)   # 60초 유휴 후 체크 시작
            client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 10)  # 10초 간격으로 체크
            client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)     # 3번 실패하면 종료

            remote_socket.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            remote_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 60)
            remote_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 10)
            remote_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)

            client_socket.setblocking(False)
            remote_socket.setblocking(False)

            idle_count = 0
            max_idle_cycles = 300  # 300초 (5분) 동안 데이터 없으면 종료

            while self.running:
                ready = select.select([client_socket, remote_socket], [], [], 1)
                if ready[0]:
                    idle_count = 0  # 데이터 있으면 카운터 리셋
                    for sock in ready[0]:
                        data = sock.recv(4096)
                        if not data:
                            return
                        if sock is client_socket:
                            remote_socket.sendall(data)
                        else:
                            client_socket.sendall(data)
                else:
                    idle_count += 1
                    if idle_count >= max_idle_cycles:
                        logger.debug(f"Connection idle timeout after {max_idle_cycles}s")
                        return
        except:
            pass
        finally:
            remote_socket.close()
            
    def stop(self):
        """서버 중지"""
        self.running = False
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass
            logger.info(f"SOCKS5 proxy stopped on port {self.port}")

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 socks5_single.py <subnet>")
        print("Example: python3 socks5_single.py 11")
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