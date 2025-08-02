# SOCKS5 Proxy Usage Guide

## Overview
Each connected dongle provides a SOCKS5 proxy that makes your traffic appear as genuine mobile network traffic without any proxy detection.

## Proxy Information

### API Endpoint
```bash
GET http://112.161.54.7:8080/proxy-info
```

Response example:
```json
{
  "timestamp": "2025-08-02T01:18:22.492Z",
  "proxies": [
    {
      "subnet": 11,
      "socks5_port": 10011,
      "host": "112.161.54.7",
      "type": "socks5",
      "ip": "192.168.11.100"
    },
    {
      "subnet": 16,
      "socks5_port": 10016,
      "host": "112.161.54.7",
      "type": "socks5",
      "ip": "192.168.16.100"
    }
  ]
}
```

## Connection Details

- **Type**: SOCKS5 (no authentication)
- **Host**: 112.161.54.7
- **Ports**: 10011-10030 (10000 + dongle subnet number)
- **No proxy headers**: Via, X-Forwarded-For, X-Real-IP are not sent

## Usage Examples

### 1. Command Line (curl)
```bash
# Using dongle 11
curl --socks5 112.161.54.7:10011 https://ipinfo.io/ip

# Using dongle 16
curl --socks5 112.161.54.7:10016 https://example.com
```

### 2. Python (requests)
```python
import requests

proxies = {
    'http': 'socks5://112.161.54.7:10011',
    'https': 'socks5://112.161.54.7:10011'
}

response = requests.get('https://ipinfo.io/ip', proxies=proxies)
print(response.text)
```

### 3. Playwright
```javascript
const { chromium } = require('playwright');

const browser = await chromium.launch({
    proxy: {
        server: 'socks5://112.161.54.7:10011'
    }
});

const context = await browser.newContext({
    // Mobile user agent
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15',
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true
});
```

### 4. Selenium
```python
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

chrome_options = Options()
chrome_options.add_argument('--proxy-server=socks5://112.161.54.7:10011')

driver = webdriver.Chrome(options=chrome_options)
driver.get('https://ipinfo.io/ip')
```

## Anti-Detection Features

1. **No Proxy Headers**: All proxy-related headers are stripped
2. **Direct Mobile IP**: Traffic appears to come directly from KT mobile network
3. **TCP Fingerprinting**: Modified to match mobile devices
4. **TTL Adjustment**: Set to 64 (typical for mobile devices)
5. **DNS**: Uses mobile carrier DNS servers

## IP Rotation

To change the IP address of a dongle:

```bash
# Toggle dongle 11 IP
curl http://112.161.54.7:8080/toggle/11

# Check toggle status
curl http://112.161.54.7:8080/toggle-status/11
```

Note: There's a 15-second cooldown between toggles for the same dongle.

## Monitoring

Check connectivity status:
```bash
curl http://112.161.54.7:8080/connectivity
```

## Important Notes

1. Each dongle operates independently with its own IP
2. Multiple dongles can be used simultaneously
3. The proxy is transparent - websites see the mobile IP directly
4. No authentication required for internal network use
5. Firewall ports 10011-10030 are open for external access