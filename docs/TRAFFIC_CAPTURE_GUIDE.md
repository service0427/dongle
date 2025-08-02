# 프록시 트래픽 캡처 가이드

## 개요
동글 11을 통해 나가는 HTTP/HTTPS 트래픽을 실시간으로 모니터링할 수 있습니다.

## 사용 가능한 도구

### 1. 간단한 모니터링 (추천)
```bash
sudo /home/proxy/network-monitor/scripts/simple_http_monitor.sh
```
- DNS 쿼리와 HTTP 요청을 실시간 표시
- 가장 빠르고 간단함

### 2. 상세 트래픽 검사
```bash
sudo python3 /home/proxy/network-monitor/scripts/traffic_inspector.py
```
- HTTP 헤더 상세 정보
- User-Agent, Cookie, Referer 표시
- HTTPS 도메인 감지 (SNI)

### 3. HTTP 캡처 및 저장
```bash
sudo python3 /home/proxy/network-monitor/scripts/http_capture.py
```
- 트래픽을 JSON 파일로 저장
- 나중에 분석 가능

## 볼 수 있는 정보

### HTTP (포트 80)
- ✅ 전체 URL
- ✅ 모든 헤더 (User-Agent, Cookie, Referer 등)
- ✅ 요청 본문 (POST 데이터)

### HTTPS (포트 443)
- ✅ 도메인명 (SNI를 통해)
- ❌ URL 경로 (암호화됨)
- ❌ 헤더 (암호화됨)
- ❌ 요청/응답 내용 (암호화됨)

## 실시간 모니터링 예시

```
[10:45:23] DNS: www.coupang.com
[10:45:23] HTTPS 연결: www.coupang.com
[10:45:24] DNS: img.coupangcdn.com
[10:45:24] HTTP GET /image.jpg → img.coupangcdn.com
[10:45:25] DNS: api.coupang.com
[10:45:25] HTTPS 연결: api.coupang.com
```

## tcpdump 직접 사용

### 모든 HTTP 헤더 보기
```bash
sudo tcpdump -i enp0s21f0u3u4u4 -A -s 0 'tcp port 80'
```

### DNS 쿼리만 보기
```bash
sudo tcpdump -i enp0s21f0u3u4u4 -nn 'udp port 53'
```

### 특정 도메인 필터링
```bash
sudo tcpdump -i enp0s21f0u3u4u4 -nn 'host www.coupang.com'
```

## 주의사항

1. **root 권한 필요**: tcpdump는 sudo로 실행해야 함
2. **HTTPS 한계**: HTTPS는 암호화되어 내용을 볼 수 없음
3. **성능 영향**: 대량 트래픽 시 시스템에 부하 가능
4. **프라이버시**: 민감한 정보가 포함될 수 있으므로 주의

## 고급 분석

HTTPS 내용까지 보려면 MITM 프록시 설정이 필요합니다:
- mitmproxy 설치 및 인증서 설정
- 브라우저에 CA 인증서 설치
- 투명 프록시로 설정

하지만 이는 복잡하고 일부 사이트에서 감지될 수 있습니다.