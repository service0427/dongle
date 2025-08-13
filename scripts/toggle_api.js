#!/usr/bin/env node
/**
 * 동글 토글 API 서버 (v1 - 락 제거 버전)
 * 단순한 웹 토글 기능만 제공
 */

const http = require('http');
const { exec, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const PORT = 8080;
const TOGGLE_TIMEOUT = 30000; // 30초
const STATE_FILE = '/home/proxy/proxy_state.json';
const MAX_CONCURRENT_TOGGLES = 3; // 최대 동시 토글 수
const activeLocks = new Set(); // 현재 실행 중인 토글 추적

// 서버 외부 IP 동적 감지 (캐시)
let serverIP = null;
function getServerIP() {
    if (!serverIP) {
        try {
            // 1차: 외부 서비스로 확인
            serverIP = execSync('curl -s -m 3 http://techb.kr/ip.php 2>/dev/null | head -1', { encoding: 'utf8' }).trim();
            if (!serverIP || !serverIP.match(/^\d+\.\d+\.\d+\.\d+$/)) {
                // 2차: 메인 인터페이스 IP
                serverIP = execSync('ip route get 8.8.8.8 2>/dev/null | awk \'{print $7; exit}\'', { encoding: 'utf8' }).trim();
            }
        } catch (e) {
            serverIP = '0.0.0.0'; // 기본값
        }
    }
    return serverIP;
}

// 상태 파일 로드
function loadState() {
    try {
        if (fs.existsSync(STATE_FILE)) {
            return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
        }
    } catch (e) {}
    return {};
}

// 상태 파일 저장
function saveState(state) {
    try {
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    } catch (e) {}
}

// 프록시 상태 가져오기
function getProxyStatus() {
    const state = loadState();
    const proxies = [];
    
    try {
        // 실제 열려있는 포트만 확인
        const openPorts = execSync(`netstat -tln 2>/dev/null | grep -E ":(100[1-3][0-9]) " | awk '{print $4}' | sed 's/.*://' | sort -u`, { encoding: 'utf8' })
            .trim()
            .split('\n')
            .filter(p => p);
        
        openPorts.forEach(port => {
            const portNum = parseInt(port);
            if (portNum >= 10011 && portNum <= 10030) {
                const subnet = portNum - 10000;
                
                let proxyInfo = {
                    proxy_url: `socks5://${getServerIP()}:${portNum}`,
                    external_ip: null,
                    last_toggle: null,
                    traffic: { upload: 0, download: 0 }
                };
                
                // 저장된 상태에서 정보 가져오기
                if (state[subnet]) {
                    proxyInfo.external_ip = state[subnet].external_ip || null;
                    proxyInfo.last_toggle = state[subnet].last_toggle || null;
                    proxyInfo.traffic = state[subnet].traffic || state[subnet].traffic_mb || { upload: 0, download: 0 };
                }
                
                // 외부 IP가 없으면 확인 (첫 로드시에만)
                if (!proxyInfo.external_ip && !state[subnet]) {
                    try {
                        const ip = execSync(
                            `timeout 2 curl --socks5 127.0.0.1:${portNum} -s http://techb.kr/ip.php 2>/dev/null | head -1`,
                            { encoding: 'utf8' }
                        ).trim();
                        
                        if (ip && ip.match(/^\d+\.\d+\.\d+\.\d+$/)) {
                            proxyInfo.external_ip = ip;
                            if (!state[subnet]) state[subnet] = {};
                            state[subnet].external_ip = ip;
                            saveState(state);
                        }
                    } catch (e) {}
                }
                
                proxies.push(proxyInfo);
            }
        });
    } catch (e) {
        console.error('Error getting proxy status:', e);
    }
    
    return proxies;
}

// 토글 실행
function executeToggle(subnet, callback) {
    const scriptPath = path.join(__dirname, 'toggle_dongle.py');
    const command = `python3 ${scriptPath} ${subnet}`;
    
    exec(command, { timeout: TOGGLE_TIMEOUT }, (error, stdout, stderr) => {
        if (error) {
            callback({ success: false, error: error.message });
        } else {
            try {
                const result = JSON.parse(stdout);
                
                // 토글 시도시 상태 업데이트 (성공/실패 모두)
                const state = loadState();
                if (!state[subnet]) state[subnet] = {};
                
                // 시스템이 이미 KST이므로 직접 포맷
                const now = new Date();
                const year = now.getFullYear();
                const month = String(now.getMonth() + 1).padStart(2, '0');
                const day = String(now.getDate()).padStart(2, '0');
                const hours = String(now.getHours()).padStart(2, '0');
                const minutes = String(now.getMinutes()).padStart(2, '0');
                const seconds = String(now.getSeconds()).padStart(2, '0');
                state[subnet].last_toggle = `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
                
                if (result.success) {
                    // 성공시 IP와 트래픽 업데이트
                    state[subnet].external_ip = result.ip;
                    
                    if (result.traffic) {
                        state[subnet].traffic = result.traffic;
                    } else if (!state[subnet].traffic) {
                        state[subnet].traffic = { upload: 0, download: 0 };
                    }
                } else {
                    // 실패시 IP를 null로 설정
                    state[subnet].external_ip = null;
                }
                
                saveState(state);
                
                callback(result);
            } catch (e) {
                callback({ success: false, error: 'Invalid response' });
            }
        }
    });
}

// HTTP 서버
const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://localhost:${PORT}`);
    const pathname = url.pathname;
    
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Access-Control-Allow-Origin', '*');
    
    // 헬스체크
    if (pathname === '/health') {
        res.writeHead(200);
        res.end(JSON.stringify({ status: 'ok' }));
        return;
    }
    
    // 프록시 상태
    if (pathname === '/status') {
        const proxies = getProxyStatus();
        // 시스템이 이미 KST이므로 직접 포맷
        const now = new Date();
        const year = now.getFullYear();
        const month = String(now.getMonth() + 1).padStart(2, '0');
        const day = String(now.getDate()).padStart(2, '0');
        const hours = String(now.getHours()).padStart(2, '0');
        const minutes = String(now.getMinutes()).padStart(2, '0');
        const seconds = String(now.getSeconds()).padStart(2, '0');
        const timestamp = `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
        
        res.writeHead(200);
        res.end(JSON.stringify({
            status: 'ready',
            api_version: 'v1-enhanced',
            timestamp: timestamp,
            available_proxies: proxies
        }));
        return;
    }
    
    // 토글 처리
    const toggleMatch = pathname.match(/^\/toggle\/(\d+)$/);
    if (toggleMatch) {
        const subnet = parseInt(toggleMatch[1]);
        
        if (subnet < 11 || subnet > 30) {
            res.writeHead(400);
            res.end(JSON.stringify({ error: 'Invalid subnet (11-30)' }));
            return;
        }
        
        // 포트별 중복 체크
        if (activeLocks.has(subnet)) {
            res.writeHead(409); // Conflict
            res.end(JSON.stringify({ 
                error: `Toggle already in progress for subnet ${subnet}`,
                code: 'TOGGLE_IN_PROGRESS'
            }));
            return;
        }
        
        // 동시 토글 수 제한 체크
        if (activeLocks.size >= MAX_CONCURRENT_TOGGLES) {
            res.writeHead(429); // Too Many Requests
            res.end(JSON.stringify({ 
                error: `Too many concurrent toggles (max: ${MAX_CONCURRENT_TOGGLES}, current: ${activeLocks.size})`,
                code: 'TOO_MANY_TOGGLES',
                current_toggles: Array.from(activeLocks),
                max_concurrent: MAX_CONCURRENT_TOGGLES
            }));
            return;
        }
        
        // 락 설정
        activeLocks.add(subnet);
        console.log(`[${new Date().toISOString()}] Toggle request for subnet ${subnet} (${activeLocks.size}/${MAX_CONCURRENT_TOGGLES} active)`);
        
        executeToggle(subnet, (result) => {
            // 락 해제
            activeLocks.delete(subnet);
            console.log(`[${new Date().toISOString()}] Toggle ${result.success ? 'SUCCESS' : 'FAILED'} for subnet ${subnet} (${activeLocks.size}/${MAX_CONCURRENT_TOGGLES} active)`);
            res.writeHead(result.success ? 200 : 500);
            res.end(JSON.stringify(result));
        });
        return;
    }
    
    // 404
    res.writeHead(404);
    res.end(JSON.stringify({ error: 'Not found' }));
});

// 서버 시작
server.listen(PORT, () => {
    console.log(`Toggle API server (no-lock version) running on port ${PORT}`);
});

// 종료 처리
process.on('SIGTERM', () => {
    server.close(() => {
        process.exit(0);
    });
});