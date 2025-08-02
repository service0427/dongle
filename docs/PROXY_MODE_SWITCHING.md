# Proxy Mode Switching Guide

## Overview
The proxy system can operate in two modes to match different device fingerprints:
- **Mobile Mode**: Makes traffic appear as coming from a mobile device
- **PC Mode**: Makes traffic appear as coming from a desktop PC

## Quick Commands

```bash
# Check current mode
/home/proxy/network-monitor/scripts/switch_proxy_mode.sh status

# Switch to mobile mode
/home/proxy/network-monitor/scripts/switch_proxy_mode.sh mobile

# Switch to PC mode
/home/proxy/network-monitor/scripts/switch_proxy_mode.sh pc
```

## Mode Differences

### Mobile Mode (Default)
- **TTL**: 64 (iOS/Android default)
- **TCP MSS**: 1400 (mobile network characteristic)
- **TCP Window**: Smaller values typical of mobile
- **Appearance**: Mobile device on cellular network

### PC Mode
- **TTL**: 128 (Windows default)
- **TCP MSS**: 1460 (ethernet standard)
- **TCP Window**: Larger values for desktop
- **Appearance**: Desktop PC on broadband connection

## Technical Details

### What Changes
1. **TTL (Time To Live)**: Network packet hop count
   - Mobile devices: 64
   - Windows PCs: 128
   - Linux/Mac: 64

2. **TCP MSS (Maximum Segment Size)**: 
   - Mobile networks: 1400 bytes
   - Ethernet: 1460 bytes

3. **TCP Options**:
   - Window scaling
   - Timestamps
   - SACK/FACK settings

### Files Involved
- `/home/proxy/network-monitor/scripts/proxy_stealth_setup.sh` - Mobile configuration
- `/home/proxy/network-monitor/scripts/proxy_stealth_setup_pc.sh` - PC configuration
- `/home/proxy/network-monitor/scripts/switch_proxy_mode.sh` - Mode switcher

## When to Use Each Mode

### Use Mobile Mode When:
- Simulating mobile app traffic
- Testing mobile-specific features
- Default for most use cases

### Use PC Mode When:
- Simulating desktop browser traffic
- Testing PC-specific features
- Services that detect mobile traffic

## Verification

After switching modes, verify with:
```bash
# Check TTL from external perspective
curl --socks5 112.161.54.7:10011 http://httpbin.org/headers
```

The proxy remains transparent in both modes - no proxy headers are sent.