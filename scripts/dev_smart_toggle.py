#!/usr/bin/env python3
"""
스마트 토글 시스템 - 개발/디버그 버전
상세 로그로 문제 원인 분석 가능

사용법:
    python3 dev_smart_toggle.py <subnet>
    python3 dev_smart_toggle.py 20

출력:
    - stderr: 상세 디버그 로그 (색상)
    - stdout: JSON 결과 (기존 호환)

문제 유형별 자동 해결:
    - NO_INTERFACE: USB/전원 문제 → reboot_dongle.py 호출
    - NO_IP_RULE/NO_DEFAULT_ROUTE: 라우팅 자동 추가
    - GATEWAY_UNREACHABLE: 네트워크 토글
    - SOCKS5 문제: 서비스 재시작
"""

import sys
import json
import time
import subprocess
import os
from datetime import datetime
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection

# 설정
USERNAME = "admin"
PASSWORD = "KdjLch!@7024"
TIMEOUT = 10
CONFIG_FILE = "/home/proxy/config/dongle_config.json"

# 색상
class C:
    R = '\033[0m'
    RED = '\033[91m'
    GRN = '\033[92m'
    YEL = '\033[93m'
    BLU = '\033[94m'
    CYN = '\033[96m'
    GRY = '\033[90m'
    BLD = '\033[1m'

def log(msg, level="INFO"):
    """로그 출력 (stderr)"""
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    colors = {
        "INFO": C.CYN, "OK": C.GRN, "FAIL": C.RED,
        "WARN": C.YEL, "STEP": C.BLU, "TIME": C.GRY,
        "HEAD": C.BLD
    }
    c = colors.get(level, C.R)
    print(f"{C.GRY}{ts}{C.R} [{c}{level:4}{C.R}] {msg}", file=sys.stderr)

def run(cmd, timeout=10, show=True):
    """명령 실행 + 로그"""
    start = time.time()
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        elapsed = time.time() - start
        out = r.stdout.strip()
        if show:
            status = f"{C.GRN}OK{C.R}" if r.returncode == 0 else f"{C.RED}FAIL({r.returncode}){C.R}"
            log(f"  $ {cmd[:70]}{'...' if len(cmd)>70 else ''}", "TIME")
            log(f"    → {status} {elapsed:.2f}s | {out[:60] if out else '(empty)'}", "TIME")
        return r
    except subprocess.TimeoutExpired:
        if show:
            log(f"  $ {cmd[:70]} → {C.RED}TIMEOUT{C.R}", "TIME")
        return None
    except Exception as e:
        if show:
            log(f"  $ {cmd[:70]} → {C.RED}ERROR: {e}{C.R}", "TIME")
        return None


