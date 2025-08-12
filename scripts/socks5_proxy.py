#!/usr/bin/env python3
"""
SOCKS5 프록시 서버 (v1 - 안정화 버전)
연결된 동글에 대해서만 프록시 제공
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

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SOCKS5Server:
    def __init__(self, subnet):
        self.subnet = subnet
        self.port = 10000 + subnet
        self.source_ip = f"192.168.{subnet}.100"
        self.running = True
        self.server_socket = None
        # 인터페이스 이름 찾기
        self.interface = self.get_interface_name()
    
    def get_interface_name(self):
        """IP 주소로 인터페이스 이름 찾기"""
        try:
            result = subprocess.run(['ip', 'addr', 'show'], capture_output=True, text=True)
            lines = result.stdout.split('\n')
            for i, line in enumerate(lines):
                if self.source_ip in line:
                    # 이전 라인에서 인터페이스 이름 추출
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
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(5)
            logger.info(f"SOCKS5 proxy started on port {self.port} for subnet {self.subnet}")
            
            while self.running:
                try:
                    client, addr = self.server_socket.accept()
                    thread = threading.Thread(target=self.handle_client, args=(client,))
                    thread.daemon = True
                    thread.start()
                except:
                    if self.running:
                        logger.error(f"Error accepting connection on port {self.port}")
                        
        except Exception as e:
            logger.error(f"Failed to start proxy on port {self.port}: {e}")
            
    def handle_client(self, client_socket):
        """클라이언트 연결 처리"""
        try:
            # SOCKS5 handshake
            client_socket.recv(262)
            client_socket.send(b"\x05\x00")
            
            # Connection request
            data = client_socket.recv(4)
            if len(data) < 4:
                client_socket.close()
                return
                
            mode = data[1]
            if mode != 1:  # Only support CONNECT
                client_socket.close()
                return
                
            # Parse destination
            addr_type = data[3]
            if addr_type == 1:  # IPv4
                addr = socket.inet_ntoa(client_socket.recv(4))
            elif addr_type == 3:  # Domain
                addr_len = client_socket.recv(1)[0]
                addr = client_socket.recv(addr_len).decode()
            else:
                client_socket.close()
                return
                
            port = struct.unpack('!H', client_socket.recv(2))[0]
            
            # Connect through specific interface
            try:
                remote = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                
                # Bind to specific source IP instead of interface
                if self.interface:
                    # Try interface binding first
                    try:
                        remote.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, 
                                         self.interface.encode())
                    except:
                        # Fallback to source IP binding
                        remote.bind((self.source_ip, 0))
                else:
                    # Use source IP binding
                    remote.bind((self.source_ip, 0))
                                 
                remote.connect((addr, port))
                
                # Send success response
                reply = b"\x05\x00\x00\x01"
                reply += socket.inet_aton('0.0.0.0') + struct.pack('!H', 0)
                client_socket.send(reply)
                
                # Relay data
                self.relay_data(client_socket, remote)
                
            except Exception as e:
                # Send failure response
                reply = b"\x05\x01\x00\x01\x00\x00\x00\x00\x00\x00"
                client_socket.send(reply)
                
        except:
            pass
        finally:
            client_socket.close()
            
    def relay_data(self, client, remote):
        """데이터 릴레이"""
        while True:
            try:
                r, w, e = select.select([client, remote], [], [], 1)
                
                if client in r:
                    data = client.recv(4096)
                    if not data:
                        break
                    remote.send(data)
                    
                if remote in r:
                    data = remote.recv(4096)
                    if not data:
                        break
                    client.send(data)
                    
            except:
                break
                
        client.close()
        remote.close()
        
    def stop(self):
        """프록시 서버 중지"""
        self.running = False
        if self.server_socket:
            self.server_socket.close()

class ProxyManager:
    def __init__(self):
        self.servers = {}
        self.running = True
        
    def check_interfaces(self):
        """연결된 동글 확인"""
        connected = []
        for subnet in range(11, 31):
            try:
                result = subprocess.run(
                    ['ip', 'addr', 'show'],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if f"192.168.{subnet}.100" in result.stdout:
                    connected.append(subnet)
            except:
                pass
        return connected
        
    def run(self):
        """메인 루프"""
        logger.info("SOCKS5 Proxy Manager started")
        
        while self.running:
            connected = self.check_interfaces()
            
            # 새로 연결된 동글 프록시 시작
            for subnet in connected:
                if subnet not in self.servers:
                    server = SOCKS5Server(subnet)
                    thread = threading.Thread(target=server.start)
                    thread.daemon = True
                    thread.start()
                    self.servers[subnet] = server
                    
            # 연결 해제된 동글 프록시 중지
            for subnet in list(self.servers.keys()):
                if subnet not in connected:
                    self.servers[subnet].stop()
                    del self.servers[subnet]
                    logger.info(f"Stopped proxy for subnet {subnet}")
                    
            time.sleep(10)  # 10초마다 체크
            
    def stop(self):
        """모든 프록시 중지"""
        self.running = False
        for server in self.servers.values():
            server.stop()

if __name__ == '__main__':
    manager = ProxyManager()
    
    def signal_handler(sig, frame):
        logger.info("Shutting down...")
        manager.stop()
        sys.exit(0)
        
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    manager.run()