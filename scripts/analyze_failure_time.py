#!/usr/bin/env python3
"""
SOCKS5 프록시 실패 시간대 분석 스크립트
문제 발생 시간을 입력하면 전후 30분 데이터를 분석하여 원인 파악

사용법:
  ./analyze_failure_time.py "2025-08-20 14:30"
  ./analyze_failure_time.py "2025-08-20 14:30" --detailed
"""

import json
import sys
import os
from datetime import datetime, timedelta
from pathlib import Path
import statistics
from collections import defaultdict

class Colors:
    """컬러 출력을 위한 ANSI 코드"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def load_metrics(base_dir, start_time, end_time):
    """지정된 시간 범위의 메트릭 파일들을 로드"""
    metrics = []
    current = start_time
    
    while current <= end_time:
        date_str = current.strftime("%Y-%m-%d")
        time_str = current.strftime("%H-%M")
        file_path = Path(base_dir) / date_str / f"metrics_{time_str}.json"
        
        if file_path.exists():
            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)
                    metrics.append(data)
            except:
                pass
        
        current += timedelta(minutes=1)
    
    return metrics

def analyze_trend(values, threshold_percent=20):
    """값들의 추세를 분석하여 급격한 변화 감지"""
    if len(values) < 3:
        return None
    
    # 이동 평균 계산
    window_size = min(5, len(values) // 2)
    moving_avg = []
    for i in range(len(values) - window_size + 1):
        avg = sum(values[i:i+window_size]) / window_size
        moving_avg.append(avg)
    
    # 급격한 변화 감지
    changes = []
    for i in range(1, len(moving_avg)):
        if moving_avg[i-1] > 0:
            change_percent = ((moving_avg[i] - moving_avg[i-1]) / moving_avg[i-1]) * 100
            if abs(change_percent) > threshold_percent:
                changes.append((i, change_percent))
    
    return changes

def analyze_metrics(metrics, failure_time):
    """메트릭 데이터 분석"""
    if not metrics:
        print(f"{Colors.RED}데이터가 없습니다!{Colors.ENDC}")
        return
    
    # 시간별 데이터 정리
    timeline = []
    memory_usage = []
    conntrack_count = []
    time_wait_count = []
    ephemeral_usage = []
    socks5_memory = defaultdict(list)
    socks5_connections = defaultdict(list)
    # 네트워크 버퍼 관련 추가
    main_rx_drops = []
    dongle_total_drops = []
    softnet_dropped = []
    ring_rx_sizes = []
    # TCP/TLS 관련 추가
    tcp_timestamps_vals = []
    https_established = []
    https_time_wait = []
    tcp_retrans = []
    
    for m in metrics:
        timestamp = datetime.strptime(m['timestamp'], "%Y-%m-%d_%H:%M:%S")
        timeline.append(timestamp)
        
        # 시스템 메모리
        memory_usage.append(m['system']['memory']['percent'])
        
        # Conntrack
        conntrack_count.append(m['conntrack']['count'])
        time_wait_count.append(m['conntrack']['time_wait'])
        
        # Ephemeral 포트
        ephemeral_usage.append(m['ephemeral_ports']['percent'])
        
        # SOCKS5 프로세스별
        for proc in m.get('socks5_processes', []):
            subnet = proc['subnet']
            socks5_memory[subnet].append(proc['memory_mb'])
            socks5_connections[subnet].append(proc['connections'])
        
        # 네트워크 버퍼 데이터 (있는 경우만)
        if 'network_buffers' in m:
            nb = m['network_buffers']
            main_rx_drops.append(nb['main_interface']['rx_dropped'])
            dongle_total_drops.append(nb['dongle_total_drops'])
            softnet_dropped.append(nb['softnet_stat']['dropped'])
            ring_rx_sizes.append(nb['main_interface']['ring_rx'])
        
        # TCP/TLS 데이터 (있는 경우만)
        if 'tcp_tls_metrics' in m:
            ttm = m['tcp_tls_metrics']
            tcp_timestamps_vals.append(ttm['settings']['timestamps'])
            https_established.append(ttm['statistics']['https_established'])
            https_time_wait.append(ttm['statistics']['https_time_wait'])
            tcp_retrans.append(ttm['statistics']['retransmissions'])
    
    print(f"\n{Colors.BLUE}{'='*80}{Colors.ENDC}")
    print(f"{Colors.BOLD}SOCKS5 실패 분석 리포트{Colors.ENDC}")
    print(f"문제 발생 시간: {failure_time}")
    print(f"분석 범위: {timeline[0]} ~ {timeline[-1]}")
    print(f"{Colors.BLUE}{'='*80}{Colors.ENDC}\n")
    
    # 1. 급격한 변화 감지
    print(f"{Colors.BOLD}1. 급격한 변화 감지 (20% 이상 변화){Colors.ENDC}")
    
    # TIME_WAIT 분석
    time_wait_changes = analyze_trend(time_wait_count)
    if time_wait_changes:
        print(f"{Colors.YELLOW}  TIME_WAIT 급증 감지:{Colors.ENDC}")
        for idx, change in time_wait_changes:
            time_point = timeline[idx]
            print(f"    {time_point.strftime('%H:%M')}: {change:+.1f}% 변화")
    
    # Ephemeral 포트 분석
    ephemeral_changes = analyze_trend(ephemeral_usage)
    if ephemeral_changes:
        print(f"{Colors.YELLOW}  Ephemeral 포트 사용률 급증:{Colors.ENDC}")
        for idx, change in ephemeral_changes:
            time_point = timeline[idx]
            print(f"    {time_point.strftime('%H:%M')}: {change:+.1f}% 변화")
    
    # 패킷 드롭 분석 (데이터가 있는 경우)
    if main_rx_drops:
        rx_drop_changes = analyze_trend(main_rx_drops, threshold_percent=50)
        if rx_drop_changes:
            print(f"{Colors.YELLOW}  메인 인터페이스 RX 드롭 급증:{Colors.ENDC}")
            for idx, change in rx_drop_changes:
                time_point = timeline[idx]
                print(f"    {time_point.strftime('%H:%M')}: {change:+.1f}% 변화")
        
        dongle_drop_changes = analyze_trend(dongle_total_drops, threshold_percent=50)
        if dongle_drop_changes:
            print(f"{Colors.YELLOW}  동글 인터페이스 드롭 급증:{Colors.ENDC}")
            for idx, change in dongle_drop_changes:
                time_point = timeline[idx]
                print(f"    {time_point.strftime('%H:%M')}: {change:+.1f}% 변화")
    
    # 2. 문제 시점 상태
    failure_idx = -1
    for i, t in enumerate(timeline):
        if t >= failure_time:
            failure_idx = i
            break
    
    if failure_idx >= 0:
        print(f"\n{Colors.BOLD}2. 문제 발생 시점 상태{Colors.ENDC}")
        failure_metrics = metrics[failure_idx]
        
        # 핵심 지표
        print(f"  시스템 메모리: {failure_metrics['system']['memory']['percent']:.1f}%")
        print(f"  Conntrack: {failure_metrics['conntrack']['count']} / {failure_metrics['conntrack']['max']}")
        print(f"  TIME_WAIT: {failure_metrics['conntrack']['time_wait']}")
        print(f"  ESTABLISHED: {failure_metrics['conntrack']['established']}")
        print(f"  Ephemeral 포트: {failure_metrics['ephemeral_ports']['percent']:.1f}% 사용")
        print(f"  TCP TIME_WAIT: {failure_metrics['tcp_sockets']['time_wait']}")
        
        # 네트워크 버퍼 상태 (데이터가 있는 경우)
        if 'network_buffers' in failure_metrics:
            nb = failure_metrics['network_buffers']
            print(f"\n  네트워크 버퍼 상태:")
            print(f"    메인 인터페이스 RX 드롭: {nb['main_interface']['rx_dropped']}")
            print(f"    동글 총 드롭: {nb['dongle_total_drops']}")
            print(f"    Ring 버퍼 크기: RX={nb['main_interface']['ring_rx']}, TX={nb['main_interface']['ring_tx']}")
            print(f"    Softnet 드롭: {nb['softnet_stat']['dropped']}")
            print(f"    netdev_max_backlog: {nb['netdev_max_backlog']}")
        
        # TCP/TLS 상태 (데이터가 있는 경우)
        if 'tcp_tls_metrics' in failure_metrics:
            ttm = failure_metrics['tcp_tls_metrics']
            print(f"\n  TCP/TLS 상태:")
            print(f"    TCP 타임스탬프: {'활성화' if ttm['settings']['timestamps'] else '비활성화'}")
            print(f"    혼잡 제어: {ttm['settings']['congestion_control']}")
            print(f"    HTTPS ESTABLISHED: {ttm['statistics']['https_established']}")
            print(f"    HTTPS TIME_WAIT: {ttm['statistics']['https_time_wait']}")
            print(f"    TCP 재전송: {ttm['statistics']['retransmissions']}")
        
        # 위험 수준 판단
        if failure_metrics['ephemeral_ports']['percent'] > 80:
            print(f"\n  {Colors.RED}⚠ Ephemeral 포트 고갈 위험!{Colors.ENDC}")
        if failure_metrics['conntrack']['time_wait'] > 2000:
            print(f"  {Colors.RED}⚠ TIME_WAIT 과다!{Colors.ENDC}")
        if failure_metrics['conntrack']['count'] > failure_metrics['conntrack']['max'] * 0.8:
            print(f"  {Colors.RED}⚠ Conntrack 테이블 포화!{Colors.ENDC}")
        
        # 네트워크 버퍼 위험 판단
        if 'network_buffers' in failure_metrics:
            nb = failure_metrics['network_buffers']
            if nb['main_interface']['rx_dropped'] > 10000:
                print(f"  {Colors.RED}⚠ 메인 인터페이스 패킷 드롭 과다!{Colors.ENDC}")
            if nb['main_interface']['ring_rx'] < 1024:
                print(f"  {Colors.YELLOW}⚠ Ring 버퍼 크기 작음 (권장: 4096){Colors.ENDC}")
            if nb['netdev_max_backlog'] < 5000:
                print(f"  {Colors.YELLOW}⚠ netdev_max_backlog 작음 (권장: 5000){Colors.ENDC}")
        
        # TLS 감지 위험 판단
        if 'tcp_tls_metrics' in failure_metrics:
            ttm = failure_metrics['tcp_tls_metrics']
            if ttm['settings']['timestamps'] == 1:
                print(f"  {Colors.YELLOW}⚠ TCP 타임스탬프 활성화 (TLS 감지 위험){Colors.ENDC}")
            if ttm['statistics']['https_time_wait'] > 500:
                print(f"  {Colors.YELLOW}⚠ HTTPS TIME_WAIT 과다 (쿠팡 차단 의심){Colors.ENDC}")
    
    # 3. 30분 전후 비교
    print(f"\n{Colors.BOLD}3. 문제 전후 30분 비교{Colors.ENDC}")
    
    # 처음 5분 평균 vs 마지막 5분 평균
    if len(metrics) >= 10:
        first_5 = metrics[:5]
        last_5 = metrics[-5:]
        
        # TIME_WAIT 비교
        first_tw = sum(m['conntrack']['time_wait'] for m in first_5) / 5
        last_tw = sum(m['conntrack']['time_wait'] for m in last_5) / 5
        tw_increase = ((last_tw - first_tw) / first_tw * 100) if first_tw > 0 else 0
        
        print(f"  TIME_WAIT: {first_tw:.0f} → {last_tw:.0f} ({tw_increase:+.1f}%)")
        
        # Ephemeral 포트 비교
        first_eph = sum(m['ephemeral_ports']['percent'] for m in first_5) / 5
        last_eph = sum(m['ephemeral_ports']['percent'] for m in last_5) / 5
        eph_increase = last_eph - first_eph
        
        print(f"  Ephemeral 포트: {first_eph:.1f}% → {last_eph:.1f}% ({eph_increase:+.1f}%p)")
        
        # Conntrack 비교
        first_conn = sum(m['conntrack']['count'] for m in first_5) / 5
        last_conn = sum(m['conntrack']['count'] for m in last_5) / 5
        conn_increase = ((last_conn - first_conn) / first_conn * 100) if first_conn > 0 else 0
        
        print(f"  Conntrack: {first_conn:.0f} → {last_conn:.0f} ({conn_increase:+.1f}%)")
    
    # 4. SOCKS5 프로세스별 분석
    print(f"\n{Colors.BOLD}4. SOCKS5 프로세스별 이상 징후{Colors.ENDC}")
    
    for subnet in sorted(socks5_memory.keys()):
        mem_values = socks5_memory[subnet]
        conn_values = socks5_connections[subnet]
        
        if mem_values:
            max_mem = max(mem_values)
            avg_mem = sum(mem_values) / len(mem_values)
            
            if max_mem > 500:
                print(f"  Subnet {subnet}: {Colors.RED}메모리 과다 사용 (최대 {max_mem}MB){Colors.ENDC}")
            elif max_mem > avg_mem * 2:
                print(f"  Subnet {subnet}: {Colors.YELLOW}메모리 급증 (평균 {avg_mem:.0f}MB → 최대 {max_mem}MB){Colors.ENDC}")
        
        if conn_values:
            max_conn = max(conn_values)
            if max_conn == 0 and len(conn_values) > 10:
                print(f"  Subnet {subnet}: {Colors.RED}연결 없음 (서비스 중단 의심){Colors.ENDC}")
    
    # 5. 가능한 원인 진단
    print(f"\n{Colors.BOLD}5. 가능한 원인 진단{Colors.ENDC}")
    
    causes = []
    
    if failure_idx >= 0:
        fm = metrics[failure_idx]
        
        # Ephemeral 포트 고갈
        if fm['ephemeral_ports']['percent'] > 70:
            causes.append(("HIGH", "Ephemeral 포트 고갈", f"{fm['ephemeral_ports']['percent']:.1f}% 사용"))
        
        # TIME_WAIT 과다
        if fm['conntrack']['time_wait'] > 1500:
            causes.append(("HIGH", "TIME_WAIT 과다", f"{fm['conntrack']['time_wait']}개"))
        
        # Conntrack 포화
        if fm['conntrack']['count'] > fm['conntrack']['max'] * 0.7:
            causes.append(("MEDIUM", "Conntrack 테이블 포화 임박", 
                          f"{fm['conntrack']['count']}/{fm['conntrack']['max']}"))
        
        # 메모리 부족
        if fm['system']['memory']['percent'] > 90:
            causes.append(("HIGH", "시스템 메모리 부족", f"{fm['system']['memory']['percent']:.1f}%"))
        
        # 네트워크 버퍼 문제
        if 'network_buffers' in fm:
            nb = fm['network_buffers']
            if nb['main_interface']['rx_dropped'] > 10000:
                causes.append(("HIGH", "네트워크 패킷 드롭", 
                              f"RX 드롭: {nb['main_interface']['rx_dropped']}"))
            if nb['softnet_stat']['dropped'] > 0:
                causes.append(("MEDIUM", "Softnet 패킷 드롭", 
                              f"{nb['softnet_stat']['dropped']}개"))
            if nb['main_interface']['ring_rx'] < 512:
                causes.append(("MEDIUM", "Ring 버퍼 크기 부족", 
                              f"RX={nb['main_interface']['ring_rx']}"))
        
        # TLS 감지 문제
        if 'tcp_tls_metrics' in fm:
            ttm = fm['tcp_tls_metrics']
            if ttm['settings']['timestamps'] == 1:
                causes.append(("HIGH", "TLS 핑거프린팅 감지 위험", 
                              "TCP 타임스탬프 활성화"))
            if ttm['statistics']['https_time_wait'] > 500:
                causes.append(("HIGH", "HTTPS 연결 차단 의심", 
                              f"TIME_WAIT: {ttm['statistics']['https_time_wait']}"))
    
    if causes:
        for severity, cause, detail in sorted(causes, key=lambda x: x[0]):
            color = Colors.RED if severity == "HIGH" else Colors.YELLOW
            print(f"  {color}[{severity}] {cause}: {detail}{Colors.ENDC}")
    else:
        print(f"  {Colors.GREEN}명확한 시스템 레벨 원인은 발견되지 않음{Colors.ENDC}")
        print(f"  다른 가능성: 네트워크 이슈, 동글 하드웨어 문제, ISP 차단 등")
    
    # 6. 권장 조치
    print(f"\n{Colors.BOLD}6. 권장 조치사항{Colors.ENDC}")
    
    if any(c[0] == "HIGH" for c in causes):
        print(f"  1. 즉시 SOCKS5 서비스 재시작:")
        print(f"     /home/proxy/scripts/socks5/manage_socks5.sh restart all")
        
        if any("Ephemeral" in c[1] for c in causes):
            print(f"  2. Ephemeral 포트 범위 확대:")
            print(f"     echo '15000 65000' > /proc/sys/net/ipv4/ip_local_port_range")
        
        if any("TIME_WAIT" in c[1] for c in causes):
            print(f"  3. TIME_WAIT 타임아웃 단축:")
            print(f"     /home/proxy/scripts/optimize_time_wait.sh")
        
        if any("패킷 드롭" in c[1] or "Ring 버퍼" in c[1] for c in causes):
            print(f"  4. 네트워크 버퍼 최적화:")
            print(f"     # Ring 버퍼 증가")
            print(f"     sudo ethtool -G eno1 rx 4096 tx 4096")
            print(f"     # netdev_max_backlog 증가")
            print(f"     echo 5000 > /proc/sys/net/core/netdev_max_backlog")
    else:
        print(f"  시스템 레벨 문제가 명확하지 않으므로 로그를 더 수집 후 재분석 필요")

def main():
    if len(sys.argv) < 2:
        print("사용법: ./analyze_failure_time.py \"YYYY-MM-DD HH:MM\"")
        print("예: ./analyze_failure_time.py \"2025-08-20 14:30\"")
        sys.exit(1)
    
    try:
        failure_time = datetime.strptime(sys.argv[1], "%Y-%m-%d %H:%M")
    except ValueError:
        print("올바른 시간 형식이 아닙니다. 예: \"2025-08-20 14:30\"")
        sys.exit(1)
    
    # 전후 30분 데이터 로드
    start_time = failure_time - timedelta(minutes=30)
    end_time = failure_time + timedelta(minutes=30)
    
    base_dir = "/home/proxy/logs/metrics"
    metrics = load_metrics(base_dir, start_time, end_time)
    
    if not metrics:
        print(f"{Colors.RED}지정된 시간대의 데이터가 없습니다.{Colors.ENDC}")
        print(f"확인 경로: {base_dir}")
        print(f"검색 범위: {start_time} ~ {end_time}")
        sys.exit(1)
    
    print(f"총 {len(metrics)}개의 데이터 포인트 로드됨")
    
    # 분석 실행
    analyze_metrics(metrics, failure_time)
    
    # 상세 모드
    if "--detailed" in sys.argv:
        print(f"\n{Colors.BOLD}[상세 데이터]{Colors.ENDC}")
        for m in metrics[-5:]:
            print(f"\n{m['timestamp']}:")
            print(f"  TIME_WAIT: {m['conntrack']['time_wait']}")
            print(f"  Ephemeral: {m['ephemeral_ports']['percent']:.1f}%")
            print(f"  Conntrack: {m['conntrack']['count']}")

if __name__ == "__main__":
    main()