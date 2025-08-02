#!/usr/bin/env python3
"""
SOCKS5 proxy server for dongles
Provides transparent proxy without detection
"""

import socket
import select
import struct
import threading
import sys
import logging
from typing import Dict, Tuple, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class SOCKS5Server:
    def __init__(self, listen_port: int, bind_ip: str, dongle_ip: str):
        self.listen_port = listen_port
        self.bind_ip = bind_ip
        self.dongle_ip = dongle_ip
        self.running = False
        
    def start(self):
        """Start the SOCKS5 server"""
        self.running = True
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        try:
            server.bind((self.bind_ip, self.listen_port))
            server.listen(5)
            logger.info(f"SOCKS5 server listening on {self.bind_ip}:{self.listen_port} (using dongle IP {self.dongle_ip})")
            
            while self.running:
                try:
                    client, addr = server.accept()
                    logger.info(f"New connection from {addr}")
                    threading.Thread(target=self.handle_client, args=(client,)).start()
                except KeyboardInterrupt:
                    break
                except Exception as e:
                    logger.error(f"Accept error: {e}")
                    
        except Exception as e:
            logger.error(f"Server error: {e}")
        finally:
            server.close()
            
    def handle_client(self, client: socket.socket):
        """Handle SOCKS5 client connection"""
        try:
            # SOCKS5 authentication
            data = client.recv(1024)
            if len(data) < 2:
                client.close()
                return
                
            # Send no authentication required
            client.send(b'\x05\x00')
            
            # Get connect request
            data = client.recv(1024)
            if len(data) < 10:
                client.close()
                return
                
            ver, cmd, _, atyp = struct.unpack('!BBBB', data[:4])
            
            if ver != 5 or cmd != 1:  # Only support CONNECT
                client.send(b'\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00')
                client.close()
                return
                
            # Parse destination
            dst_addr = None
            dst_port = None
            
            if atyp == 1:  # IPv4
                dst_addr = socket.inet_ntoa(data[4:8])
                dst_port = struct.unpack('!H', data[8:10])[0]
            elif atyp == 3:  # Domain name
                addr_len = data[4]
                dst_addr = data[5:5+addr_len].decode()
                dst_port = struct.unpack('!H', data[5+addr_len:7+addr_len])[0]
            else:
                client.send(b'\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00')
                client.close()
                return
                
            logger.info(f"Connecting to {dst_addr}:{dst_port}")
            
            # Create outbound connection using dongle interface
            remote = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            remote.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            
            # Bind to dongle IP
            remote.bind((self.dongle_ip, 0))
            
            try:
                remote.connect((dst_addr, dst_port))
                
                # Send success response
                client.send(b'\x05\x00\x00\x01' + socket.inet_aton('0.0.0.0') + struct.pack('!H', 0))
                
                # Relay data
                self.relay_data(client, remote)
                
            except Exception as e:
                logger.error(f"Connect error: {e}")
                client.send(b'\x05\x01\x00\x01\x00\x00\x00\x00\x00\x00')
                
        except Exception as e:
            logger.error(f"Client handler error: {e}")
        finally:
            client.close()
            
    def relay_data(self, client: socket.socket, remote: socket.socket):
        """Relay data between client and remote"""
        try:
            while True:
                ready, _, _ = select.select([client, remote], [], [], 5)
                
                if client in ready:
                    data = client.recv(4096)
                    if not data:
                        break
                    remote.send(data)
                    
                if remote in ready:
                    data = remote.recv(4096)
                    if not data:
                        break
                    client.send(data)
                    
        except Exception as e:
            logger.debug(f"Relay error: {e}")
        finally:
            client.close()
            remote.close()

def main():
    """Main function to start SOCKS5 servers for all dongles"""
    servers = []
    
    # Start servers for connected dongles
    import subprocess
    
    for subnet in range(11, 31):
        # Check if dongle is connected
        result = subprocess.run(
            f"ip addr show | grep -q '192.168.{subnet}.100'",
            shell=True
        )
        
        if result.returncode == 0:
            port = 10000 + subnet
            dongle_ip = f"192.168.{subnet}.100"
            
            logger.info(f"Starting SOCKS5 server for dongle {subnet} on port {port}")
            
            server = SOCKS5Server(port, '0.0.0.0', dongle_ip)
            thread = threading.Thread(target=server.start)
            thread.daemon = True
            thread.start()
            servers.append(server)
    
    if not servers:
        logger.error("No dongles found")
        sys.exit(1)
        
    logger.info(f"Started {len(servers)} SOCKS5 servers")
    
    # Keep running
    try:
        while True:
            threading.Event().wait(1)
    except KeyboardInterrupt:
        logger.info("Shutting down...")
        for server in servers:
            server.running = False

if __name__ == '__main__':
    main()