#!/usr/bin/env python3
"""
데이터 사용량 조회 스크립트 (API용)
"""
import json
import sys
from data_usage_monitor import DataUsageMonitor

def main():
    try:
        monitor = DataUsageMonitor()
        monitor.update_usage()
        status = monitor.get_status()
        print(json.dumps(status))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)

if __name__ == "__main__":
    main()