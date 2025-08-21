#!/usr/bin/env python3
"""
SOCKS5 프로세스 상세 모니터링 스크립트
각 프로세스의 메모리, CPU, 네트워크, 스레드 등 상세 정보 제공
"""

import psutil
import json
import time
import subprocess
from datetime import datetime, timedelta
from collections import defaultdict
import sys

class Colors:
    """컬러 출력을 위한 ANSI 코드"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def format_bytes(bytes_value):
    """바이트를 읽기 쉬운 형식으로 변환"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_value < 1024.0:
            return f"{bytes_value:.1f} {unit}"
        bytes_value /= 1024.0
    return f"{bytes_value:.1f} PB"

def format_duration(seconds):
    """초를 읽기 쉬운 시간 형식으로 변환"""
    if seconds < 60:
        return f"{seconds:.0f}s"
    elif seconds < 3600:
        return f"{seconds/60:.0f}m"
    elif seconds < 86400:
        return f"{seconds/3600:.1f}h"
    else:
        return f"{seconds/86400:.1f}d"

def get_interface_stats(subnet):
    """네트워크 인터페이스 통계 가져오기"""
    try:
        # 인터페이스 이름 찾기
        result = subprocess.run(['ip', 'addr'], capture_output=True, text=True)
        lines = result.stdout.split('\n')
        interface = None
        
        for i, line in enumerate(lines):
            if f"192.168.{subnet}.100" in line:
                for j in range(i, -1, -1):
                    if ': ' in lines[j] and '<' in lines[j]:
                        interface = lines[j].split(':')[1].strip().split('@')[0]
                        break
                break
        
        if interface and interface in psutil.net_io_counters(pernic=True):
            stats = psutil.net_io_counters(pernic=True)[interface]
            return {
                'interface': interface,
                'bytes_sent': stats.bytes_sent,
                'bytes_recv': stats.bytes_recv,
                'packets_sent': stats.packets_sent,
                'packets_recv': stats.packets_recv,
                'errin': stats.errin,
                'errout': stats.errout,
                'dropin': stats.dropin,
                'dropout': stats.dropout
            }
    except:
        pass
    return None

def analyze_socks5_process(proc, subnet):
    """단일 SOCKS5 프로세스 상세 분석"""
    try:
        p = psutil.Process(proc.pid)
        
        # 기본 정보
        create_time = datetime.fromtimestamp(p.create_time())
        runtime = time.time() - p.create_time()
        
        # 메모리 정보
        mem_info = p.memory_info()
        mem_percent = p.memory_percent()
        
        # CPU 정보
        cpu_percent = p.cpu_percent(interval=0.1)
        cpu_times = p.cpu_times()
        
        # 스레드 정보
        num_threads = p.num_threads()
        
        # 연결 정보 (경고 억제)
        import warnings
        with warnings.catch_warnings():
            warnings.filterwarnings("ignore", category=DeprecationWarning)
            try:
                connections = p.connections()
            except AttributeError:
                # 새 버전의 psutil 사용
                connections = [c for c in psutil.net_connections() if c.pid == p.pid]
        
        conn_states = defaultdict(int)
        unique_ips = set()
        
        for conn in connections:
            if conn.status != 'NONE':
                conn_states[conn.status] += 1
            if conn.raddr:
                unique_ips.add(conn.raddr.ip)
        
        # 파일 디스크립터
        try:
            num_fds = p.num_fds()
        except:
            num_fds = len(p.open_files()) + len(connections)
        
        # I/O 통계
        try:
            io_counters = p.io_counters()
            io_stats = {
                'read_bytes': io_counters.read_bytes,
                'write_bytes': io_counters.write_bytes,
                'read_count': io_counters.read_count,
                'write_count': io_counters.write_count
            }
        except:
            io_stats = None
        
        # 컨텍스트 스위치
        try:
            ctx_switches = p.num_ctx_switches()
            ctx_stats = {
                'voluntary': ctx_switches.voluntary,
                'involuntary': ctx_switches.involuntary
            }
        except:
            ctx_stats = None
        
        return {
            'pid': proc.pid,
            'subnet': subnet,
            'status': p.status(),
            'create_time': create_time,
            'runtime': runtime,
            'memory': {
                'rss': mem_info.rss,
                'vms': mem_info.vms,
                'percent': mem_percent,
                'rss_mb': mem_info.rss / 1048576,
                'vms_mb': mem_info.vms / 1048576
            },
            'cpu': {
                'percent': cpu_percent,
                'user_time': cpu_times.user,
                'system_time': cpu_times.system
            },
            'threads': num_threads,
            'connections': {
                'total': len(connections),
                'states': dict(conn_states),
                'unique_ips': len(unique_ips),
                'ip_list': list(unique_ips)[:5]  # 처음 5개만
            },
            'fds': num_fds,
            'io': io_stats,
            'context_switches': ctx_stats
        }
    except (psutil.NoSuchProcess, psutil.AccessDenied) as e:
        return None

