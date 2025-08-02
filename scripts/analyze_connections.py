#!/usr/bin/env python3
"""
동시 접속 분석 및 패턴 파악
"""
import subprocess
import json
from collections import defaultdict
from datetime import datetime

def analyze_socks5_logs():
    """SOCKS5 로그 분석"""
    # 최근 5분 로그 가져오기
    cmd = "journalctl -u dongle-socks5 --since '5 minutes ago' --no-pager"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    
    connections = defaultdict(int)
    destinations = defaultdict(int)
    errors = []
    
    for line in result.stdout.split('\n'):
        if 'New connection from' in line:
            try:
                # IP 추출
                ip = line.split("from ('")[1].split("'")[0]
                connections[ip] += 1
            except:
                pass
                
        if 'Connecting to' in line:
            try:
                # 목적지 추출
                dest = line.split('Connecting to ')[1].strip()
                destinations[dest] += 1
            except:
                pass
                
        if any(word in line.lower() for word in ['error', 'failed', 'denied', 'timeout']):
            errors.append(line)
    
    print("=== 동시 접속 분석 ===")
    print(f"분석 시간: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    print("1. 접속 IP별 연결 수:")
    for ip, count in sorted(connections.items(), key=lambda x: x[1], reverse=True):
        print(f"   {ip}: {count} connections")
    
    print(f"\n2. 총 연결 시도: {sum(connections.values())}")
    
    print("\n3. 주요 접속 대상:")
    for dest, count in sorted(destinations.items(), key=lambda x: x[1], reverse=True)[:10]:
        print(f"   {dest}: {count} times")
    
    print(f"\n4. 오류 발생: {len(errors)} 건")
    if errors:
        print("   최근 오류:")
        for err in errors[:5]:
            print(f"   - {err}")
    
    # 현재 활성 연결 체크
    print("\n5. 현재 활성 연결:")
    for port in [10011, 10016]:
        cmd = f"ss -tn | grep :{port} | grep ESTAB | wc -l"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        count = result.stdout.strip()
        print(f"   Port {port}: {count} active connections")
    
    # 프로세스 상태 체크
    print("\n6. SOCKS5 서버 상태:")
    cmd = "systemctl is-active dongle-socks5"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    print(f"   Service: {result.stdout.strip()}")
    
    # CPU/메모리 사용률
    cmd = "ps aux | grep dongle_socks5_server.py | grep -v grep"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.stdout:
        parts = result.stdout.split()
        if len(parts) > 3:
            print(f"   CPU: {parts[2]}%")
            print(f"   Memory: {parts[3]}%")

def check_rate_limits():
    """속도 제한 및 차단 패턴 확인"""
    print("\n=== 차단 가능성 분석 ===")
    
    # 1. 동시 연결 수가 너무 많은지
    print("1. 동시 연결 패턴:")
    print("   - 12개 동시 연결은 일반적인 사용 패턴이 아님")
    print("   - 같은 IP에서 짧은 시간에 많은 연결 = 봇으로 의심")
    
    # 2. 연결 패턴
    print("\n2. 연결 특성:")
    print("   - 모두 같은 User-Agent")
    print("   - 동일한 시간대에 집중")
    print("   - 자동화된 패턴")
    
    # 3. 권장사항
    print("\n3. 권장사항:")
    print("   - 연결 간 랜덤 딜레이 추가 (1-5초)")
    print("   - User-Agent 다양화")
    print("   - 동시 연결 수 제한 (4-6개)")
    print("   - 세션 재사용으로 새 연결 최소화")
    print("   - 실제 사용자처럼 행동 패턴 구현")

if __name__ == "__main__":
    analyze_socks5_logs()
    check_rate_limits()