class DevSmartToggle:
    def __init__(self, subnet):
        self.subnet = subnet
        self.interface = None
        self.gateway = f"192.168.{subnet}.1"
        self.local_ip = f"192.168.{subnet}.100"
        self.result = {
            'success': False, 'ip': None,
            'traffic': {'upload': 0, 'download': 0},
            'signal': None, 'step': 0
        }
        self.problems = []
        self.analysis = {}

        log(f"{'='*60}", "HEAD")
        log(f"DEV SmartToggle - subnet {subnet}", "HEAD")
        log(f"{'='*60}", "HEAD")

    # ─────────────────────────────────────────────────────────────
    # 1. 사전 분석
    # ─────────────────────────────────────────────────────────────
    def pre_analysis(self):
        """사전 분석: 핑체크부터 문제 원인 파악"""
        log("", "INFO")
        log(f"{'─'*50}", "STEP")
        log("사전 분석 시작", "STEP")
        log(f"{'─'*50}", "STEP")

        self.problems = []
        analysis = {}

        # 1) 인터페이스 확인
        log("1) 인터페이스 확인", "INFO")
        r = run(f"ip addr | grep '{self.local_ip}' -B2 | head -1 | cut -d: -f2 | tr -d ' '")
        self.interface = r.stdout.strip() if r else ""
        analysis['interface'] = self.interface

        if not self.interface:
            log(f"   {C.RED}✗ 인터페이스 없음 → USB/전원 문제{C.R}", "FAIL")
            self.problems.append("NO_INTERFACE")
            self.analysis = analysis
            return analysis

        log(f"   {C.GRN}✓ 인터페이스: {self.interface}{C.R}", "OK")

        # 2) 인터페이스 상태
        log("2) 인터페이스 링크 상태", "INFO")
        r = run(f"ip link show {self.interface} | grep -o 'state [A-Z]*' | awk '{{print $2}}'")
        link_state = r.stdout.strip() if r else ""
        analysis['link_state'] = link_state

        if link_state not in ["UP", "UNKNOWN"]:
            log(f"   {C.RED}✗ 링크 상태: {link_state}{C.R}", "FAIL")
            self.problems.append("LINK_DOWN")
        else:
            log(f"   {C.GRN}✓ 링크 상태: {link_state}{C.R}", "OK")

        # 3) 게이트웨이 핑
        log(f"3) 게이트웨이 핑 ({self.gateway})", "INFO")
        r = run(f"ping -c 1 -W 2 -I {self.interface} {self.gateway}")
        analysis['gateway_ping'] = r and r.returncode == 0

        if not analysis['gateway_ping']:
            log(f"   {C.RED}✗ 게이트웨이 응답 없음{C.R}", "FAIL")
            self.problems.append("GATEWAY_UNREACHABLE")
        else:
            # 응답 시간 추출
            if r:
                import re
                match = re.search(r'time=(\d+\.?\d*)', r.stdout)
                if match:
                    ping_time = float(match.group(1))
                    analysis['gateway_ping_ms'] = ping_time
                    if ping_time > 10:
                        log(f"   {C.YEL}△ 게이트웨이 응답 느림: {ping_time}ms{C.R}", "WARN")
                    else:
                        log(f"   {C.GRN}✓ 게이트웨이 응답: {ping_time}ms{C.R}", "OK")

        # 4) 라우팅 테이블 확인
        log("4) 라우팅 테이블 확인", "INFO")
        r = run(f"ip rule show | grep 'from {self.local_ip}'")
        analysis['ip_rule'] = bool(r and r.stdout.strip())

        if analysis['ip_rule']:
            table = r.stdout.strip().split()[-1]
            analysis['routing_table'] = table

            r = run(f"ip route show table {table} | grep default")
            analysis['default_route'] = bool(r and r.stdout.strip())

            if analysis['default_route']:
                log(f"   {C.GRN}✓ IP rule OK, table {table}, default route OK{C.R}", "OK")
            else:
                log(f"   {C.RED}✗ IP rule OK, but NO default route in table {table}{C.R}", "FAIL")
                self.problems.append("NO_DEFAULT_ROUTE")
        else:
            log(f"   {C.RED}✗ IP rule 없음{C.R}", "FAIL")
            self.problems.append("NO_IP_RULE")
            analysis['routing_table'] = str(self.subnet)
            analysis['default_route'] = False

        # 5) 외부 핑
        log("5) 외부 핑 (8.8.8.8)", "INFO")
        r = run(f"ping -c 1 -W 3 -I {self.interface} 8.8.8.8")
        analysis['external_ping'] = r and r.returncode == 0

        if not analysis['external_ping']:
            log(f"   {C.RED}✗ 외부 핑 실패{C.R}", "FAIL")
            self.problems.append("EXTERNAL_PING_FAIL")
        else:
            if r:
                import re
                match = re.search(r'time=(\d+\.?\d*)', r.stdout)
                if match:
                    ping_time = float(match.group(1))
                    analysis['external_ping_ms'] = ping_time
                    if ping_time > 500:
                        log(f"   {C.YEL}△ 외부 핑 매우 느림: {ping_time}ms{C.R}", "WARN")
                        self.problems.append("SLOW_CONNECTION")
                    elif ping_time > 200:
                        log(f"   {C.YEL}△ 외부 핑 느림: {ping_time}ms{C.R}", "WARN")
                    else:
                        log(f"   {C.GRN}✓ 외부 핑: {ping_time}ms{C.R}", "OK")

        # 6) HTTP 테스트
        log("6) HTTP 연결 테스트", "INFO")
        r = run(f"curl --interface {self.interface} -s -m 10 http://techb.kr/ip.php", timeout=15)
        http_ip = r.stdout.strip() if r else ""
        analysis['http_ok'] = bool(http_ip and http_ip.split('.')[0].isdigit())
        analysis['http_ip'] = http_ip if analysis['http_ok'] else None

        if analysis['http_ok']:
            log(f"   {C.GRN}✓ HTTP OK → {http_ip}{C.R}", "OK")
        else:
            log(f"   {C.RED}✗ HTTP 연결 실패{C.R}", "FAIL")
            self.problems.append("HTTP_FAIL")

        # 7) HTTPS 테스트
        log("7) HTTPS 연결 테스트", "INFO")
        r = run(f"curl --interface {self.interface} -s -m 10 https://api.ipify.org", timeout=15)
        https_ip = r.stdout.strip() if r else ""
        analysis['https_ok'] = bool(https_ip and https_ip.split('.')[0].isdigit())
        analysis['https_ip'] = https_ip if analysis['https_ok'] else None

        if analysis['https_ok']:
            log(f"   {C.GRN}✓ HTTPS OK → {https_ip}{C.R}", "OK")
        else:
            log(f"   {C.RED}✗ HTTPS 연결 실패{C.R}", "FAIL")
            if analysis['http_ok']:
                self.problems.append("HTTPS_ONLY_FAIL")
            else:
                self.problems.append("HTTPS_FAIL")

        # 8) SOCKS5 서비스 상태
        log("8) SOCKS5 서비스 상태", "INFO")
        r = run(f"systemctl is-active dongle-socks5-{self.subnet}")
        analysis['socks5_active'] = r and r.stdout.strip() == "active"

        if analysis['socks5_active']:
            log(f"   {C.GRN}✓ SOCKS5 서비스 active{C.R}", "OK")
        else:
            log(f"   {C.RED}✗ SOCKS5 서비스 inactive{C.R}", "FAIL")
            self.problems.append("SOCKS5_INACTIVE")

        # 9) SOCKS5 프록시 테스트
        if analysis['socks5_active']:
            log("9) SOCKS5 프록시 테스트", "INFO")
            port = 10000 + self.subnet
            r = run(f"curl --socks5 127.0.0.1:{port} -s -m 10 https://api.ipify.org", timeout=15)
            socks_ip = r.stdout.strip() if r else ""
            analysis['socks5_works'] = bool(socks_ip and socks_ip.split('.')[0].isdigit())

            if analysis['socks5_works']:
                log(f"   {C.GRN}✓ SOCKS5 프록시 OK → {socks_ip}{C.R}", "OK")
            else:
                log(f"   {C.RED}✗ SOCKS5 프록시 연결 실패{C.R}", "FAIL")
                self.problems.append("SOCKS5_NOT_WORKING")
        else:
            analysis['socks5_works'] = False

        # 10) 모뎀 신호 상태
        log("10) 모뎀 신호 상태", "INFO")
        try:
            conn = Connection(f'http://{self.gateway}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
            client = Client(conn)
            signal = client.device.signal()

            rsrp = signal.get('rsrp', 'N/A')
            sinr = signal.get('sinr', 'N/A')
            band = signal.get('band', 'N/A')
            cell_id = signal.get('cell_id', 'N/A')

            analysis['signal'] = {
                'rsrp': rsrp, 'sinr': sinr, 'band': band, 'cell_id': cell_id
            }

            # SINR 파싱
            sinr_val = None
            if sinr and sinr != 'N/A':
                try:
                    sinr_val = float(str(sinr).replace('dB', '').strip())
                except:
                    pass

            if sinr_val is not None and sinr_val < -3:
                log(f"   {C.YEL}△ 신호 품질 낮음: RSRP={rsrp}, SINR={sinr}, Band={band}{C.R}", "WARN")
                self.problems.append("LOW_SIGNAL")
            else:
                log(f"   {C.GRN}✓ RSRP={rsrp}, SINR={sinr}, Band={band}, Cell={cell_id}{C.R}", "OK")

        except Exception as e:
            log(f"   {C.RED}✗ 모뎀 API 접근 실패: {e}{C.R}", "FAIL")
            analysis['signal'] = None

        # 현재 IP
        analysis['current_ip'] = analysis.get('https_ip') or analysis.get('http_ip')

        # 결과 요약
        log("", "INFO")
        log(f"{'─'*50}", "INFO")
        log("분석 결과 요약", "INFO")
        log(f"{'─'*50}", "INFO")

        if not self.problems:
            log(f"{C.GRN}모든 체크 통과 - 정상 상태{C.R}", "OK")
        else:
            log(f"발견된 문제 ({len(self.problems)}개):", "WARN")
            for p in self.problems:
                log(f"  • {p}", "WARN")

        self.analysis = analysis
        return analysis

    # ─────────────────────────────────────────────────────────────
    # 2. 복구 단계들
    # ─────────────────────────────────────────────────────────────

    def fix_routing(self):
        """라우팅 문제 수정"""
        log("", "INFO")
        log(f"{'─'*50}", "STEP")
        log("라우팅 수정", "STEP")
        log(f"{'─'*50}", "STEP")

        table = self.analysis.get('routing_table', str(self.subnet))

        # IP rule 추가
        if not self.analysis.get('ip_rule'):
            log(f"IP rule 추가 (table {table})", "INFO")
            run(f"sudo ip rule add from {self.local_ip} table {table}")

        # Default route 추가
        if not self.analysis.get('default_route'):
            log(f"Default route 추가", "INFO")
            run(f"sudo ip route add default via {self.gateway} dev {self.interface} table {table}")

        time.sleep(1)
        r = run(f"ip route show table {table} | grep default")
        success = bool(r and r.stdout.strip())

        if success:
            log(f"{C.GRN}✓ 라우팅 수정 완료{C.R}", "OK")
        else:
            log(f"{C.RED}✗ 라우팅 수정 실패{C.R}", "FAIL")

        return success

    def restart_socks5(self):
        """SOCKS5 서비스 재시작"""
        log("", "INFO")
        log(f"{'─'*50}", "STEP")
        log("SOCKS5 서비스 재시작", "STEP")
        log(f"{'─'*50}", "STEP")

        run(f"sudo systemctl restart dongle-socks5-{self.subnet}", timeout=15)
        time.sleep(3)

        r = run(f"systemctl is-active dongle-socks5-{self.subnet}")
        if r and r.stdout.strip() == "active":
            port = 10000 + self.subnet
            r = run(f"curl --socks5 127.0.0.1:{port} -s -m 10 https://api.ipify.org", timeout=15)
            ip = r.stdout.strip() if r else ""
            if ip and ip.split('.')[0].isdigit():
                self.result['ip'] = ip
                log(f"{C.GRN}✓ SOCKS5 재시작 성공 → {ip}{C.R}", "OK")
                return True

        log(f"{C.RED}✗ SOCKS5 재시작 실패{C.R}", "FAIL")
        return False

    def network_toggle(self):
        """네트워크 토글 (모뎀 API)"""
        log("", "INFO")
        log(f"{'─'*50}", "STEP")
        log("네트워크 토글 (Huawei API)", "STEP")
        log(f"{'─'*50}", "STEP")

        old_ip = self.analysis.get('current_ip')
        log(f"현재 IP: {old_ip}", "INFO")

        try:
            log(f"모뎀 연결: {self.gateway}", "INFO")
            conn_start = time.time()
            connection = Connection(f'http://{self.gateway}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)

            try:
                client = Client(connection)
            except Exception as e:
                if "Already login" in str(e):
                    log("Already login → 로그아웃 후 재연결", "WARN")
                    self.logout_modem()
                    time.sleep(1)
                    connection = Connection(f'http://{self.gateway}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
                    client = Client(connection)
                else:
                    raise

            log(f"모뎀 연결 완료 ({time.time()-conn_start:.2f}s)", "OK")

            log("네트워크 모드 조회...", "INFO")
            current_mode = client.net.net_mode()
            log(f"현재 모드: {current_mode.get('NetworkMode')}", "INFO")

            log("AUTO(00) 모드로 전환...", "INFO")
            client.net.set_net_mode(
                networkmode='00',
                networkband=current_mode['NetworkBand'],
                lteband=current_mode['LTEBand']
            )
            time.sleep(3)

            log("LTE(03) 모드로 전환...", "INFO")
            client.net.set_net_mode(
                networkmode='03',
                networkband=current_mode['NetworkBand'],
                lteband=current_mode['LTEBand']
            )

            log("IP 변경 대기 (최대 30초)...", "INFO")
            for i in range(30):
                time.sleep(1)
                new_ip = self.get_external_ip()

                if new_ip and new_ip != old_ip:
                    log(f"{C.GRN}IP 변경됨: {old_ip} → {new_ip}{C.R}", "OK")
                    self.result['ip'] = new_ip
                    self.collect_modem_info(client)
                    return True

                if i % 5 == 4:
                    log(f"  대기 중... {i+1}s (현재: {new_ip or 'N/A'})", "TIME")

            final_ip = self.get_external_ip()
            if final_ip and final_ip != old_ip:
                self.result['ip'] = final_ip
                self.collect_modem_info(client)
                return True

            log(f"{C.RED}30초 타임아웃, IP 미변경{C.R}", "FAIL")
            return False

        except Exception as e:
            log(f"{C.RED}토글 예외: {e}{C.R}", "FAIL")
            return False

    def reboot_dongle(self):
        """동글 재부팅 (reboot_dongle.py 호출)"""
        log("", "INFO")
        log(f"{'─'*50}", "STEP")
        log("동글 재부팅 (reboot_dongle.py)", "STEP")
        log(f"{'─'*50}", "STEP")

        reboot_script = "/home/proxy/scripts/reboot_dongle.py"
        if not os.path.exists(reboot_script):
            log(f"{C.RED}reboot_dongle.py 없음{C.R}", "FAIL")
            return False

        log("reboot_dongle.py 실행...", "INFO")
        r = run(f"python3 {reboot_script} {self.subnet}", timeout=120, show=False)

        if r:
            # 출력 로그
            for line in r.stdout.split('\n')[-10:]:
                if line.strip():
                    log(f"  {line}", "TIME")

        if r and r.returncode == 0:
            log("재부팅 명령 성공, 90초 대기...", "INFO")
            time.sleep(90)

            # 재분석
            self.pre_analysis()

            if self.check_connectivity():
                log(f"{C.GRN}✓ 재부팅 후 복구 성공{C.R}", "OK")
                return True

        log(f"{C.RED}✗ 재부팅 후에도 복구 실패{C.R}", "FAIL")
        return False

    # ─────────────────────────────────────────────────────────────
    # 3. 유틸리티
    # ─────────────────────────────────────────────────────────────

    def check_connectivity(self):
        """연결 확인"""
        if not self.interface:
            r = run(f"ip addr | grep '{self.local_ip}' -B2 | head -1 | cut -d: -f2 | tr -d ' '", show=False)
            self.interface = r.stdout.strip() if r else ""
            if not self.interface:
                return False

        try:
            r = subprocess.run(
                f"curl --interface {self.interface} -s -m 5 https://api.ipify.org",
                shell=True, capture_output=True, text=True, timeout=10
            )
            ip = r.stdout.strip()
            if ip and ip.split('.')[0].isdigit():
                self.result['ip'] = ip
                return True
        except:
            pass
        return False

    def get_external_ip(self):
        """외부 IP 확인"""
        if not self.interface:
            return None

        try:
            r = subprocess.run(
                f"curl --interface {self.interface} -s -m 5 https://api.ipify.org",
                shell=True, capture_output=True, text=True, timeout=10
            )
            ip = r.stdout.strip()
            if ip and ip.split('.')[0].isdigit():
                return ip
        except:
            pass

        try:
            r = subprocess.run(
                f"curl --interface {self.interface} -s -m 5 http://techb.kr/ip.php",
                shell=True, capture_output=True, text=True, timeout=10
            )
            ip = r.stdout.strip()
            if ip and ip.split('.')[0].isdigit():
                return ip
        except:
            pass

        return None

    def logout_modem(self):
        """모뎀 로그아웃"""
        try:
            import requests
            requests.post(
                f'http://{self.gateway}/api/user/logout',
                data='<?xml version="1.0" encoding="UTF-8"?><request><Logout>1</Logout></request>',
                headers={'Content-Type': 'application/xml'},
                timeout=2
            )
        except:
            pass

    def collect_modem_info(self, client):
        """모뎀 정보 수집"""
        try:
            stats = client.monitoring.traffic_statistics()
            self.result['traffic'] = {
                'upload': int(stats['TotalUpload']),
                'download': int(stats['TotalDownload'])
            }
        except:
            pass

        try:
            signal = client.device.signal()
            def pv(v):
                if v is None or v == 'None': return None
                try: return float(str(v).replace('dBm','').replace('dB','').strip())
                except: return None

            self.result['signal'] = {
                'rsrp': pv(signal.get('rsrp')),
                'rsrq': pv(signal.get('rsrq')),
                'rssi': pv(signal.get('rssi')),
                'sinr': pv(signal.get('sinr')),
                'band': signal.get('band'),
                'cell_id': signal.get('cell_id'),
            }
        except:
            pass

    def verify_socks5(self):
        """SOCKS5 최종 검증"""
        log("SOCKS5 최종 검증...", "INFO")
        port = 10000 + self.subnet
        r = run(f"curl --socks5 127.0.0.1:{port} -s -m 10 https://api.ipify.org", timeout=15)
        ip = r.stdout.strip() if r else ""

        if ip and ip.split('.')[0].isdigit():
            log(f"{C.GRN}✓ SOCKS5 OK → {ip}{C.R}", "OK")
            self.result['ip'] = ip
            return True

        log("SOCKS5 실패, 재시작 시도", "WARN")
        run(f"sudo systemctl restart dongle-socks5-{self.subnet}", timeout=15)
        time.sleep(3)

        r = run(f"curl --socks5 127.0.0.1:{port} -s -m 10 https://api.ipify.org", timeout=15)
        ip = r.stdout.strip() if r else ""
        if ip and ip.split('.')[0].isdigit():
            log(f"{C.GRN}✓ SOCKS5 재시작 후 OK{C.R}", "OK")
            self.result['ip'] = ip
            return True

        log(f"{C.RED}✗ SOCKS5 검증 실패{C.R}", "FAIL")
        return False

    # ─────────────────────────────────────────────────────────────
    # 4. 메인 실행
    # ─────────────────────────────────────────────────────────────

    def execute(self):
        """스마트 토글 실행"""
        total_start = time.time()

        # 1. 사전 분석
        self.pre_analysis()

        # 2. 문제 없으면 토글만
        if not self.problems:
            log("", "INFO")
            log(f"{C.GRN}정상 상태 → 네트워크 토글만 실행{C.R}", "INFO")

            if self.network_toggle():
                if self.verify_socks5():
                    self.result['success'] = True
                    self.result['step'] = 0
                    self.print_result(total_start, "정상 토글")
                    return self.result

        # 3. 문제별 해결

        # 인터페이스 없음 → 재부팅 필요
        if "NO_INTERFACE" in self.problems:
            log("", "INFO")
            log(f"{C.YEL}인터페이스 없음 → 동글 재부팅 필요{C.R}", "WARN")

            if self.reboot_dongle():
                # 라우팅도 확인
                if "NO_IP_RULE" in self.problems or "NO_DEFAULT_ROUTE" in self.problems:
                    self.fix_routing()

                if self.verify_socks5():
                    self.result['success'] = True
                    self.result['step'] = 4
                    self.print_result(total_start, "동글 재부팅")
                    return self.result

            self.result['step'] = 4
            self.print_result(total_start, "실패 - 재부팅 후에도 복구 안됨")
            return self.result

        # SOCKS5만 문제
        if set(self.problems) <= {"SOCKS5_INACTIVE", "SOCKS5_NOT_WORKING"}:
            log("", "INFO")
            log(f"{C.YEL}SOCKS5만 문제 → 서비스 재시작{C.R}", "WARN")

            if self.restart_socks5():
                self.result['success'] = True
                self.result['step'] = 0
                self.print_result(total_start, "SOCKS5 재시작")
                return self.result

        # HTTPS만 안됨
        if "HTTPS_ONLY_FAIL" in self.problems:
            log("", "INFO")
            log(f"{C.YEL}HTTPS만 실패 → SOCKS5 재시작{C.R}", "WARN")

            if self.restart_socks5():
                self.result['success'] = True
                self.result['step'] = 0
                self.print_result(total_start, "SOCKS5 재시작")
                return self.result

        # 라우팅 문제
        if "NO_IP_RULE" in self.problems or "NO_DEFAULT_ROUTE" in self.problems:
            log("", "INFO")
            log(f"{C.YEL}라우팅 문제 → 라우팅 수정{C.R}", "WARN")

            if self.fix_routing():
                time.sleep(2)
                if self.check_connectivity():
                    if self.verify_socks5():
                        self.result['success'] = True
                        self.result['step'] = 1
                        self.print_result(total_start, "라우팅 수정")
                        return self.result

        # 연결 문제 → 토글
        if any(p in self.problems for p in ["GATEWAY_UNREACHABLE", "EXTERNAL_PING_FAIL", "HTTP_FAIL", "SLOW_CONNECTION", "LOW_SIGNAL"]):
            log("", "INFO")
            log(f"{C.YEL}연결/신호 문제 → 네트워크 토글{C.R}", "WARN")

            if self.network_toggle():
                if self.verify_socks5():
                    self.result['success'] = True
                    self.result['step'] = 2
                    self.print_result(total_start, "네트워크 토글")
                    return self.result

            # 토글 실패 → 재부팅
            log("토글 실패 → 동글 재부팅 시도", "WARN")
            if self.reboot_dongle():
                if "NO_IP_RULE" in self.problems or "NO_DEFAULT_ROUTE" in self.problems:
                    self.fix_routing()

                if self.verify_socks5():
                    self.result['success'] = True
                    self.result['step'] = 4
                    self.print_result(total_start, "동글 재부팅")
                    return self.result

        # 모든 시도 실패
        self.result['step'] = 4
        self.print_result(total_start, "모든 시도 실패")
        return self.result

    def print_result(self, start_time, msg):
        """결과 출력"""
        elapsed = time.time() - start_time
        log("", "INFO")
        log(f"{'='*60}", "HEAD")

        if self.result['success']:
            log(f"{C.GRN}토글 성공: {msg}{C.R}", "OK")
            log(f"최종 IP: {self.result.get('ip')}", "OK")
        else:
            log(f"{C.RED}토글 실패: {msg}{C.R}", "FAIL")
            log(f"발견된 문제: {self.problems}", "FAIL")

        log(f"소요 시간: {elapsed:.2f}s", "TIME")
        log(f"{'='*60}", "HEAD")


def main():
    if len(sys.argv) < 2:
        print("Usage: dev_smart_toggle.py <subnet>", file=sys.stderr)
        print("Example: dev_smart_toggle.py 20", file=sys.stderr)
        print("", file=sys.stderr)
        print("출력:", file=sys.stderr)
        print("  stderr: 상세 디버그 로그", file=sys.stderr)
        print("  stdout: JSON 결과", file=sys.stderr)
        sys.exit(1)

    try:
        subnet = int(sys.argv[1])
        if subnet < 11 or subnet > 30:
            raise ValueError('Subnet must be between 11 and 30')

        toggle = DevSmartToggle(subnet)
        result = toggle.execute()

        # JSON 출력 (stdout)
        output = {
            'success': result.get('success', False),
            'ip': result.get('ip'),
            'traffic': result.get('traffic', {'upload': 0, 'download': 0}),
            'signal': result.get('signal'),
            'step': result.get('step', 0)
        }
        print(json.dumps(output, ensure_ascii=False))

        sys.exit(0 if output['success'] else 1)

    except ValueError as e:
        log(f"파라미터 오류: {e}", "FAIL")
        print(json.dumps({'error': str(e)}))
        sys.exit(1)
    except Exception as e:
        log(f"실행 오류: {e}", "FAIL")
        import traceback
        traceback.print_exc(file=sys.stderr)
        print(json.dumps({
            'success': False, 'ip': None,
            'traffic': {'upload': 0, 'download': 0},
            'signal': None, 'step': 4
        }))
        sys.exit(1)


if __name__ == '__main__':
    main()
