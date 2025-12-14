# API Callback 데이터 구조 문서

## 개요

이 문서는 프록시 시스템에서 외부 서버로 전송되는 두 가지 데이터 구조를 설명합니다:

1. **smart_toggle.py** - 개별 동글 토글 시 전송되는 콜백
2. **push_proxy_status.sh** - 전체 프록시 상태 헬스체크 (매분 크론)

---

## 1. smart_toggle.py 콜백

### 콜백 URL

| 환경 | 시작 콜백 | 결과 콜백 |
|------|----------|----------|
| 운영 | `http://61.84.75.37:10002/toggle/start` | `http://61.84.75.37:10002/toggle/result` |
| 개발 | `http://61.84.75.37:44010/toggle/start` | `http://61.84.75.37:44010/toggle/result` |

두 서버에 동시에 전송됩니다.

### 1.1 토글 시작 콜백 (toggle/start)

토글 시작 시 즉시 전송됩니다.

```json
{
  "server_ip": "112.161.54.7",
  "port": 10016
}
```

| 필드 | 타입 | 설명 |
|------|------|------|
| server_ip | string | 프록시 서버 공인 IP (eno1 인터페이스) |
| port | int | SOCKS5 프록시 포트 (10000 + subnet) |

---

### 1.2 토글 결과 콜백 (toggle/result)

#### 성공 케이스

```json
{
  "success": true,
  "ip": "175.223.14.190",
  "traffic": {
    "upload": 7408564242,
    "download": 13143734622
  },
  "signal": {
    "rsrp": -105.0,
    "rsrq": -14.0,
    "rssi": -71.0,
    "sinr": -5.0,
    "band": "3",
    "cell_id": "0029435-012",
    "pci": "372",
    "plmn": "45008"
  },
  "step": 0,
  "server_ip": "112.161.54.7",
  "port": 10016
}
```

#### 실패 케이스

```json
{
  "success": false,
  "ip": null,
  "traffic": {
    "upload": 0,
    "download": 0
  },
  "signal": null,
  "step": 4,
  "server_ip": "112.161.54.7",
  "port": 10011
}
```

### 필드 설명

| 필드 | 타입 | 설명 |
|------|------|------|
| success | bool | 토글 성공 여부 |
| ip | string/null | 새로운 외부 IP (실패 시 null) |
| traffic.upload | int | 누적 업로드 바이트 |
| traffic.download | int | 누적 다운로드 바이트 |
| signal | object/null | LTE 신호 정보 (실패 시 null) |
| signal.rsrp | float | Reference Signal Received Power (dBm) |
| signal.rsrq | float | Reference Signal Received Quality (dB) |
| signal.rssi | float | Received Signal Strength Indicator (dBm) |
| signal.sinr | float | Signal to Interference plus Noise Ratio (dB) |
| signal.band | string | LTE 밴드 번호 |
| signal.cell_id | string | 기지국 셀 ID |
| signal.pci | string | Physical Cell ID |
| signal.plmn | string | Public Land Mobile Network (45008=KT) |
| step | int | 복구 단계 (아래 참조) |
| server_ip | string | 프록시 서버 공인 IP |
| port | int | SOCKS5 프록시 포트 |

### step 값 의미

step은 **어떤 단계에서 IP 할당에 성공했는지**를 나타냅니다.

#### 진단 → 시작 단계 결정

| 진단 결과 | 시작 단계 | 설명 |
|-----------|----------|------|
| 인터페이스 없음 | step 3 | USB 리셋부터 시작 |
| 라우팅/IP rule 없음 | step 1 | 라우팅 복구부터 시작 |
| 외부 연결 안됨 | step 2 | 네트워크 토글부터 시작 |
| 정상 상태 | step 2 | 토글만 실행 (성공 시 step=0) |

#### 결과 step 값

| 값 | 의미 | 설명 |
|----|------|------|
| **0** | 정상 토글 | 진단 결과 정상, 네트워크 토글만으로 IP 변경 성공 (가장 빠름) |
| **1** | 라우팅 복구 | 라우팅 테이블/IP rule 문제 → 복구 후 성공 |
| **2** | 네트워크 토글 | 비정상 상태에서 모뎀 모드 전환으로 복구 성공 |
| **3** | USB 리셋 | USB unbind/bind로 드라이버 재시작 후 성공 |
| **4** | 전원 재시작 | 최대 복구 시도 (성공 또는 실패) |

