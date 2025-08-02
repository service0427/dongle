#!/usr/bin/env node

const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

// 동글 연결성 체크
async function checkDongleConnectivity(subnet) {
    const interface = `192.168.${subnet}.100`;
    
    try {
        // 1. 인터페이스 존재 확인
        const { stdout: ifaceCheck } = await execPromise(`ip addr show | grep "${interface}" | wc -l`);
        if (parseInt(ifaceCheck.trim()) === 0) {
            return { subnet, status: 'not_connected', ip: null };
        }
        
        // 2. 간단한 연결성 테스트 (DNS 쿼리)
        try {
            await execPromise(
                `curl --interface ${interface} -s -m 3 -o /dev/null -w "%{http_code}" http://1.1.1.1`
            );
        } catch (e) {
            return { subnet, status: 'no_internet', ip: interface };
        }
        
        return {
            subnet,
            status: 'connected',
            ip: interface
        };
        
    } catch (error) {
        // 라우팅은 있지만 인터페이스가 없는 경우 체크
        try {
            const { stdout: ruleCheck } = await execPromise(`ip rule list | grep "from ${interface}" | wc -l`);
            if (parseInt(ruleCheck.trim()) > 0) {
                return { subnet, status: 'stale_route', ip: interface };
            }
        } catch (e) {}
        
        return { subnet, status: 'error', ip: interface, error: error.message };
    }
}

// 모든 동글 체크
async function checkAllDongles() {
    const results = [];
    
    // 11-30번 동글 체크
    for (let i = 11; i <= 30; i++) {
        const result = await checkDongleConnectivity(i);
        if (result.status !== 'not_connected') {
            results.push(result);
        }
    }
    
    return results;
}

// Stale route 정리
async function cleanStaleRoutes() {
    const dongles = await checkAllDongles();
    const staleRoutes = dongles.filter(d => d.status === 'stale_route');
    
    for (const dongle of staleRoutes) {
        const subnet = dongle.subnet;
        console.log(`Cleaning stale route for dongle${subnet}...`);
        
        try {
            await execPromise(`ip rule del from 192.168.${subnet}.100 2>/dev/null`);
            await execPromise(`ip route flush table dongle${subnet} 2>/dev/null`);
            await execPromise(`iptables -t nat -D POSTROUTING -s 192.168.${subnet}.0/24 -j MASQUERADE 2>/dev/null`);
        } catch (e) {
            // Ignore errors
        }
    }
    
    return staleRoutes.length;
}

// Export for use in health_check.js
module.exports = {
    checkDongleConnectivity,
    checkAllDongles,
    cleanStaleRoutes
};

// CLI 실행
if (require.main === module) {
    checkAllDongles().then(async results => {
        console.log('=== Dongle Connectivity Status ===');
        console.log(JSON.stringify(results, null, 2));
        
        // Stale routes 정리
        const cleaned = await cleanStaleRoutes();
        if (cleaned > 0) {
            console.log(`\nCleaned ${cleaned} stale routes.`);
        }
    });
}