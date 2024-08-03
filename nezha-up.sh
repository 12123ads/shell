#!/bin/bash

version="v0.18.13"
ARCH=$(uname -m)
arch=""

if [ "$ARCH" = "aarch64" ]; then
    arch="arm64"
else
    arch="amd64"
fi

if systemctl is-active --quiet nezha-agent; then
    systemctl stop nezha-agent
    wget -q https://github.com/nezhahq/agent/releases/download/$version/nezha-agent_linux_$arch.zip -O /tmp/nezha-agent.zip
    unzip -o -q /tmp/nezha-agent.zip -d /opt/nezha/agent/
    rm /tmp/nezha-agent.zip
    sed -i 's/ip.rxzh.cf/status.xzh.gs/' /etc/systemd/system/nezha-agent.service
    if grep -q -F "--disable-auto-update" /etc/systemd/system/nezha-agent.service; then
        echo "--disable-auto-update exists in nezha-agent.service"
    else
        sed -i 's/--tls/--tls --disable-auto-update/' /etc/systemd/system/nezha-agent.service
    fi
    systemctl daemon-reload
    systemctl start nezha-agent
    echo "nezha-agent服务已重启"
else
    echo "nezha-agent服务不存在"
fi