#### step 값 해석 예시

```
step=0 + success=true  → 정상 상태, 빠른 IP 변경 완료
step=1 + success=true  → 라우팅 문제였으나 복구 성공
step=2 + success=true  → 연결 문제였으나 토글로 복구
step=3 + success=true  → USB 드라이버 문제, 리셋으로 복구
step=4 + success=true  → 전원 재시작으로 복구 성공
step=4 + success=false → 모든 복구 시도 실패
```

---

## 2. push_proxy_status.sh 헬스체크

### 콜백 URL

| 환경 | URL |
|------|-----|
| 운영 | `http://61.84.75.37:3001/api/proxy` |
| 운영 | `http://61.84.75.37:29999/api/proxy` |
| 개발 | `http://61.84.75.37:44010/sync/dongle` |

세 서버에 동시에 전송됩니다.

### 실행 주기
- 크론으로 매분 실행

### 전송 데이터

```json
{
  "status": "ready",
  "timestamp": "2025-12-13 22:56:01",
  "last_heartbeat_at": "2025-12-13T22:56:02.654200",
  "server_ip": "112.161.54.7",
  "available_proxies": [
    {
      "proxy_url": "socks5://112.161.54.7:10016",
      "subnet": 16,
      "external_ip": "175.223.26.202",
      "last_toggle": "2025-12-13 22:49:25",
      "traffic": {
        "upload": 7408510801,
        "download": 13143595860
      },
      "connected": true,
      "toggle_status": {
        "status": "idle",
        "message": "Ready for toggle",
        "last_toggle": "2025-12-13 22:49:25"
      },
      "signal": {
        "rsrp": -105,
        "rsrq": -9,
        "rssi": -79,
        "sinr": -2,
        "band": "3",
        "cell_id": "0029403-030",
        "pci": "228",
        "plmn": "45008"
      }
    },
    {
      "proxy_url": "socks5://112.161.54.7:10017",
      "subnet": 17,
      "external_ip": "39.7.54.121",
      "last_toggle": "2025-12-13 22:50:16",
      "traffic": {
        "upload": 89679249784,
        "download": 601586495927
      },
      "connected": true,
      "toggle_status": {
        "status": "recent",
        "message": "Recently toggled",
        "last_toggle": "2025-12-13 22:50:16",
        "seconds_ago": 45
      },
      "signal": {
        "rsrp": -111,
        "rsrq": -11,
        "rssi": -81,
        "sinr": 1,
        "band": "3",
        "cell_id": "7401488",
        "pci": "240",
        "plmn": "45008"
      }
    }
  ],
  "proxy_count": 8,
  "dongle_check": {
    "expected": 8,
    "physical": 14,
    "connected": 8,
    "disconnected_ports": [],
    "hub_info": {
      "main_hub": "1-3",
      "sub_hubs": ["1-3.4"],
      "ports_per_hub": 4
    }
  }
}
```

### 필드 설명

#### 최상위 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| status | string | 서버 상태 ("ready") |
| timestamp | string | API 응답 생성 시간 |
| last_heartbeat_at | string | 헬스체크 전송 시간 (ISO 8601) |
| server_ip | string | 프록시 서버 공인 IP |
| available_proxies | array | 프록시 목록 |
| proxy_count | int | 총 프록시 개수 |
| dongle_check | object | 동글 상태 체크 정보 |

#### available_proxies[] 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| proxy_url | string | SOCKS5 프록시 URL |
| subnet | int | 동글 서브넷 번호 (11-30) |
| external_ip | string | 현재 외부 IP |
| last_toggle | string | 마지막 토글 시간 |
| traffic | object | 누적 트래픽 (upload/download 바이트) |
| connected | bool | 연결 상태 |
| toggle_status | object | 토글 진행 상태 (아래 참조) |
| signal | object | LTE 신호 정보 |

#### toggle_status 필드

토글 진행 상태를 나타내는 객체입니다. `status` 값에 따라 포함되는 필드가 다릅니다.

| status 값 | 의미 | 설명 |
|-----------|------|------|
| `idle` | 대기 중 | 토글 가능 상태 |
| `in_progress` | 진행 중 | 현재 토글이 진행 중 (60초 타임아웃) |
| `recent` | 최근 완료 | 60초 이내에 토글 완료됨 |
| `timeout` | 타임아웃 | 60초 초과하여 stuck 상태 |

