/**
 * Playwright example using dongle SOCKS5 proxy
 * This shows how to connect from external servers without being detected as proxy
 */

const { chromium } = require('playwright');

async function testWithDongleProxy() {
    // Get proxy info from API
    const proxyInfoResponse = await fetch('http://112.161.54.7:8080/proxy-info');
    const proxyInfo = await proxyInfoResponse.json();
    
    if (proxyInfo.proxies.length === 0) {
        console.error('No available dongles');
        return;
    }
    
    // Use first available dongle
    const proxy = proxyInfo.proxies[0];
    console.log(`Using dongle ${proxy.subnet} proxy at ${proxy.host}:${proxy.socks5_port}`);
    
    // Launch browser with SOCKS5 proxy
    const browser = await chromium.launch({
        proxy: {
            server: `socks5://${proxy.host}:${proxy.socks5_port}`
        },
        headless: false,
        args: [
            '--disable-blink-features=AutomationControlled',
            '--disable-features=IsolateOrigins,site-per-process',
            '--disable-dev-shm-usage',
            '--no-sandbox',
            '--disable-web-security',
            '--disable-setuid-sandbox'
        ]
    });
    
    const context = await browser.newContext({
        viewport: { width: 390, height: 844 }, // iPhone 12 Pro viewport
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1',
        locale: 'ko-KR',
        timezoneId: 'Asia/Seoul',
        // Disable WebRTC leak
        permissions: [],
        // Mobile device emulation
        isMobile: true,
        hasTouch: true,
        deviceScaleFactor: 3
    });
    
    // Additional anti-detection measures
    await context.addInitScript(() => {
        // Override navigator properties
        Object.defineProperty(navigator, 'webdriver', {
            get: () => undefined
        });
        
        // Override chrome property
        Object.defineProperty(window, 'chrome', {
            get: () => undefined
        });
        
        // Override permissions
        const originalQuery = window.navigator.permissions.query;
        window.navigator.permissions.query = (parameters) => (
            parameters.name === 'notifications' ?
                Promise.resolve({ state: Notification.permission }) :
                originalQuery(parameters)
        );
        
        // Override plugins
        Object.defineProperty(navigator, 'plugins', {
            get: () => [1, 2, 3, 4, 5]
        });
        
        // Override language
        Object.defineProperty(navigator, 'language', {
            get: () => 'ko-KR'
        });
        
        Object.defineProperty(navigator, 'languages', {
            get: () => ['ko-KR', 'ko']
        });
    });
    
    const page = await context.newPage();
    
    // Check IP
    await page.goto('https://ipinfo.io/json');
    const ipInfo = await page.textContent('pre');
    console.log('Current IP info:', ipInfo);
    
    // Test some website
    await page.goto('https://www.naver.com');
    await page.screenshot({ path: 'naver_mobile.png' });
    
    // Check for proxy detection
    await page.goto('https://browserleaks.com/proxy');
    await page.waitForTimeout(5000);
    await page.screenshot({ path: 'proxy_check.png' });
    
    await browser.close();
}

// Toggle dongle IP if needed
async function toggleDongleIP(subnet) {
    const response = await fetch(`http://112.161.54.7:8080/toggle/${subnet}`);
    const result = await response.json();
    console.log('Toggle result:', result);
    return result.success;
}

// Main execution
(async () => {
    try {
        await testWithDongleProxy();
    } catch (error) {
        console.error('Error:', error);
    }
})();