def print_detailed_report(data):
    """상세 리포트 출력"""
    print(f"\n{Colors.HEADER}{'='*80}{Colors.ENDC}")
    print(f"{Colors.BOLD}SOCKS5 Detailed Status Report{Colors.ENDC}")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{Colors.HEADER}{'='*80}{Colors.ENDC}\n")
    
    total_memory = 0
    total_connections = 0
    total_cpu = 0
    process_count = 0
    
    for info in sorted(data, key=lambda x: x['subnet']):
        process_count += 1
        subnet = info['subnet']
        
        print(f"{Colors.BLUE}═══ Subnet {subnet} (PID: {info['pid']}) ═══{Colors.ENDC}")
        
        # 상태 및 런타임
        status_color = Colors.GREEN if info['status'] == 'sleeping' else Colors.YELLOW
        print(f"Status: {status_color}{info['status']}{Colors.ENDC}")
        print(f"Runtime: {format_duration(info['runtime'])} (Started: {info['create_time'].strftime('%H:%M:%S')})")
        
        # 메모리 정보
        mem = info['memory']
        total_memory += mem['rss_mb']
        mem_color = Colors.RED if mem['rss_mb'] > 500 else Colors.YELLOW if mem['rss_mb'] > 300 else Colors.GREEN
        print(f"\nMemory:")
        print(f"  RSS: {mem_color}{mem['rss_mb']:.1f} MB{Colors.ENDC} ({mem['percent']:.1f}%)")
        print(f"  VMS: {mem['vms_mb']:.1f} MB")
        
        # CPU 정보
        cpu = info['cpu']
        total_cpu += cpu['percent']
        cpu_color = Colors.RED if cpu['percent'] > 50 else Colors.YELLOW if cpu['percent'] > 20 else Colors.GREEN
        print(f"\nCPU:")
        print(f"  Usage: {cpu_color}{cpu['percent']:.1f}%{Colors.ENDC}")
        print(f"  User Time: {format_duration(cpu['user_time'])}, System Time: {format_duration(cpu['system_time'])}")
        
        # 스레드 정보
        thread_color = Colors.RED if info['threads'] > 150 else Colors.YELLOW if info['threads'] > 50 else Colors.GREEN
        print(f"\nThreads: {thread_color}{info['threads']}{Colors.ENDC}")
        
        # 연결 정보
        conn = info['connections']
        total_connections += conn['total']
        print(f"\nConnections:")
        print(f"  Total: {conn['total']}")
        if conn['states']:
            print(f"  States: {conn['states']}")
        print(f"  Unique IPs: {conn['unique_ips']}")
        if conn['ip_list']:
            print(f"  Sample IPs: {', '.join(conn['ip_list'][:3])}")
        
        # 파일 디스크립터
        print(f"\nFile Descriptors: {info['fds']}")
        
        # I/O 통계
        if info['io']:
            io = info['io']
            print(f"\nI/O Statistics:")
            print(f"  Read: {format_bytes(io['read_bytes'])} ({io['read_count']} ops)")
            print(f"  Write: {format_bytes(io['write_bytes'])} ({io['write_count']} ops)")
        
        # 컨텍스트 스위치
        if info['context_switches']:
            ctx = info['context_switches']
            print(f"\nContext Switches:")
            print(f"  Voluntary: {ctx['voluntary']:,}, Involuntary: {ctx['involuntary']:,}")
        
        # 네트워크 인터페이스 통계
        net_stats = get_interface_stats(subnet)
        if net_stats:
            print(f"\nNetwork Interface ({net_stats['interface']}):")
            print(f"  TX: {format_bytes(net_stats['bytes_sent'])} ({net_stats['packets_sent']:,} packets)")
            print(f"  RX: {format_bytes(net_stats['bytes_recv'])} ({net_stats['packets_recv']:,} packets)")
            if net_stats['errin'] or net_stats['errout']:
                print(f"  Errors: IN={net_stats['errin']}, OUT={net_stats['errout']}")
            if net_stats['dropin'] or net_stats['dropout']:
                print(f"  Drops: IN={net_stats['dropin']}, OUT={net_stats['dropout']}")
        
        print("")
    
    # 전체 요약
    print(f"{Colors.HEADER}{'='*80}{Colors.ENDC}")
    print(f"{Colors.BOLD}Summary:{Colors.ENDC}")
    print(f"  Processes: {process_count}")
    print(f"  Total Memory: {total_memory:.1f} MB (Avg: {total_memory/process_count:.1f} MB)")
    print(f"  Total CPU: {total_cpu:.1f}% (Avg: {total_cpu/process_count:.1f}%)")
    print(f"  Total Connections: {total_connections}")
    
    # 시스템 리소스
    mem = psutil.virtual_memory()
    cpu_count = psutil.cpu_count()
    print(f"\n{Colors.BOLD}System Resources:{Colors.ENDC}")
    print(f"  System Memory: {mem.percent:.1f}% used ({format_bytes(mem.used)} / {format_bytes(mem.total)})")
    print(f"  System CPU: {psutil.cpu_percent(interval=0.1):.1f}% ({cpu_count} cores)")
    
    # 권장사항
    print(f"\n{Colors.BOLD}Recommendations:{Colors.ENDC}")
    if total_memory/process_count > 100:
        print(f"  {Colors.YELLOW}⚠ Average memory usage is high. Consider monitoring for memory leaks.{Colors.ENDC}")
    if any(d['memory']['rss_mb'] > 300 for d in data):
        print(f"  {Colors.YELLOW}⚠ Some processes exceed 300MB. May need restart soon.{Colors.ENDC}")
    if any(d['threads'] > 100 for d in data):
        print(f"  {Colors.YELLOW}⚠ High thread count detected. Check for thread leaks.{Colors.ENDC}")
    if total_memory/process_count < 50 and total_cpu/process_count < 10:
        print(f"  {Colors.GREEN}✓ All systems healthy and running efficiently.{Colors.ENDC}")

