#!/usr/bin/env python3
"""
실시간 트래픽 모니터링 with 속도 계산
"""
import time
import subprocess
import os
from collections import defaultdict
from datetime import datetime

class TrafficMonitor:
    def __init__(self):
        self.prev_stats = {}
        self.connections_log = defaultdict(list)
        
    def get_interface_stats(self, interface):
        """인터페이스 통계 가져오기"""
        try:
            cmd = f"cat /sys/class/net/{interface}/statistics/rx_bytes"
            rx_bytes = int(subprocess.check_output(cmd, shell=True).strip())
            
            cmd = f"cat /sys/class/net/{interface}/statistics/tx_bytes"
            tx_bytes = int(subprocess.check_output(cmd, shell=True).strip())
            
            return rx_bytes, tx_bytes
        except:
            return 0, 0
    
    def format_bytes(self, bytes_val):
        """바이트를 읽기 쉬운 형식으로"""
        if bytes_val < 1024:
            return f"{bytes_val} B"
        elif bytes_val < 1024*1024:
            return f"{bytes_val/1024:.1f} KB"
        elif bytes_val < 1024*1024*1024:
            return f"{bytes_val/1024/1024:.1f} MB"
        else:
            return f"{bytes_val/1024/1024/1024:.2f} GB"
    
    def get_speed(self, interface, current_rx, current_tx):
        """속도 계산"""
        key = interface
        if key in self.prev_stats:
            prev_rx, prev_tx, prev_time = self.prev_stats[key]
            time_diff = time.time() - prev_time
            
            rx_speed = (current_rx - prev_rx) / time_diff
            tx_speed = (current_tx - prev_tx) / time_diff
            
            return rx_speed, tx_speed
        return 0, 0
    
    def get_active_connections(self, port):
        """활성 연결 정보"""
        cmd = f"ss -tn | grep ':{port}' | grep ESTAB"
        try:
            output = subprocess.check_output(cmd, shell=True, text=True)
            connections = []
            for line in output.strip().split('\n'):
                if line:
                    parts = line.split()
                    if len(parts) >= 5:
                        remote = parts[4].split(':')[0]
                        connections.append(remote)
            return connections
        except:
            return []
    
    def monitor(self):
        """메인 모니터링 루프"""
        print("동글 11 실시간 트래픽 모니터링")
        print("="*60)
        
        while True:
            os.system('clear')
            print(f"\n=== 동글 11 트래픽 현황 - {datetime.now().strftime('%H:%M:%S')} ===\n")
            
            # 인터페이스 찾기
            cmd = "ip addr show | grep '192.168.11.100' | awk '{print $NF}'"
            try:
                interface = subprocess.check_output(cmd, shell=True, text=True).strip()
                if interface:
                    # 트래픽 통계
                    rx_bytes, tx_bytes = self.get_interface_stats(interface)
                    rx_speed, tx_speed = self.get_speed(interface, rx_bytes, tx_bytes)
                    
                    print(f"인터페이스: {interface}")
                    print(f"총 다운로드: {self.format_bytes(rx_bytes)}")
                    print(f"총 업로드: {self.format_bytes(tx_bytes)}")
                    print(f"다운로드 속도: {self.format_bytes(rx_speed)}/s")
                    print(f"업로드 속도: {self.format_bytes(tx_speed)}/s")
                    
                    # 현재 통계 저장
                    self.prev_stats[interface] = (rx_bytes, tx_bytes, time.time())
                    
                    # SOCKS5 연결 정보
                    print(f"\n--- SOCKS5 프록시 (포트 10011) ---")
                    connections = self.get_active_connections(10011)
                    print(f"활성 연결 수: {len(connections)}")
                    
                    if connections:
                        ip_counts = defaultdict(int)
                        for ip in connections:
                            ip_counts[ip] += 1
                        
                        print("\n연결된 클라이언트:")
                        for ip, count in sorted(ip_counts.items(), key=lambda x: x[1], reverse=True):
                            print(f"  {ip}: {count}개 연결")
                    
                    # 최근 활동 로그
                    print(f"\n--- 최근 활동 ---")
                    cmd = "journalctl -u dongle-socks5 --since '10 seconds ago' | grep 'Connecting to' | tail -5"
                    try:
                        output = subprocess.check_output(cmd, shell=True, text=True)
                        if output.strip():
                            for line in output.strip().split('\n'):
                                if 'Connecting to' in line:
                                    dest = line.split('Connecting to ')[-1].strip()
                                    print(f"  → {dest}")
                    except:
                        pass
                
            except Exception as e:
                print(f"오류: {e}")
            
            time.sleep(2)

if __name__ == "__main__":
    monitor = TrafficMonitor()
    try:
        monitor.monitor()
    except KeyboardInterrupt:
        print("\n\n모니터링 종료")