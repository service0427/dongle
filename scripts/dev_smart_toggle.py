#!/usr/bin/env python3
"""
스마트 토글 v2 - 단순화 버전
빠른 체크 → 실패시 바로 재부팅 → 라우팅

목표: 75초 이내 완료
"""

import sys
import json
import time
import subprocess
from datetime import datetime
from huawei_lte_api.Client import Client
from huawei_lte_api.Connection import Connection

# 설정
USERNAME = "admin"
PASSWORD = "KdjLch!@7024"
TIMEOUT = 5
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
    ts = datetime.now().strftime("%H:%M:%S")
    colors = {"INFO": C.CYN, "OK": C.GRN, "FAIL": C.RED, "WARN": C.YEL, "STEP": C.BLU}
    c = colors.get(level, C.R)
    print(f"{C.GRY}{ts}{C.R} [{c}{level:4}{C.R}] {msg}", file=sys.stderr)

def run(cmd, timeout=10):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r
    except:
        return None


class SmartToggle:
    def __init__(self, subnet):
        self.subnet = subnet
        self.interface = None
        self.gateway = f"192.168.{subnet}.1"
        self.local_ip = f"192.168.{subnet}.100"
        self.result = {
            'success': False,
            'ip': None,
            'traffic': {'upload': 0, 'download': 0},
            'signal': None,
            'step': 0
        }

    def quick_check(self):
        """빠른 연결 체크 (5초 이내)"""
        log(f"{'─'*50}", "STEP")
        log("빠른 연결 체크", "STEP")
        log(f"{'─'*50}", "STEP")

        # 1. 인터페이스 확인
        r = run(f"ip addr | grep '{self.local_ip}' -B2 | head -1 | cut -d: -f2 | tr -d ' '")
        self.interface = r.stdout.strip() if r else ""

        if not self.interface:
            log(f"{C.RED}✗ 인터페이스 없음{C.R}", "FAIL")
            return "NO_INTERFACE"
        log(f"인터페이스: {self.interface}", "OK")

        # 2. 게이트웨이 핑 (2초)
        r = run(f"ping -c 1 -W 2 {self.gateway}", timeout=3)
        if not r or r.returncode != 0:
            log(f"{C.RED}✗ 게이트웨이 응답 없음{C.R}", "FAIL")
            return "GATEWAY_FAIL"
        log(f"게이트웨이 핑 OK", "OK")

        # 3. 외부 연결 (3초) - SOCKS5로 테스트
        port = 10000 + self.subnet
        r = run(f"curl --socks5 127.0.0.1:{port} -s -m 3 https://api.ipify.org", timeout=5)
        ip = r.stdout.strip() if r else ""

        if ip and ip.split('.')[0].isdigit():
            log(f"SOCKS5 연결 OK → {ip}", "OK")
            self.result['ip'] = ip
            return "OK"

        log(f"{C.YEL}△ SOCKS5 연결 실패{C.R}", "WARN")
        return "SOCKS5_FAIL"

    def reboot_dongle(self):
        """동글 재부팅 (API 사용)"""
        log(f"{'─'*50}", "STEP")
        log("동글 재부팅", "STEP")
        log(f"{'─'*50}", "STEP")

        try:
            log("API 재부팅 시도...", "INFO")
            connection = Connection(f'http://{self.gateway}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
            client = Client(connection)
            result = client.device.reboot()

            if result == 'OK' or result == {} or 'OK' in str(result):
                log("API 재부팅 명령 성공", "OK")
                return True
            else:
                log(f"API 응답 이상: {result}", "WARN")
                return True  # 일단 진행

        except Exception as e:
            if "Already login" in str(e):
                log("Already login - 로그아웃 후 재시도", "WARN")
                self.logout_modem()
                time.sleep(2)
                try:
                    connection = Connection(f'http://{self.gateway}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
                    client = Client(connection)
                    client.device.reboot()
                    log("API 재부팅 명령 성공 (재시도)", "OK")
                    return True
                except Exception as e2:
                    log(f"재시도 실패: {e2}", "FAIL")
            else:
                log(f"API 재부팅 실패: {e}", "FAIL")

        # API 실패시 reboot_dongle.py 사용
        log("reboot_dongle.py로 전환...", "INFO")
        r = run(f"python3 /home/proxy/scripts/reboot_dongle.py {self.subnet}", timeout=120)
        return r and r.returncode == 0

    def wait_for_dongle(self, max_wait=60):
        """동글 재부팅 대기"""
        log(f"재부팅 대기 중...", "INFO")

        # 최소 30초는 대기 (재부팅 완료까지 필요)
        log("  30초 필수 대기...", "INFO")
        time.sleep(30)

        # 이후 외부 연결 확인
        for i in range((max_wait - 30) // 5):
            # 게이트웨이 핑
            r = run(f"ping -c 1 -W 2 {self.gateway}", timeout=3)
            if r and r.returncode == 0:
                # 외부 핑도 확인
                r = run(f"ping -c 1 -W 2 8.8.8.8", timeout=3)
                if r and r.returncode == 0:
                    log(f"동글 재시작 완료 ({30 + (i+1)*5}초)", "OK")
                    return True

            time.sleep(5)
            log(f"  대기 중... {30 + (i+1)*5}초", "INFO")

        log(f"{C.YEL}대기 시간 초과, 계속 진행{C.R}", "WARN")
        return True

    def setup_after_reboot(self):
        """재부팅 후 설정: 모뎀 체크 + 라우팅"""
        log(f"{'─'*50}", "STEP")
        log("재부팅 후 설정", "STEP")
        log(f"{'─'*50}", "STEP")

        # 1. 인터페이스 재확인
        r = run(f"ip addr | grep '{self.local_ip}' -B2 | head -1 | cut -d: -f2 | tr -d ' '")
        self.interface = r.stdout.strip() if r else ""

        if not self.interface:
            log(f"{C.RED}✗ 인터페이스 없음 (IP: {self.local_ip}){C.R}", "FAIL")
            # IP 할당 대기 후 재시도
            log("IP 할당 대기 중 (5초)...", "INFO")
            time.sleep(5)
            r = run(f"ip addr | grep '{self.local_ip}' -B2 | head -1 | cut -d: -f2 | tr -d ' '")
            self.interface = r.stdout.strip() if r else ""
            if not self.interface:
                log(f"{C.RED}✗ 인터페이스 여전히 없음{C.R}", "FAIL")
                return False
        log(f"인터페이스: {self.interface}", "OK")

        # 2. 모뎀 로그인 + APN/신호 체크
        try:
            log("모뎀 연결...", "INFO")
            connection = Connection(f'http://{self.gateway}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
            client = Client(connection)

            # APN 체크
            try:
                profiles = client.dial_up.profiles()
                current = profiles.get('CurrentProfile')
                profile_list = profiles.get('Profiles', {}).get('Profile', [])
                if not isinstance(profile_list, list):
                    profile_list = [profile_list]

                current_name = None
                kt_index = None
                for p in profile_list:
                    if p.get('Index') == current:
                        current_name = p.get('Name', '')
                    if p.get('Name', '').lower() == 'kt':
                        kt_index = p.get('Index')

                if current_name and current_name.lower() != 'kt' and kt_index:
                    log(f"APN '{current_name}' → 'KT'로 변경", "WARN")
                    client.dial_up.set_default_profile(kt_index)
                    time.sleep(2)
                else:
                    log(f"APN: {current_name or 'OK'}", "OK")
            except Exception as e:
                log(f"APN 체크 실패 (무시): {e}", "WARN")

            # 신호 체크
            try:
                signal = client.device.signal()
                rsrp = signal.get('rsrp', 'N/A')
                sinr = signal.get('sinr', 'N/A')
                band = signal.get('band', 'N/A')
                log(f"신호: RSRP={rsrp}, SINR={sinr}, Band={band}", "OK")

                # 결과에 저장
                def pv(v):
                    if v is None or v == 'None': return None
                    try: return float(str(v).replace('dBm','').replace('dB','').strip())
                    except: return None

                self.result['signal'] = {
                    'rsrp': pv(signal.get('rsrp')),
                    'rsrq': pv(signal.get('rsrq')),
                    'sinr': pv(signal.get('sinr')),
                    'band': signal.get('band'),
                    'cell_id': signal.get('cell_id'),
                }
            except Exception as e:
                log(f"신호 체크 실패 (무시): {e}", "WARN")

            # 트래픽 정보
            try:
                stats = client.monitoring.traffic_statistics()
                self.result['traffic'] = {
                    'upload': int(stats.get('TotalUpload', 0)),
                    'download': int(stats.get('TotalDownload', 0))
                }
            except:
                pass

        except Exception as e:
            log(f"모뎀 연결 실패 (무시하고 계속): {e}", "WARN")

        # 3. 라우팅 설정 (재시도 포함)
        log("라우팅 설정...", "INFO")

        for attempt in range(3):
            # IP rule 확인/추가
            r = run(f"ip rule show | grep 'from {self.local_ip}'")
            if not r or not r.stdout.strip():
                run(f"ip rule add from {self.local_ip} table {self.subnet}")

            # Default route 삭제 후 재추가 (기존 잘못된 라우트 제거)
            run(f"ip route del default table {self.subnet} 2>/dev/null")
            r = run(f"ip route add default via {self.gateway} dev {self.interface} table {self.subnet}")
            if r and r.returncode != 0 and "File exists" not in (r.stderr or ""):
                log(f"라우팅 추가 실패 (시도 {attempt+1}/3): {r.stderr.strip()}", "WARN")

            # 확인
            time.sleep(0.5)
            r = run(f"ip route show table {self.subnet}")
            if r and f"via {self.gateway}" in r.stdout:
                log("라우팅 설정 완료", "OK")
                break

            if attempt < 2:
                log(f"라우팅 확인 실패, 재시도 {attempt+2}/3...", "WARN")
                time.sleep(1)
        else:
            log(f"{C.RED}라우팅 설정 실패 (3회 시도){C.R}", "FAIL")
            return False

        # 4. SOCKS5 서비스 재시작
        log("SOCKS5 서비스 재시작...", "INFO")
        run(f"systemctl restart dongle-socks5-{self.subnet}")
        time.sleep(2)

        return True

    def verify(self):
        """최종 검증 (3회 재시도)"""
        log(f"{'─'*50}", "STEP")
        log("최종 검증", "STEP")
        log(f"{'─'*50}", "STEP")

        port = 10000 + self.subnet

        # SOCKS5 재시작
        run(f"sudo systemctl restart dongle-socks5-{self.subnet}", timeout=10)
        time.sleep(3)

        # 3회 재시도
        for attempt in range(3):
            r = run(f"curl --socks5 127.0.0.1:{port} -s -m 5 https://api.ipify.org", timeout=10)
            ip = r.stdout.strip() if r else ""

            if ip and ip.split('.')[0].isdigit():
                log(f"SOCKS5 OK → {ip}", "OK")
                self.result['ip'] = ip
                self.result['success'] = True
                return True

            if attempt < 2:
                log(f"SOCKS5 실패, 재시도 {attempt+2}/3...", "WARN")
                time.sleep(3)

        log(f"{C.RED}✗ SOCKS5 검증 실패 (3회 시도){C.R}", "FAIL")
        return False

    def logout_modem(self):
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

    def usb_power_cycle(self):
        """USB 전원 사이클 (인터페이스 없을 때)"""
        log(f"{'─'*50}", "STEP")
        log("USB 전원 사이클", "STEP")
        log(f"{'─'*50}", "STEP")

        # power_control.sh 사용
        log(f"동글 {self.subnet} 전원 OFF...", "INFO")
        r = run(f"/home/proxy/scripts/power_control.sh off {self.subnet}", timeout=30)
        if r and r.returncode == 0:
            log("전원 OFF 성공", "OK")
        else:
            log("전원 OFF 실패 - 계속 진행", "WARN")

        time.sleep(3)

        log(f"동글 {self.subnet} 전원 ON...", "INFO")
        r = run(f"/home/proxy/scripts/power_control.sh on {self.subnet}", timeout=30)
        if r and r.returncode == 0:
            log("전원 ON 성공", "OK")
        else:
            log("전원 ON 실패", "WARN")
            return False

        # usb_modeswitch 실행 (Mass Storage Mode 대응)
        time.sleep(5)
        log("USB 모드 스위치 실행...", "INFO")
        run("usb_modeswitch -c /etc/usb_modeswitch.d/12d1:1f01 2>/dev/null || true", timeout=10)

        return True

    def execute(self):
        """메인 실행"""
        start = time.time()

        log(f"{'='*50}", "STEP")
        log(f"SmartToggle v2 - subnet {self.subnet}", "STEP")
        log(f"{'='*50}", "STEP")

        # 1. 빠른 체크
        status = self.quick_check()

        if status == "OK":
            # 이미 정상 - 트래픽/신호 수집만
            log("정상 상태 - 완료", "OK")
            self.collect_info()
            self.result['success'] = True
            self.result['step'] = 0
            self.print_result(start)
            return self.result

        # 2. 문제 있음 → 재부팅
        log("", "INFO")
        log(f"{C.YEL}문제 감지 ({status}) → 재부팅{C.R}", "WARN")

        if status == "NO_INTERFACE":
            # 인터페이스 없음 → USB 전원 사이클
            self.usb_power_cycle()
            self.wait_for_dongle(90)  # 전원 사이클은 더 오래 대기
        else:
            # 일반 재부팅
            if not self.reboot_dongle():
                log("재부팅 명령 실패, 하지만 계속 진행", "WARN")
            self.wait_for_dongle(60)

        # 4. 재부팅 후 설정
        if not self.setup_after_reboot():
            self.result['step'] = 4  # 실패
            self.print_result(start)
            return self.result

        # 5. 최종 검증
        if self.verify():
            self.result['step'] = 1  # 재부팅 성공
            self.print_result(start)
            return self.result

        # 6. 검증 실패 시 USB 전원 재시작 시도 (fallback)
        if status != "NO_INTERFACE":  # 이미 USB 재시작 안했으면
            log("", "INFO")
            log(f"{C.YEL}API 재부팅 후 검증 실패 → USB 전원 재시작 시도{C.R}", "WARN")
            self.usb_power_cycle()
            self.wait_for_dongle(90)

            # USB 전원 재시작 후 재설정
            if self.setup_after_reboot():
                if self.verify():
                    self.result['step'] = 2  # USB 전원 재시작 성공
                    self.print_result(start)
                    return self.result

        # 실패
        self.result['step'] = 4  # 실패
        self.print_result(start)
        return self.result

    def collect_info(self):
        """트래픽/신호 정보 수집"""
        try:
            connection = Connection(f'http://{self.gateway}/', username=USERNAME, password=PASSWORD, timeout=TIMEOUT)
            client = Client(connection)

            try:
                stats = client.monitoring.traffic_statistics()
                self.result['traffic'] = {
                    'upload': int(stats.get('TotalUpload', 0)),
                    'download': int(stats.get('TotalDownload', 0))
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
                    'sinr': pv(signal.get('sinr')),
                    'band': signal.get('band'),
                    'cell_id': signal.get('cell_id'),
                }
            except:
                pass
        except:
            pass

    def print_result(self, start):
        elapsed = time.time() - start
        log("", "INFO")
        log(f"{'='*50}", "STEP")

        if self.result['success']:
            log(f"{C.GRN}성공: {self.result['ip']}{C.R}", "OK")
        else:
            log(f"{C.RED}실패{C.R}", "FAIL")

        log(f"소요시간: {elapsed:.1f}초", "INFO")
        log(f"{'='*50}", "STEP")


def main():
    if len(sys.argv) < 2:
        print("Usage: dev_smart_toggle.py <subnet>", file=sys.stderr)
        sys.exit(1)

    try:
        subnet = int(sys.argv[1])
        toggle = SmartToggle(subnet)
        result = toggle.execute()

        print(json.dumps(result, ensure_ascii=False))
        sys.exit(0 if result['success'] else 1)

    except Exception as e:
        log(f"오류: {e}", "FAIL")
        import traceback
        traceback.print_exc(file=sys.stderr)
        print(json.dumps({'success': False, 'ip': None, 'traffic': {'upload': 0, 'download': 0}, 'signal': None, 'step': 4}))
        sys.exit(1)


if __name__ == '__main__':
    main()
