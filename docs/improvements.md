# Monitor Script Improvements

## 개선된 기능들 (improved_monitor.sh)

### 1. 연속 실패 감지
- 3번 연속 실패 시에만 recovery 실행
- 일시적인 네트워크 지연 무시

### 2. 다중 연결 테스트
- curl 외부 IP 확인 (20초 타임아웃)
- 게이트웨이 ping
- DNS 조회
- 3개 중 2개 이상 성공하면 OK

### 3. Soft Recovery
인터페이스 재시작 없이:
- 라우팅 메트릭만 재조정
- DNS 캐시 플러시
- ARP 캐시 클리어

### 4. 재부팅 후 안정화
- 첫 실행 시 60초 대기

## 적용 방법
1. 현재 monitor.sh를 백업
2. improved_monitor.sh의 로직을 monitor.sh에 병합
3. config.conf에 MAX_FAILURES 옵션 추가