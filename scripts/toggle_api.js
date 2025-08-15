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
            serverIP = execSync('curl -s -m 3 https://mkt.techb.kr/ip 2>/dev/null | head -1', { encoding: 'utf8' }).trim();
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
        // 실제 연결된 인터페이스 기반으로 확인
        const subnets = execSync(`ip addr show | grep -oE "192.168.([1-3][0-9]).100" | cut -d. -f3 | sort -u`, { encoding: 'utf8' })
            .trim()
            .split('\n')
            .filter(s => s);
        
        subnets.forEach(subnetStr => {
            const subnet = parseInt(subnetStr);
            if (subnet >= 11 && subnet <= 30) {
                const portNum = 10000 + subnet;
                
                let proxyInfo = {
                    proxy_url: `socks5://${getServerIP()}:${portNum}`,
                    external_ip: null,
                    last_toggle: null,
                    traffic: { upload: 0, download: 0 },
                    connected: false  // 기본값 false
                };
                
                // 저장된 상태에서 정보 가져오기
                if (state[subnet]) {
                    proxyInfo.external_ip = state[subnet].external_ip || null;
                    proxyInfo.last_toggle = state[subnet].last_toggle || null;
                    proxyInfo.traffic = state[subnet].traffic || state[subnet].traffic_mb || { upload: 0, download: 0 };
                }
                
                // 외부 IP가 없거나 null이면 확인
                if (!proxyInfo.external_ip) {
                    try {
                        const ip = execSync(
                            `timeout 2 curl --socks5 127.0.0.1:${portNum} -s https://mkt.techb.kr/ip 2>/dev/null | head -1`,
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
                
                // connected 상태 설정 (external_ip가 있으면 true)
                proxyInfo.connected = proxyInfo.external_ip ? true : false;
                
                proxies.push(proxyInfo);
            }
        });
    } catch (e) {
        console.error('Error getting proxy status:', e);
    }
    
    return proxies;
}

// 스마트 토글 실행
function executeToggle(subnet, callback) {
    const scriptPath = path.join(__dirname, 'smart_toggle.py');
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
    
    // 동글 정보 API
    if (pathname === '/dongle-info') {
        exec('python3 ' + path.join(__dirname, 'dongle_info.py') + ' info', { timeout: 60000 }, (error, stdout, stderr) => {
            if (error) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Failed to get dongle info', details: error.message }));
                return;
            }
            
            try {
                const data = JSON.parse(stdout);
                res.writeHead(200);
                res.end(JSON.stringify(data));
            } catch (e) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Invalid response from dongle_info.py' }));
            }
        });
        return;
    }
    
    // 특정 동글 정보
    if (pathname.startsWith('/dongle-info/')) {
        const subnetStr = pathname.split('/')[2];
        const subnets = subnetStr.split(',').map(s => s.trim()).filter(s => /^\d+$/.test(s));
        
        if (subnets.length === 0) {
            res.writeHead(400);
            res.end(JSON.stringify({ error: 'Invalid subnet format' }));
            return;
        }
        
        exec('python3 ' + path.join(__dirname, 'dongle_info.py') + ' info ' + subnets.join(','), { timeout: 60000 }, (error, stdout, stderr) => {
            if (error) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Failed to get dongle info', details: error.message }));
                return;
            }
            
            try {
                const data = JSON.parse(stdout);
                res.writeHead(200);
                res.end(JSON.stringify(data));
            } catch (e) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Invalid response from dongle_info.py' }));
            }
        });
        return;
    }
    
    // 트래픽 리셋
    if (pathname === '/reset-traffic') {
        exec('python3 ' + path.join(__dirname, 'dongle_info.py') + ' reset', { timeout: 120000 }, (error, stdout, stderr) => {
            if (error) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Failed to reset traffic', details: error.message }));
                return;
            }
            
            try {
                const data = JSON.parse(stdout);
                res.writeHead(200);
                res.end(JSON.stringify(data));
            } catch (e) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Invalid response from dongle_info.py' }));
            }
        });
        return;
    }
    
    // 특정 동글 트래픽 리셋
    if (pathname.startsWith('/reset-traffic/')) {
        const subnetStr = pathname.split('/')[2];
        const subnets = subnetStr.split(',').map(s => s.trim()).filter(s => /^\d+$/.test(s));
        
        if (subnets.length === 0) {
            res.writeHead(400);
            res.end(JSON.stringify({ error: 'Invalid subnet format' }));
            return;
        }
        
        exec('python3 ' + path.join(__dirname, 'dongle_info.py') + ' reset ' + subnets.join(','), { timeout: 120000 }, (error, stdout, stderr) => {
            if (error) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Failed to reset traffic', details: error.message }));
                return;
            }
            
            try {
                const data = JSON.parse(stdout);
                res.writeHead(200);
                res.end(JSON.stringify(data));
            } catch (e) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Invalid response from dongle_info.py' }));
            }
        });
        return;
    }
    
    // APN 정보만
    if (pathname === '/apn-info') {
        exec('python3 ' + path.join(__dirname, 'dongle_info.py') + ' info', { timeout: 60000 }, (error, stdout, stderr) => {
            if (error) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Failed to get APN info', details: error.message }));
                return;
            }
            
            try {
                const data = JSON.parse(stdout);
                // APN 정보만 추출
                const apnInfo = {
                    timestamp: data.timestamp,
                    dongles: {},
                    summary: {
                        total_requested: data.summary.total_requested,
                        connected: data.summary.connected
                    }
                };
                
                Object.keys(data.dongles).forEach(subnet => {
                    const dongle = data.dongles[subnet];
                    if (dongle.status === 'connected' && dongle.apn) {
                        apnInfo.dongles[subnet] = {
                            subnet: dongle.subnet,
                            ip: dongle.ip,
                            status: dongle.status,
                            apn: dongle.apn,
                            network: dongle.network
                        };
                    }
                });
                
                res.writeHead(200);
                res.end(JSON.stringify(apnInfo));
            } catch (e) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Invalid response from dongle_info.py' }));
            }
        });
        return;
    }
    
    // 트래픽 정보만
    if (pathname === '/traffic-stats') {
        exec('python3 ' + path.join(__dirname, 'dongle_info.py') + ' info', { timeout: 60000 }, (error, stdout, stderr) => {
            if (error) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Failed to get traffic stats', details: error.message }));
                return;
            }
            
            try {
                const data = JSON.parse(stdout);
                // 트래픽 정보만 추출
                const trafficInfo = {
                    timestamp: data.timestamp,
                    dongles: {},
                    summary: {
                        total_requested: data.summary.total_requested,
                        connected: data.summary.connected,
                        total_traffic_gb: data.summary.total_traffic_gb
                    }
                };
                
                Object.keys(data.dongles).forEach(subnet => {
                    const dongle = data.dongles[subnet];
                    if (dongle.status === 'connected' && dongle.traffic) {
                        trafficInfo.dongles[subnet] = {
                            subnet: dongle.subnet,
                            ip: dongle.ip,
                            status: dongle.status,
                            traffic: dongle.traffic
                        };
                    }
                });
                
                res.writeHead(200);
                res.end(JSON.stringify(trafficInfo));
            } catch (e) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: 'Invalid response from dongle_info.py' }));
            }
        });
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