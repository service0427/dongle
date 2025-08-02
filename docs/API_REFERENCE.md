# API Reference

Health Check API는 포트 8080에서 실행됩니다.

## Endpoints

### GET /status
시스템 전체 상태 확인

**Response:**
```json
{
  "timestamp": "2025-08-02T03:30:00.000Z",
  "dongles": {
    "11": {
      "interface": "enp0s21f0u3u4u4",
      "ip": "192.168.11.100",
      "connected": true
    }
  },
  "mainInterface": {
    "name": "eno1",
    "ip": "112.161.54.7",
    "metric": 0
  },
  "connectivity": {
    "internet": true,
    "latency": 15.2
  }
}
```

### GET /connectivity
각 동글의 인터넷 연결 상태

**Response:**
```json
{
  "timestamp": "2025-08-02T03:30:00.000Z",
  "dongles": {
    "11": {
      "connected": true,
      "internet": true,
      "latency": 20.5,
      "externalIP": "175.223.26.77"
    }
  }
}
```

### GET /toggle/:subnet
동글 IP 변경 (재연결)

**Parameters:**
- `subnet`: 동글 번호 (11-30)

**Response:**
```json
{
  "success": true,
  "subnet": 11,
  "message": "Toggle completed successfully",
  "oldIP": "175.223.26.77",
  "newIP": "175.223.15.123"
}
```

### GET /toggle-status/:subnet
토글 작업 상태 확인

**Response:**
```json
{
  "status": "in_progress",
  "subnet": 11,
  "startTime": "2025-08-02T03:30:00.000Z",
  "progress": "Disconnecting..."
}
```

### GET /proxy-info
프록시 서버 정보

**Response:**
```json
{
  "timestamp": "2025-08-02T03:30:00.000Z",
  "proxies": [
    {
      "subnet": 11,
      "socks5_port": 10011,
      "host": "112.161.54.7",
      "type": "socks5",
      "ip": "192.168.11.100"
    }
  ]
}
```

### GET /data-usage
일일 데이터 사용량

**Response:**
```json
{
  "date": "2025-08-02",
  "dongles": {
    "11": {
      "daily_usage_gb": 0.5,
      "speed_limited": false,
      "warning": false,
      "critical": false
    }
  }
}
```

### GET /usage-warnings
데이터 사용량 경고

**Response:**
```json
{
  "warnings": [
    {
      "subnet": 11,
      "type": "warning",
      "message": "동글 11: 1.5GB 초과 (1.8GB) - 주의",
      "usage": 1.8
    }
  ],
  "timestamp": "2025-08-02T03:30:00.000Z"
}
```