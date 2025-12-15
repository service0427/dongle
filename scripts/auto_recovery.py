#!/usr/bin/env python3
"""
자동 리커버리 시스템
- 3분마다 실행 (cron)
- 각 동글 SOCKS5 체크
- 3회 연속 실패 시 자동 복구

사용법:
    python3 auto_recovery.py           # 전체 동글 체크
    python3 auto_recovery.py --status  # 현재 상태 확인
    python3 auto_recovery.py --reset   # 실패 카운터 리셋
"""

import os
import sys
import json
import time
import subprocess
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed

# 설정
CONFIG_FILE = "/home/proxy/config/dongle_config.json"
STATE_FILE = "/home/proxy/logs/recovery_state.json"
LOCK_DIR = "/tmp"
SMART_TOGGLE = "/home/proxy/scripts/dev_smart_toggle.py"

# 파라미터
CHECK_TIMEOUT = 5          # SOCKS5 체크 타임아웃 (초) - 느린 동글 대응
FAIL_THRESHOLD = 3         # 연속 실패 횟수
RECOVERY_COOLDOWN = 15     # 같은 동글 재복구 방지 (분)
MAX_CONCURRENT_RECOVERY = 2  # 동시 복구 최대 수

def log(msg, level="INFO"):
    """로그 출력"""
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"{ts} [{level}] {msg}")

def load_config():
    """동글 설정 로드"""
    try:
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)
            # interface_mapping에서 subnet 번호 추출
            mapping = config.get('interface_mapping', {})
            return [int(s) for s in mapping.keys()]
    except Exception as e:
        log(f"설정 로드 실패: {e}", "ERROR")
        return []

def load_state():
    """상태 파일 로드"""
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE, 'r') as f:
                return json.load(f)
    except:
        pass
    return {}

def save_state(state):
    """상태 파일 저장"""
    try:
        with open(STATE_FILE, 'w') as f:
            json.dump(state, f, indent=2, default=str)
    except Exception as e:
        log(f"상태 저장 실패: {e}", "ERROR")

def check_socks5(subnet):
    """SOCKS5 연결 테스트"""
    port = 10000 + subnet
    try:
        result = subprocess.run(
            f"curl --socks5 127.0.0.1:{port} -s -m {CHECK_TIMEOUT} https://api.ipify.org",
            shell=True, capture_output=True, text=True, timeout=CHECK_TIMEOUT + 2
        )
        ip = result.stdout.strip()
        if ip and ip.split('.')[0].isdigit():
            return True, ip
    except:
        pass
    return False, None

def is_locked(subnet):
    """복구 중인지 확인"""
    lock_file = f"{LOCK_DIR}/recovery_lock_{subnet}"
    if os.path.exists(lock_file):
        try:
            with open(lock_file, 'r') as f:
                lock_time = datetime.fromisoformat(f.read().strip())
                # 5분 이상 지난 락은 무시 (비정상 종료)
                if datetime.now() - lock_time > timedelta(minutes=5):
                    os.remove(lock_file)
                    return False
                return True
        except:
            os.remove(lock_file)
    return False

def set_lock(subnet):
    """복구 락 설정"""
    lock_file = f"{LOCK_DIR}/recovery_lock_{subnet}"
    with open(lock_file, 'w') as f:
        f.write(datetime.now().isoformat())

def remove_lock(subnet):
    """복구 락 해제"""
    lock_file = f"{LOCK_DIR}/recovery_lock_{subnet}"
    try:
        os.remove(lock_file)
    except:
        pass

def can_recover(state, subnet):
    """복구 가능 여부 확인 (쿨다운)"""
    subnet_state = state.get(str(subnet), {})
    last_recovery = subnet_state.get('last_recovery')

    if last_recovery:
        try:
            last_time = datetime.fromisoformat(last_recovery)
            if datetime.now() - last_time < timedelta(minutes=RECOVERY_COOLDOWN):
                return False
        except:
            pass
    return True

