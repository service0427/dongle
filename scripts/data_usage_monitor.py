#!/usr/bin/env python3
"""
일일 데이터 사용량 모니터링 및 속도 제한 감지
KT 무제한 요금제: 일 2-3GB 이후 속도 제한 (5Mbps)
"""
import os
import json
import time
import subprocess
from datetime import datetime, date
from pathlib import Path

class DataUsageMonitor:
    def __init__(self):
        self.data_dir = Path("/home/proxy/network-monitor/data")
        self.data_file = self.data_dir / "daily_usage.json"
        self.data_dir.mkdir(exist_ok=True)
        self.load_data()
        
    def load_data(self):
        """저장된 데이터 로드"""
        if self.data_file.exists():
            with open(self.data_file, 'r') as f:
                self.usage_data = json.load(f)
        else:
            self.usage_data = {}
    
    def save_data(self):
        """데이터 저장"""
        with open(self.data_file, 'w') as f:
            json.dump(self.usage_data, f, indent=2)
    
    def get_interface_stats(self, interface):
        """인터페이스 통계"""
        try:
            rx_file = f"/sys/class/net/{interface}/statistics/rx_bytes"
            tx_file = f"/sys/class/net/{interface}/statistics/tx_bytes"
            
            with open(rx_file, 'r') as f:
                rx_bytes = int(f.read().strip())
            with open(tx_file, 'r') as f:
                tx_bytes = int(f.read().strip())
                
            return rx_bytes, tx_bytes
        except:
            return 0, 0
    
    def get_dongle_info(self):
        """활성 동글 정보 가져오기"""
        dongles = {}
        for subnet in range(11, 30):
            cmd = f"ip addr show | grep '192.168.{subnet}.100' | awk '{{print $NF}}'"
            try:
                interface = subprocess.check_output(cmd, shell=True, text=True).strip()
                if interface:
                    dongles[subnet] = interface
            except:
                pass
        return dongles
    
    def update_usage(self):
        """사용량 업데이트"""
        today = str(date.today())
        
        if today not in self.usage_data:
            self.usage_data[today] = {}
        
        dongles = self.get_dongle_info()
        
        for subnet, interface in dongles.items():
            rx_bytes, tx_bytes = self.get_interface_stats(interface)
            total_bytes = rx_bytes + tx_bytes
            
            dongle_key = f"dongle_{subnet}"
            
            if dongle_key not in self.usage_data[today]:
                # 첫 기록
                self.usage_data[today][dongle_key] = {
                    "interface": interface,
                    "start_bytes": total_bytes,
                    "current_bytes": total_bytes,
                    "daily_usage": 0,
                    "last_update": datetime.now().isoformat(),
                    "speed_limited": False,
                    "limit_detected_at": None
                }
            else:
                # 업데이트
                data = self.usage_data[today][dongle_key]
                daily_usage = total_bytes - data["start_bytes"]
                data["current_bytes"] = total_bytes
                data["daily_usage"] = daily_usage
                data["last_update"] = datetime.now().isoformat()
                
                # 속도 제한 감지 (2GB 이상 사용 시)
                if daily_usage > 2 * 1024 * 1024 * 1024:  # 2GB
                    if not data["speed_limited"]:
                        # 속도 테스트
                        if self.check_speed_limit(interface):
                            data["speed_limited"] = True
                            data["limit_detected_at"] = datetime.now().isoformat()
        
        self.save_data()
    
    def check_speed_limit(self, interface):
        """속도 제한 감지 (5Mbps 이하인지 체크)"""
        # 간단한 속도 측정
        time.sleep(1)
        rx1, tx1 = self.get_interface_stats(interface)
        time.sleep(2)
        rx2, tx2 = self.get_interface_stats(interface)
        
        rx_speed = (rx2 - rx1) / 2  # bytes per second
        speed_mbps = (rx_speed * 8) / (1024 * 1024)  # Mbps
        
        return speed_mbps < 6  # 5Mbps 근처면 제한으로 판단
    
    def get_status(self):
        """현재 상태 반환"""
        today = str(date.today())
        if today not in self.usage_data:
            return {"error": "No data for today"}
        
        status = {
            "date": today,
            "dongles": {}
        }
        
        for dongle_key, data in self.usage_data[today].items():
            subnet = dongle_key.split('_')[1]
            usage_gb = data["daily_usage"] / (1024 * 1024 * 1024)
            
            status["dongles"][subnet] = {
                "daily_usage_gb": round(usage_gb, 2),
                "speed_limited": data["speed_limited"],
                "limit_detected_at": data["limit_detected_at"],
                "warning": usage_gb > 1.5,  # 1.5GB 이상이면 경고
                "critical": usage_gb > 2.0   # 2GB 이상이면 위험
            }
        
        return status
    
    def auto_toggle_if_limited(self, subnet):
        """속도 제한 시 자동 토글"""
        today = str(date.today())
        dongle_key = f"dongle_{subnet}"
        
        if (today in self.usage_data and 
            dongle_key in self.usage_data[today] and
            self.usage_data[today][dongle_key]["speed_limited"]):
            
            print(f"[경고] 동글 {subnet} 속도 제한 감지! IP 변경 시도...")
            
            # 토글 API 호출
            try:
                import requests
                response = requests.get(f"http://localhost:8080/toggle/{subnet}", timeout=60)
                if response.status_code == 200:
                    print(f"동글 {subnet} IP 변경 완료")
                    # 제한 상태 리셋
                    self.usage_data[today][dongle_key]["speed_limited"] = False
                    self.usage_data[today][dongle_key]["start_bytes"] = 0
                    self.save_data()
            except Exception as e:
                print(f"토글 실패: {e}")

def main():
    monitor = DataUsageMonitor()
    
    print("=== 일일 데이터 사용량 모니터 ===")
    print("KT 무제한: 일 2-3GB 이후 5Mbps 속도 제한")
    print("자동 감지 및 IP 변경 기능 포함")
    print("")
    
    while True:
        monitor.update_usage()
        status = monitor.get_status()
        
        os.system('clear')
        print(f"\n=== 데이터 사용량 현황 - {datetime.now().strftime('%H:%M:%S')} ===")
        print(f"날짜: {status['date']}\n")
        
        for subnet, info in sorted(status['dongles'].items()):
            print(f"동글 {subnet}:")
            print(f"  일일 사용량: {info['daily_usage_gb']} GB")
            
            if info['critical']:
                print("  ⚠️  경고: 2GB 초과! 속도 제한 가능성 높음")
            elif info['warning']:
                print("  ⚠️  주의: 1.5GB 초과")
            
            if info['speed_limited']:
                print(f"  🚫 속도 제한 감지됨! ({info['limit_detected_at']})")
                # 자동 토글 옵션
                monitor.auto_toggle_if_limited(subnet)
            
            print()
        
        # 자정에 리셋
        if datetime.now().hour == 0 and datetime.now().minute == 0:
            print("자정 - 일일 사용량 리셋")
            monitor.usage_data = {}
            monitor.save_data()
        
        time.sleep(60)  # 1분마다 체크

if __name__ == "__main__":
    main()