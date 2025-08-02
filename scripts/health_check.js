#!/usr/bin/env node

const http = require('http');
const fs = require('fs');
const { exec } = require('child_process');
const path = require('path');
const { checkAllDongles, cleanStaleRoutes } = require('./check_dongle_connectivity');

// 설정
const PORT = process.env.HEALTH_CHECK_PORT || 8080;
const STATE_FILE = '/home/proxy/network-monitor/logs/state.json';
const LOG_FILE = '/home/proxy/network-monitor/logs/monitor.log';
const SCRIPTS_DIR = '/home/proxy/network-monitor/scripts';

// 로깅 함수
function log(message) {
    const timestamp = new Date().toISOString();
    const logMessage = `[${timestamp}] HEALTH_CHECK: ${message}\n`;
    fs.appendFileSync(LOG_FILE, logMessage);
    console.log(logMessage.trim());
}

// 상태 파일 읽기
function readState() {
    try {
        if (fs.existsSync(STATE_FILE)) {
            return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
        }
    } catch (error) {
        log(`Error reading state file: ${error.message}`);
    }
    return null;
}

// 인터페이스 정보 가져오기
async function getInterfaceInfo() {
    return new Promise((resolve) => {
        exec(`${SCRIPTS_DIR}/detect_interfaces.sh`, (error, stdout, stderr) => {
            if (error) {
                log(`Error detecting interfaces: ${error.message}`);
                resolve({ main: null, dongles: [] });
                return;
            }

            const lines = stdout.split('\n');
            let mainInterface = null;
            let dongleInterfaces = [];

            lines.forEach(line => {
                if (line.includes('export MAIN_INTERFACE=')) {
                    mainInterface = line.split('=')[1].trim();
                } else if (line.includes('export DONGLE_INTERFACES=')) {
                    const dongles = line.split('=')[1].replace(/"/g, '').trim();
                    if (dongles) {
                        dongleInterfaces = dongles.split(' ');
                    }
                }
            });

            resolve({
                main: mainInterface,
                dongles: dongleInterfaces
            });
        });
    });
}

// 네트워크 인터페이스 상세 정보
async function getInterfaceDetails(iface) {
    return new Promise((resolve) => {
        exec(`ip addr show ${iface} 2>/dev/null`, (error, stdout) => {
            if (error) {
                resolve({ name: iface, status: 'error', ip: null });
                return;
            }

            const ipMatch = stdout.match(/inet\s+(\d+\.\d+\.\d+\.\d+)/);
            const stateMatch = stdout.match(/state\s+(\w+)/);
            
            resolve({
                name: iface,
                status: stateMatch ? stateMatch[1].toLowerCase() : 'unknown',
                ip: ipMatch ? ipMatch[1] : null
            });
        });
    });
}

// 시스템 상태 가져오기 (간소화)
async function getSystemStatus() {
    const state = readState();
    const interfaces = await getInterfaceInfo();
    
    const status = {
        timestamp: new Date().toISOString(),
        monitor: {
            running: state ? true : false,
            lastCheck: state ? state.timestamp : null,
            status: state ? state.status : 'unknown'
        },
        interfaces: {
            main: null,
            dongles: []
        }
    };

    // 메인 인터페이스 정보
    if (interfaces.main) {
        status.interfaces.main = await getInterfaceDetails(interfaces.main);
    }

    // 동글 인터페이스 정보
    for (const dongle of interfaces.dongles) {
        status.interfaces.dongles.push(await getInterfaceDetails(dongle));
    }

    return status;
}

// 모니터 서비스 상태 확인
async function getMonitorServiceStatus() {
    return new Promise((resolve) => {
        exec('systemctl is-active network-monitor.service', (error, stdout) => {
            resolve({
                service: 'network-monitor',
                status: stdout.trim() || 'inactive'
            });
        });
    });
}

// HTTP 서버
const server = http.createServer(async (req, res) => {
    // CORS 헤더
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET');
    res.setHeader('Content-Type', 'application/json');

    try {
        if (req.url === '/health' || req.url === '/') {
            // 기본 헬스체크 - 간단한 정보만
            const interfaces = await getInterfaceInfo();
            const connectivity = await checkAllDongles();
            
            const simpleStatus = {
                timestamp: new Date().toISOString(),
                main_interface: interfaces.main,
                total_dongles: connectivity.length,
                connected_dongles: connectivity.filter(d => d.status === 'connected').length,
                dongles: connectivity.map(d => ({
                    subnet: d.subnet,
                    status: d.status
                }))
            };
            
            res.writeHead(200);
            res.end(JSON.stringify(simpleStatus, null, 2));
            
        } else if (req.url === '/status') {
            // 상세 상태
            const status = await getSystemStatus();
            const service = await getMonitorServiceStatus();
            
            const fullStatus = {
                ...status,
                service
            };
            
            res.writeHead(200);
            res.end(JSON.stringify(fullStatus, null, 2));
            
        } else if (req.url === '/interfaces') {
            // 인터페이스 정보만
            const interfaces = await getInterfaceInfo();
            const details = {
                main: interfaces.main ? await getInterfaceDetails(interfaces.main) : null,
                dongles: []
            };
            
            for (const dongle of interfaces.dongles) {
                details.dongles.push(await getInterfaceDetails(dongle));
            }
            
            res.writeHead(200);
            res.end(JSON.stringify(details, null, 2));
            
        } else if (req.url === '/logs') {
            // 최근 로그
            const logs = await getRecentLogs(50);
            res.writeHead(200);
            res.end(JSON.stringify({ logs }, null, 2));
            
        } else if (req.url === '/connectivity') {
            // 동글 연결성 상태 (간소화)
            const connectivity = await checkAllDongles();
            const summary = {
                timestamp: new Date().toISOString(),
                total: connectivity.length,
                connected: connectivity.filter(d => d.status === 'connected').length,
                no_internet: connectivity.filter(d => d.status === 'no_internet').length,
                stale_routes: connectivity.filter(d => d.status === 'stale_route').length,
                dongles: connectivity.map(d => ({
                    subnet: d.subnet,
                    status: d.status,
                    ip: d.ip
                }))
            };
            res.writeHead(200);
            res.end(JSON.stringify(summary, null, 2));
            
        } else if (req.url === '/clean-stale-routes') {
            // Stale routes 정리
            const cleaned = await cleanStaleRoutes();
            res.writeHead(200);
            res.end(JSON.stringify({ 
                cleaned: cleaned,
                message: `Cleaned ${cleaned} stale routes`
            }, null, 2));
            
        } else if (req.url === '/apn') {
            // 모든 동글 APN 확인
            exec('python3 /home/proxy/network-monitor/scripts/check_dongle_apn.py',
                { timeout: 30000 },
                (error, stdout, stderr) => {
                    if (error) {
                        res.writeHead(500);
                        res.end(JSON.stringify({ 
                            error: 'APN check failed', 
                            details: stderr || error.message 
                        }));
                        return;
                    }
                    
                    try {
                        const result = JSON.parse(stdout);
                        res.writeHead(200);
                        res.end(JSON.stringify(result, null, 2));
                    } catch (parseError) {
                        res.writeHead(500);
                        res.end(JSON.stringify({ 
                            error: 'Invalid response',
                            output: stdout
                        }));
                    }
                }
            );
            return;
            
        } else if (req.url.startsWith('/apn/')) {
            // 특정 동글 APN 확인
            const subnet = req.url.split('/')[2];
            if (!subnet || isNaN(subnet) || subnet < 11 || subnet > 30) {
                res.writeHead(400);
                res.end(JSON.stringify({ error: 'Invalid subnet' }));
                return;
            }
            
            exec(`python3 /home/proxy/network-monitor/scripts/check_dongle_apn.py ${subnet}`,
                { timeout: 10000 },
                (error, stdout, stderr) => {
                    if (error) {
                        res.writeHead(500);
                        res.end(JSON.stringify({ 
                            error: 'APN check failed', 
                            details: stderr || error.message 
                        }));
                        return;
                    }
                    
                    try {
                        const result = JSON.parse(stdout);
                        res.writeHead(200);
                        res.end(JSON.stringify(result, null, 2));
                    } catch (parseError) {
                        res.writeHead(500);
                        res.end(JSON.stringify({ 
                            error: 'Invalid response',
                            output: stdout
                        }));
                    }
                }
            );
            return;
            
        } else if (req.url.startsWith('/fix-apn/')) {
            // 동글 APN 수정
            const subnet = req.url.split('/')[2];
            if (!subnet || isNaN(subnet) || subnet < 11 || subnet > 30) {
                res.writeHead(400);
                res.end(JSON.stringify({ error: 'Invalid subnet' }));
                return;
            }
            
            log(`Fixing APN for dongle${subnet}`);
            
            exec(`python3 /home/proxy/network-monitor/scripts/fix_dongle_apn.py ${subnet}`,
                { timeout: 30000 },
                (error, stdout, stderr) => {
                    if (error) {
                        log(`APN fix error for dongle${subnet}: ${error.message}`);
                        res.writeHead(500);
                        res.end(JSON.stringify({ 
                            error: 'APN fix failed', 
                            details: stderr || error.message 
                        }));
                        return;
                    }
                    
                    try {
                        const result = JSON.parse(stdout);
                        res.writeHead(200);
                        res.end(JSON.stringify(result, null, 2));
                    } catch (parseError) {
                        res.writeHead(500);
                        res.end(JSON.stringify({ 
                            error: 'Invalid response',
                            output: stdout
                        }));
                    }
                }
            );
            return;
            
        } else if (req.url === '/proxy-info') {
            // 프록시 설정 정보
            const connectivity = await checkAllDongles();
            const proxyInfo = {
                timestamp: new Date().toISOString(),
                proxies: []
            };
            
            for (const dongle of connectivity) {
                if (dongle.status === 'connected') {
                    proxyInfo.proxies.push({
                        subnet: dongle.subnet,
                        socks5_port: 10000 + dongle.subnet,
                        host: '112.161.54.7',
                        type: 'socks5',
                        ip: dongle.ip
                    });
                }
            }
            
            res.writeHead(200);
            res.end(JSON.stringify(proxyInfo, null, 2));
            return;
            
        } else if (req.url.startsWith('/toggle-status/')) {
            // 토글 진행 상태 확인
            const subnet = req.url.split('/')[2];
            if (!subnet || isNaN(subnet) || subnet < 11 || subnet > 30) {
                res.writeHead(400);
                res.end(JSON.stringify({ error: 'Invalid subnet' }));
                return;
            }
            
            const lockFile = `/tmp/dongle_toggle_${subnet}.lock`;
            fs.access(lockFile, fs.constants.F_OK, (err) => {
                if (err) {
                    // 락 파일이 없음 = 토글 진행 중이 아님
                    res.writeHead(200);
                    res.end(JSON.stringify({ 
                        subnet: parseInt(subnet),
                        in_progress: false 
                    }));
                } else {
                    // 락 파일이 있음 = 토글 진행 중
                    fs.readFile(lockFile, 'utf8', (readErr, data) => {
                        res.writeHead(200);
                        res.end(JSON.stringify({ 
                            subnet: parseInt(subnet),
                            in_progress: true,
                            pid: readErr ? null : data.trim()
                        }));
                    });
                }
            });
            return;
            
        } else if (req.url.startsWith('/toggle/')) {
            // 동글 IP 토글
            const subnet = req.url.split('/')[2];
            if (!subnet || isNaN(subnet) || subnet < 11 || subnet > 30) {
                res.writeHead(400);
                res.end(JSON.stringify({ error: 'Invalid subnet' }));
                return;
            }
            
            log(`Toggling IP for dongle${subnet}`);
            
            exec(`python3 /home/proxy/network-monitor/scripts/toggle_dongle.py ${subnet}`, 
                { timeout: 60000 }, // 60초 타임아웃
                (error, stdout, stderr) => {
                    if (error) {
                        log(`Toggle error for dongle${subnet}: ${error.message}`);
                        log(`Toggle stderr: ${stderr}`);
                        log(`Toggle stdout: ${stdout}`);
                        
                        // stdout에 결과가 있으면 파싱 시도
                        if (stdout) {
                            try {
                                const result = JSON.parse(stdout);
                                if (result.error && result.error.includes('already in progress')) {
                                    res.writeHead(409); // Conflict
                                } else {
                                    res.writeHead(500);
                                }
                                res.end(JSON.stringify(result, null, 2));
                                return;
                            } catch (e) {
                                // JSON 파싱 실패
                            }
                        }
                        
                        res.writeHead(500);
                        res.end(JSON.stringify({ 
                            error: 'Toggle failed', 
                            details: stderr || error.message,
                            stdout: stdout
                        }));
                        return;
                    }
                    
                    try {
                        const result = JSON.parse(stdout);
                        res.writeHead(200);
                        res.end(JSON.stringify(result, null, 2));
                    } catch (parseError) {
                        res.writeHead(500);
                        res.end(JSON.stringify({ 
                            error: 'Invalid response from toggle script',
                            output: stdout
                        }));
                    }
                }
            );
            return;
            
        } else {
            // 404
            res.writeHead(404);
            res.end(JSON.stringify({ error: 'Not found' }));
        }
    } catch (error) {
        log(`Server error: ${error.message}`);
        res.writeHead(500);
        res.end(JSON.stringify({ error: 'Internal server error' }));
    }
});

// 최근 로그 가져오기
async function getRecentLogs(lines) {
    return new Promise((resolve) => {
        exec(`tail -n ${lines} ${LOG_FILE} 2>/dev/null`, (error, stdout) => {
            if (error) {
                resolve([]);
                return;
            }
            resolve(stdout.trim().split('\n').filter(line => line));
        });
    });
}

// 서버 시작
server.listen(PORT, '0.0.0.0', () => {
    log(`Health check server started on port ${PORT}`);
    console.log(`Health check server listening on http://0.0.0.0:${PORT}`);
    console.log('Available endpoints:');
    console.log('  GET /         - Basic health check');
    console.log('  GET /status   - Detailed status with logs');
    console.log('  GET /interfaces - Network interface information');
    console.log('  GET /logs     - Recent log entries');
    console.log('  GET /connectivity - Dongle connectivity status');
    console.log('  GET /clean-stale-routes - Clean stale routing entries');
    console.log('  GET /toggle/<subnet> - Toggle dongle IP (e.g., /toggle/11)');
    console.log('  GET /apn - Check APN for all dongles');
    console.log('  GET /apn/<subnet> - Check APN for specific dongle');
    console.log('  GET /fix-apn/<subnet> - Fix APN for specific dongle');
    console.log('  GET /toggle-status/<subnet> - Check toggle progress status');
    console.log('  GET /proxy-info - Get SOCKS5 proxy connection info');
});

// 종료 처리
process.on('SIGINT', () => {
    log('Health check server stopping...');
    server.close(() => {
        log('Health check server stopped');
        process.exit(0);
    });
});

process.on('SIGTERM', () => {
    log('Health check server stopping...');
    server.close(() => {
        log('Health check server stopped');
        process.exit(0);
    });
});