def run_recovery(subnet):
    """복구 실행"""
    try:
        set_lock(subnet)
        log(f"{subnet}: 복구 시작...", "RECOVER")

        start = time.time()
        result = subprocess.run(
            f"python3 {SMART_TOGGLE} {subnet}",
            shell=True, capture_output=True, text=True, timeout=120
        )
        elapsed = time.time() - start

        # JSON 결과 파싱
        try:
            output = json.loads(result.stdout.strip())
            if output.get('success'):
                ip = output.get('ip', 'N/A')
                log(f"{subnet}: 복구 성공 ({elapsed:.1f}초) -> {ip}", "RECOVER")
                return True, ip
            else:
                log(f"{subnet}: 복구 실패 ({elapsed:.1f}초)", "RECOVER")
                return False, None
        except:
            log(f"{subnet}: 결과 파싱 실패", "ERROR")
            return False, None

    except subprocess.TimeoutExpired:
        log(f"{subnet}: 복구 타임아웃 (120초)", "ERROR")
        return False, None
    except Exception as e:
        log(f"{subnet}: 복구 오류 - {e}", "ERROR")
        return False, None
    finally:
        remove_lock(subnet)

def main():
    # 옵션 처리
    if len(sys.argv) > 1:
        if sys.argv[1] == "--status":
            state = load_state()
            print(json.dumps(state, indent=2, default=str))
            return
        elif sys.argv[1] == "--reset":
            save_state({})
            log("상태 리셋 완료", "INFO")
            return

    # 설정 로드
    subnets = load_config()
    if not subnets:
        log("활성 동글 없음", "WARN")
        return

    log(f"체크 시작 - {len(subnets)}개 동글", "CHECK")

    # 상태 로드
    state = load_state()

    # 결과 집계
    ok_count = 0
    fail_count = 0
    recover_count = 0
    recovering_subnets = []

    # 병렬 체크
    results = {}
    with ThreadPoolExecutor(max_workers=len(subnets)) as executor:
        futures = {executor.submit(check_socks5, s): s for s in subnets}
        for future in as_completed(futures):
            subnet = futures[future]
            success, ip = future.result()
            results[subnet] = (success, ip)

    # 결과 처리
    for subnet in subnets:
        success, ip = results.get(subnet, (False, None))
        subnet_key = str(subnet)

        if subnet_key not in state:
            state[subnet_key] = {"fail_count": 0}

        if success:
            # 성공 - 카운터 리셋
            state[subnet_key]["fail_count"] = 0
            state[subnet_key]["last_ip"] = ip
            state[subnet_key]["last_check"] = datetime.now().isoformat()
            log(f"{subnet}: {ip}", "OK")
            ok_count += 1
        else:
            # 실패 - 카운터 증가
            state[subnet_key]["fail_count"] = state[subnet_key].get("fail_count", 0) + 1
            state[subnet_key]["last_check"] = datetime.now().isoformat()
            count = state[subnet_key]["fail_count"]

            if count >= FAIL_THRESHOLD:
                # 복구 필요
                if is_locked(subnet):
                    log(f"{subnet}: 연결 실패 ({count}/{FAIL_THRESHOLD}) - 복구 진행 중", "FAIL")
                elif not can_recover(state, subnet):
                    log(f"{subnet}: 연결 실패 ({count}/{FAIL_THRESHOLD}) - 쿨다운 중", "FAIL")
                elif len(recovering_subnets) >= MAX_CONCURRENT_RECOVERY:
                    log(f"{subnet}: 연결 실패 ({count}/{FAIL_THRESHOLD}) - 복구 대기", "FAIL")
                else:
                    recovering_subnets.append(subnet)
                fail_count += 1
            else:
                log(f"{subnet}: 연결 실패 ({count}/{FAIL_THRESHOLD})", "FAIL")
                fail_count += 1

    # 복구 실행
    for subnet in recovering_subnets:
        subnet_key = str(subnet)
        log(f"{subnet}: 연결 실패 ({FAIL_THRESHOLD}/{FAIL_THRESHOLD}) -> 복구 시작", "FAIL")

        success, ip = run_recovery(subnet)

        if success:
            state[subnet_key]["fail_count"] = 0
            state[subnet_key]["last_ip"] = ip
            state[subnet_key]["last_recovery"] = datetime.now().isoformat()
            recover_count += 1
        else:
            state[subnet_key]["last_recovery"] = datetime.now().isoformat()

    # 상태 저장
    save_state(state)

    # 완료 로그
    log(f"체크 완료 - 정상 {ok_count}개, 실패 {fail_count}개, 복구 {recover_count}개", "CHECK")


if __name__ == "__main__":
    main()
