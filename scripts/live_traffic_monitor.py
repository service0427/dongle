#!/usr/bin/env python3
"""
실시간 동글 11 트래픽 모니터링 (간단 버전)
"""
import subprocess
import re
import sys
from datetime import datetime
import os

def monitor_traffic():
    """트래픽 모니터링"""
    # 인터페이스 찾기
    cmd = "ip addr show | grep '192.168.11.100' | awk '{print $NF}'"
    interface = subprocess.check_output(cmd, shell=True, text=True).strip()
    
    if not interface:
        print("동글 11을 찾을 수 없습니다")
        return
        
    print(f"=== 동글 11 트래픽 모니터링 ===")
    print(f"인터페이스: {interface}")
    print(f"시작: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)
    print()
    
    # tcpdump로 모든 트래픽 캡처
    cmd = f"tcpdump -i {interface} -nn -l -q 2>/dev/null"
    process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, text=True)
    
    try:
        for line in iter(process.stdout.readline, ''):
            if not line:
                continue
                
            timestamp = datetime.now().strftime('%H:%M:%S')
            
            # DNS 쿼리 감지
            if 'UDP' in line and '.53:' in line:
                print(f"[{timestamp}] DNS 쿼리")
                
            # HTTP 트래픽 감지
            elif '.80:' in line or '.80 >' in line:
                src_dst = re.search(r'(\d+\.\d+\.\d+\.\d+)\.(\d+) > (\d+\.\d+\.\d+\.\d+)\.(\d+)', line)
                if src_dst:
                    src_ip = src_dst.group(1)
                    dst_ip = src_dst.group(3)
                    dst_port = src_dst.group(4)
                    
                    if dst_port == '80':
                        print(f"[{timestamp}] HTTP → {dst_ip}")
                    else:
                        print(f"[{timestamp}] HTTP ← {src_ip}")
                        
            # HTTPS 트래픽 감지
            elif '.443:' in line or '.443 >' in line:
                src_dst = re.search(r'(\d+\.\d+\.\d+\.\d+)\.(\d+) > (\d+\.\d+\.\d+\.\d+)\.(\d+)', line)
                if src_dst:
                    src_ip = src_dst.group(1)
                    dst_ip = src_dst.group(3)
                    dst_port = src_dst.group(4)
                    
                    if dst_port == '443':
                        print(f"[{timestamp}] HTTPS → {dst_ip}")
                        
            # 기타 트래픽
            else:
                # 간단히 출력
                if '>' in line and not 'ARP' in line:
                    print(f"[{timestamp}] {line.strip()}")
                    
    except KeyboardInterrupt:
        print("\n\n모니터링 종료")
        process.terminate()

if __name__ == "__main__":
    if os.geteuid() != 0:
        print("root 권한이 필요합니다")
        sys.exit(1)
    monitor_traffic()