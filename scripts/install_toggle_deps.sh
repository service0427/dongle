#!/bin/bash

# Python toggle 기능 의존성 설치 스크립트

echo "=== Installing Python dependencies for toggle feature ==="

# pip 설치
if ! command -v pip3 &> /dev/null; then
    echo "Installing pip3..."
    sudo dnf install -y python3-pip
fi

# huawei-lte-api 패키지 설치
echo "Installing huawei-lte-api..."
pip3 install huawei-lte-api requests

echo "Dependencies installed successfully!"
echo ""
echo "You can now use the toggle feature:"
echo "  curl http://localhost:8080/toggle/11"
echo "  curl http://localhost:8080/toggle/16"