def main():
    """메인 함수"""
    # proxy_state.json에서 활성 서브넷 확인
    active_subnets = []
    try:
        with open('/home/proxy/proxy_state.json', 'r') as f:
            data = json.load(f)
            active_subnets = [int(k) for k in data.keys()]
    except:
        print("Warning: Could not read proxy_state.json, using default range")
        active_subnets = list(range(11, 24))
    
    # SOCKS5 프로세스 찾기 및 분석
    process_data = []
    
    for proc in psutil.process_iter(['pid', 'cmdline']):
        try:
            cmdline = proc.info['cmdline']
            if cmdline and 'socks5_single' in ' '.join(cmdline):
                for arg in cmdline:
                    if arg.isdigit():
                        subnet = int(arg)
                        if subnet in active_subnets:
                            info = analyze_socks5_process(proc, subnet)
                            if info:
                                process_data.append(info)
                            break
        except:
            continue
    
    if not process_data:
        print(f"{Colors.RED}No SOCKS5 processes found!{Colors.ENDC}")
        return
    
    # 리포트 출력
    print_detailed_report(process_data)
    
    # JSON 출력 옵션
    if len(sys.argv) > 1 and sys.argv[1] == '--json':
        # datetime 객체를 문자열로 변환
        for d in process_data:
            d['create_time'] = d['create_time'].isoformat()
        print("\n" + json.dumps(process_data, indent=2))

if __name__ == '__main__':
    main()