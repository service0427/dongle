#!/usr/bin/env node
/**
 * 동글 토글 API 서버 (v1 - 락 제거 버전)
 * 단순한 웹 토글 기능만 제공
 */

const http = require('http');
const { exec, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const PORT = 80;
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

// 동글 설정 파일 읽기
function loadDongleConfig() {
    const configFile = '/home/proxy/config/dongle_config.json';
    try {
        if (fs.existsSync(configFile)) {
            const data = fs.readFileSync(configFile, 'utf8');
            return JSON.parse(data);
        }
    } catch (e) {
        console.error('Error loading dongle config:', e);
    }
    return null;
}

// 동글 상태 분석
function analyzeDongleStatus() {
    const config = loadDongleConfig();
    if (!config) {
        return null;
    }
    
    try {
        // 현재 활성 인터페이스 확인
        const activeInterfaces = execSync(`ip addr show | grep -oE "192.168.([1-3][0-9]).100" | cut -d. -f3`, { encoding: 'utf8' })
            .trim()
            .split('\n')
            .filter(s => s)
            .map(s => parseInt(s));
        
        // config에 정의된 동글 중 활성화된 개수
        const configuredDongles = Object.keys(config.interface_mapping || {}).map(s => parseInt(s));
        const activeCount = configuredDongles.filter(subnet => activeInterfaces.includes(subnet)).length;
        
        return {
            expected: config.expected_count || 0,
            configured: configuredDongles.length,
            active: activeCount,
            inactive: configuredDongles.length - activeCount,
            all_connected: activeCount === configuredDongles.length
        };
    } catch (e) {
        console.error('Error analyzing dongle status:', e);
        return null;
    }
}

// 프록시 상태 가져오기
function getProxyStatus() {
    const state = loadState();
    const config = loadDongleConfig();
    const proxies = [];
    const dongleStatus = analyzeDongleStatus();
    
    // config 파일이 없으면 에러
    if (!config || !config.interface_mapping) {
        return { 
            proxies: [], 
            dongleStatus: null,
            error: 'Configuration file not found or invalid. Run /home/proxy/init_dongle_config.sh first.'
        };
    }
    
    try {
        // 현재 활성 인터페이스 확인
        const activeSubnets = execSync(`ip addr show | grep -oE "192.168.([1-3][0-9]).100" | cut -d. -f3`, { encoding: 'utf8' })
            .trim()
            .split('\n')
            .filter(s => s)
            .map(s => parseInt(s));
        
        // config 파일의 interface_mapping을 기준으로 프록시 목록 생성
        Object.keys(config.interface_mapping).forEach(subnetStr => {
            const subnet = parseInt(subnetStr);
            const mapping = config.interface_mapping[subnetStr];
            
            let proxyInfo = {
                proxy_url: `socks5://${getServerIP()}:${mapping.socks5_port}`,
                external_ip: null,
                last_toggle: null,
                traffic: { upload: 0, download: 0 },
                connected: activeSubnets.includes(subnet)  // 실제 인터페이스 존재 여부
            };
            
            // 저장된 상태에서 정보 가져오기
            if (state[subnet]) {
                proxyInfo.external_ip = state[subnet].external_ip || null;
                proxyInfo.last_toggle = state[subnet].last_toggle || null;
                proxyInfo.traffic = state[subnet].traffic || state[subnet].traffic_mb || { upload: 0, download: 0 };
            }
            
            proxies.push(proxyInfo);
        });
        
        // 서브넷 번호 순으로 정렬
        proxies.sort((a, b) => {
            const portA = parseInt(a.proxy_url.split(':').pop());
            const portB = parseInt(b.proxy_url.split(':').pop());
            return portA - portB;
        });
        
    } catch (e) {
        console.error('Error getting proxy status:', e);
    }
    
    return { proxies, dongleStatus };
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
        const result = getProxyStatus();
        
        // config 파일 에러 체크
        if (result.error) {
            res.writeHead(500);
            res.end(JSON.stringify({ 
                status: 'error', 
                error: result.error 
            }));
            return;
        }
        
        // 시스템이 이미 KST이므로 직접 포맷
        const now = new Date();
        const year = now.getFullYear();
        const month = String(now.getMonth() + 1).padStart(2, '0');
        const day = String(now.getDate()).padStart(2, '0');
        const hours = String(now.getHours()).padStart(2, '0');
        const minutes = String(now.getMinutes()).padStart(2, '0');
        const seconds = String(now.getSeconds()).padStart(2, '0');
        const timestamp = `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
        
        const response = {
            status: 'ready',
            api_version: 'v1-config-based',
            timestamp: timestamp,
            available_proxies: result.proxies
        };
        
        // 동글 설정이 있으면 상태 정보 추가
        if (result.dongleStatus) {
            response.dongle_status = result.dongleStatus;
        }
        
        res.writeHead(200);
        res.end(JSON.stringify(response));
        return;
    }
    // SOCKS5 복구 API (외부에서 문제 감지 시 사용)
    if (pathname.startsWith('/recover-socks5/')) {
        const subnet = pathname.split('/')[2];
        
        // 서브넷 유효성 검사
        if (!subnet || isNaN(subnet) || subnet < 11 || subnet > 30) {
            res.writeHead(400);
            res.end(JSON.stringify({ 
                error: 'Invalid subnet',
                message: 'Subnet must be between 11 and 30'
            }));
            return;
        }
        
        console.log(`[${new Date().toISOString()}] SOCKS5 recovery requested for subnet ${subnet}`);
        
        // SOCKS5 서비스 상태 확인
        exec(`systemctl is-active dongle-socks5-${subnet}`, { timeout: 5000 }, (error, stdout, stderr) => {
            const isActive = stdout.trim() === 'active';
            
            // 서비스 재시작
            exec(`sudo systemctl restart dongle-socks5-${subnet}`, { timeout: 10000 }, (restartError) => {
                if (restartError) {
                    res.writeHead(500);
                    res.end(JSON.stringify({ 
                        error: 'Failed to restart SOCKS5 service',
                        subnet: subnet,
                        was_active: isActive,
                        details: restartError.message
                    }));
                    return;
                }
                
                // 재시작 후 잠시 대기
                setTimeout(() => {
                    // 서비스 상태 재확인
                    exec(`systemctl is-active dongle-socks5-${subnet}`, { timeout: 5000 }, (checkError, checkStdout) => {
                        const newStatus = checkStdout.trim();
                        const recovered = newStatus === 'active';
                        
                        // 포트 확인
                        const port = 10000 + parseInt(subnet);
                        exec(`ss -tuln | grep :${port}`, { timeout: 5000 }, (portError, portStdout) => {
                            const portOpen = !!portStdout.trim();
                            
                            const response = {
                                success: recovered && portOpen,
                                subnet: subnet,
                                port: port,
                                service_status: {
                                    before: isActive ? 'active' : 'inactive',
                                    after: newStatus
                                },
                                port_listening: portOpen,
                                timestamp: new Date().toISOString()
                            };
                            
                            res.writeHead(recovered && portOpen ? 200 : 500);
                            res.end(JSON.stringify(response));
                        });
                    });
                }, 3000); // 3초 대기
            });
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