##### idle 상태
```json
{
  "status": "idle",
  "message": "Ready for toggle",
  "last_toggle": "2025-12-13 22:49:25"
}
```

##### in_progress 상태
```json
{
  "status": "in_progress",
  "message": "Toggle in progress",
  "started_at": "2025-12-13T22:50:00.000Z",
  "elapsed_seconds": 15
}
```

##### recent 상태
```json
{
  "status": "recent",
  "message": "Recently toggled",
  "last_toggle": "2025-12-13 22:50:16",
  "seconds_ago": 45
}
```

##### timeout 상태
```json
{
  "status": "timeout",
  "message": "Toggle timed out (exceeded 60s)",
  "started_at": "2025-12-13T22:49:00.000Z",
  "elapsed_seconds": 65
}
```

#### toggle_status 필드 상세

| 필드 | 타입 | 조건 | 설명 |
|------|------|------|------|
| status | string | 항상 | idle, in_progress, recent, timeout 중 하나 |
| message | string | 항상 | 상태 설명 메시지 |
| last_toggle | string | idle, recent | 마지막 토글 완료 시간 |
| started_at | string | in_progress, timeout | 토글 시작 시간 (ISO 8601) |
| elapsed_seconds | int | in_progress, timeout | 경과 시간 (초) |
| seconds_ago | int | recent | 마지막 토글 후 경과 시간 (초) |

#### dongle_check 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| expected | int | 예상 동글 개수 (설정값) |
| physical | int | 물리적 USB 동글 개수 (lsusb) |
| connected | int | 실제 연결된 프록시 개수 |
| disconnected_ports | array | 연결 끊긴 포트 목록 |
| hub_info | object | USB 허브 구성 정보 |

---

## 3. 연결 끊김 상태 예시

프록시가 연결 끊겼을 때의 예시:

```json
{
  "status": "ready",
  "timestamp": "2025-12-13 23:00:00",
  "server_ip": "112.161.54.7",
  "available_proxies": [
    {
      "proxy_url": "socks5://112.161.54.7:10011",
      "subnet": 11,
      "external_ip": null,
      "last_toggle": null,
      "traffic": {
        "upload": 0,
        "download": 0
      },
      "connected": false,
      "toggle_status": {
        "status": "idle",
        "message": "Ready for toggle",
        "last_toggle": null
      },
      "signal": null
    }
  ],
  "proxy_count": 8,
  "dongle_check": {
    "expected": 8,
    "physical": 7,
    "connected": 7,
    "disconnected_ports": ["10011"]
  }
}
```

---

## 4. 신호 품질 기준

### RSRP (Reference Signal Received Power)
| 범위 | 품질 |
|------|------|
| > -80 dBm | 매우 좋음 |
| -80 ~ -90 dBm | 좋음 |
| -90 ~ -100 dBm | 보통 |
| -100 ~ -110 dBm | 나쁨 |
| < -110 dBm | 매우 나쁨 |

### RSRQ (Reference Signal Received Quality)
| 범위 | 품질 |
|------|------|
| > -10 dB | 좋음 |
| -10 ~ -15 dB | 보통 |
| < -15 dB | 나쁨 |

### SINR (Signal to Interference plus Noise Ratio)
| 범위 | 품질 |
|------|------|
| > 20 dB | 매우 좋음 |
| 10 ~ 20 dB | 좋음 |
| 0 ~ 10 dB | 보통 |
| < 0 dB | 나쁨 |

---

## 5. 로그 파일 위치

| 파일 | 설명 |
|------|------|
| /home/proxy/logs/push_status.log | 헬스체크 전송 로그 |
| /home/proxy/logs/last_push_status.json | 마지막 전송 데이터 |
| /home/proxy/logs/toggle_api.log | 토글 API 로그 |

---

## 6. 테스트 명령어

```bash
# 토글 테스트 (subnet 16)
python3 /home/proxy/scripts/smart_toggle.py 16

# 현재 상태 확인
curl -s http://localhost/status | python3 -m json.tool

# 헬스체크 수동 실행
/home/proxy/scripts/push_proxy_status.sh

# 마지막 전송 데이터 확인
cat /home/proxy/logs/last_push_status.json | python3 -m json.tool
```
